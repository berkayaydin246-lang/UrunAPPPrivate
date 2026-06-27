# Claude Vision OCR Backend

## Why Claude Vision

Claude Vision (Anthropic) is used as the sole OCR engine for the production ingredient extraction backend because:

- It reads both text and image context simultaneously — critical for labels where ingredient lists are split across multiple visual zones.
- It handles Turkish characters (ç, ğ, ı, ö, ş, ü) and E-codes reliably without post-processing heuristics.
- A single API call replaces the previous two-step pipeline (OCR engine → LLM structuring), reducing latency and failure points.
- The prompt is fully controlled: Claude is explicitly prohibited from making health claims, scoring products, or inferring information not visibly present.

## Why Google Vision was removed

The previous pipeline used Google Cloud Vision for raw text extraction followed by OpenAI for structuring. This caused several problems:

- Google Cloud Vision required a service account JSON file — difficult to manage securely in deployment.
- Two separate API calls meant double the latency and double the failure surface.
- OpenAI's output required strict JSON mode; Claude returns structured JSON natively when prompted correctly.
- The dependency chain (`google-cloud-vision`, `openai`) added unnecessary complexity.

## Why Claude does NOT score products

Health scoring is entirely handled by the Flutter `AnalysisEngine` — a deterministic, rule-based engine that matches ingredients against the local database and applies fixed scoring rules.

Claude's role is strictly limited to **reading visible text from an image**. This separation is intentional:

- Determinism: the same ingredient list always produces the same score.
- Auditability: scoring rules are in source code, not an LLM's training weights.
- Safety: Claude cannot hallucinate a risk level for an ingredient it "thinks" is harmful.
- Regulatory: medical or health claims must not come from a generative model.

The Claude prompt explicitly states: *Do NOT give health advice. Do NOT classify ingredient risk. Do NOT score the product. Do NOT make any medical claims.*

## Backend `.env` variables

| Variable | Required | Description |
|---|---|---|
| `CLAUDE_API_KEY` | ✅ | Anthropic API key from console.anthropic.com |
| `OCR_BACKEND_API_KEY` | recommended | Secret Bearer token — must match Flutter's `OCR_BACKEND_API_KEY` |
| `CLAUDE_MODEL` | optional | Default: `claude-sonnet-4-6`. Use `claude-haiku-4-5-20251001` for lower cost. |
| `PORT` | optional | Default: `8000` |
| `CORS_ORIGINS` | optional | Default: `*` (restrict to your domain in production) |

## Flutter `.env` variables

| Variable | Description |
|---|---|
| `OCR_BACKEND_URL` | Full base URL of the deployed backend, e.g. `https://ocr.example.com` |
| `OCR_BACKEND_API_KEY` | Must match `OCR_BACKEND_API_KEY` on the server |

Leave both blank to disable advanced OCR — ML Kit local OCR continues to work without any backend.

## Running locally

```bash
cd backend/ocr_service
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Fill in CLAUDE_API_KEY and OCR_BACKEND_API_KEY in .env
uvicorn main:app --reload --port 8000
```

Test the health endpoint:
```bash
curl http://localhost:8000/health
# {"status":"ok"}
```

Test ingredient extraction (replace URL and keys):
```bash
curl -X POST http://localhost:8000/ocr/ingredients \
  -H "Authorization: Bearer your-secret-backend-api-key" \
  -H "Content-Type: application/json" \
  -d '{"image_url":"https://...", "language_hint":"tr", "mode":"ingredients_label"}'
```

## Deploying

Any Python ASGI host works (Railway, Render, Fly.io, etc.):

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Set `CLAUDE_API_KEY`, `OCR_BACKEND_API_KEY`, and optionally `CORS_ORIGINS` as environment secrets in the platform. Never commit `.env`.

## Cost control notes

- Images > 5 MB are rejected before reaching Claude (HTTP 413).
- Images > 800 KB are automatically resized and compressed to JPEG 85% with max 1568 px dimension (Pillow). This keeps base64 payload small.
- Each request = one Claude API call. No double-charging.
- Switch to `claude-haiku-4-5-20251001` for roughly 20× lower cost per token when accuracy requirements allow.
- Claude Vision charges are based on input image size + token count. Compression significantly reduces image token cost.

## Flutter confidence threshold

Ingredients with `confidence < 0.85` returned by the backend are placed in `uncertainItems` in the Flutter model and **do not affect analysis scoring**. Only `confirmedIngredients` (confidence ≥ 0.85) reach the `AnalysisEngine`. This threshold is defined in `StructuredIngredientExtractionResult.confirmedConfidenceThreshold`.
