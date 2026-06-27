# OCR Service — Claude Vision Backend

FastAPI backend that extracts ingredient data from Turkish packaged food label images using Claude Vision (Anthropic).

## Architecture

```
Flutter app
  └─ ProductionOcrService
       ├─ uploads image to Supabase Storage (ocr-temp bucket)
       ├─ POST /ocr/ingredients  { image_url, language_hint, mode }
       │       ↓
       │   FastAPI (this service)
       │     1. Verify Bearer token
       │     2. Download image from Supabase URL
       │     3. Validate size (max 5 MB)
       │     4. Compress / resize if > 800 KB (Pillow)
       │     5. Base64-encode → Claude Vision API
       │     6. Parse JSON response
       │     7. Return IngredientResponse
       └─ Flutter deletes temp file from Storage
```

## What Claude does (and does NOT do)

| Task | Claude |
|---|---|
| Read visible ingredient text from image | ✅ |
| Preserve Turkish characters (ç ğ ı ö ş ü) | ✅ |
| Preserve E-codes (E250, E330 …) | ✅ |
| Flag unclear items in uncertain_items | ✅ |
| Give health advice | ❌ never |
| Score product risk | ❌ never |
| Make medical claims | ❌ never |

Health scoring remains in the Flutter rule-based `AnalysisEngine` — Claude never influences it.

## Setup

### 1. Create and activate virtualenv

```bash
cd backend/ocr_service
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
```

### 2. Install dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env and fill in CLAUDE_API_KEY and OCR_BACKEND_API_KEY
```

### 4. Run locally

```bash
uvicorn main:app --reload --port 8000
```

Health check: `GET http://localhost:8000/health`

## API

### POST /ocr/ingredients

**Headers:**
```
Authorization: Bearer <OCR_BACKEND_API_KEY>
Content-Type: application/json
```

**Request body:**
```json
{
  "image_url": "https://...",
  "language_hint": "tr",
  "mode": "ingredients_label"
}
```

**Response:**
```json
{
  "raw_text": "su, un, tuz, sodyum nitrit (E250)",
  "cleaned_text": "su, un, tuz, sodyum nitrit",
  "ingredients": [
    { "name": "su", "original_text": "su", "e_code": null, "confidence": 0.99 },
    { "name": "sodyum nitrit", "original_text": "sodyum nitrit (E250)", "e_code": "E250", "confidence": 0.97 }
  ],
  "e_codes": ["E250"],
  "uncertain_items": [],
  "warnings": [],
  "quality_score": 0.92
}
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `CLAUDE_API_KEY` | ✅ | Anthropic API key |
| `OCR_BACKEND_API_KEY` | recommended | Bearer token Flutter must send |
| `CLAUDE_MODEL` | optional | Default: `claude-sonnet-4-6` |
| `PORT` | optional | Default: `8000` |
| `CORS_ORIGINS` | optional | Default: `*` |

## Cost control

- Images larger than 5 MB are rejected before hitting Claude.
- Images larger than 800 KB are resized/compressed to JPEG 85% with max 1568 px dimension before encoding.
- Use `CLAUDE_MODEL=claude-haiku-4-5-20251001` for lower cost in high-volume scenarios.
- Claude is only called once per request (no separate OCR + parsing steps).

## Deployment

Any platform that can run a Python ASGI app works (Railway, Fly.io, Render, etc.):

```bash
uvicorn main:app --host 0.0.0.0 --port $PORT
```

Set all environment variables in the platform's secret store. Do **not** commit `.env`.
