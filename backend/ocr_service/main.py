from __future__ import annotations
from dotenv import load_dotenv
load_dotenv()
import base64
import io
import json
import logging
import os
import re
import traceback
from typing import Any
from urllib.parse import urlparse

import httpx
from anthropic import Anthropic, APIConnectionError, APIStatusError, APITimeoutError
from fastapi import Depends, FastAPI, HTTPException, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, HttpUrl

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("ocr_service")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Claude model — override via env for cost tuning (haiku = cheaper, opus = better).
_CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

# Hard limit: reject images larger than this before sending to Claude.
_MAX_RAW_BYTES = 5 * 1024 * 1024  # 5 MB

# Resize threshold: compress images larger than this before encoding.
_COMPRESS_THRESHOLD_BYTES = 800_000  # 800 KB

# Maximum dimension (px) after resize — Claude Vision works well up to ~1568 px.
_MAX_IMAGE_DIM = 1568

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(title="OCR Service — Claude Vision", version="1.0.0")

_cors_origins_raw = os.getenv("CORS_ORIGINS", "*")
_allowed_origins = [o.strip() for o in _cors_origins_raw.split(",") if o.strip()]
if "*" in _allowed_origins:
    _allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Startup diagnostics
# ---------------------------------------------------------------------------


@app.on_event("startup")
def _log_startup_config() -> None:
    claude_key_set = bool(os.getenv("CLAUDE_API_KEY", "").strip())
    backend_key_set = bool(os.getenv("OCR_BACKEND_API_KEY", "").strip())
    logger.info("=== OCR Service startup ===")
    logger.info("CLAUDE_MODEL       : %s", _CLAUDE_MODEL)
    logger.info("CLAUDE_API_KEY set : %s", claude_key_set)
    logger.info("OCR_BACKEND_API_KEY: %s", "set" if backend_key_set else "NOT SET (open access)")
    logger.info("CORS_ORIGINS       : %s", _allowed_origins)
    if not claude_key_set:
        logger.error("CLAUDE_API_KEY is missing — /ocr/ingredients will return HTTP 503")


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

_bearer = HTTPBearer(auto_error=False)


def _verify_api_key(
    credentials: HTTPAuthorizationCredentials | None = Security(_bearer),
) -> None:
    expected = os.getenv("OCR_BACKEND_API_KEY", "").strip()
    if not expected:
        # No key configured — open access (useful for local dev).
        return
    if credentials is None or credentials.credentials != expected:
        logger.warning("Rejected request — invalid or missing Bearer token")
        raise HTTPException(status_code=401, detail="Unauthorized")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class IngredientRequest(BaseModel):
    image_url: HttpUrl
    language_hint: str = Field(default="tr")
    mode: str = Field(default="ingredients_label")


class IngredientItem(BaseModel):
    name: str
    original_text: str
    e_code: str | None = None
    confidence: float = Field(ge=0.0, le=1.0)


class IngredientResponse(BaseModel):
    raw_text: str
    cleaned_text: str
    ingredients: list[IngredientItem]
    e_codes: list[str]
    uncertain_items: list[str]
    warnings: list[str]
    quality_score: float = Field(ge=0.0, le=1.0)
    discarded_fragments: list[str] = Field(default_factory=list)


class ProductLabelRequest(BaseModel):
    image_url: HttpUrl
    language_hint: str = Field(default="tr")


class NutritionFacts(BaseModel):
    energy_kcal: float | None = None
    fat: float | None = None
    saturated_fat: float | None = None
    carbohydrates: float | None = None
    sugars: float | None = None
    fiber: float | None = None
    proteins: float | None = None
    salt: float | None = None
    sodium: float | None = None
    serving_size: str | None = None

    def has_any_data(self) -> bool:
        return any(
            v is not None
            for v in (
                self.energy_kcal, self.fat, self.saturated_fat,
                self.carbohydrates, self.sugars, self.fiber,
                self.proteins, self.salt, self.sodium,
            )
        )

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for field, value in self.__dict__.items():
            if value is not None:
                result[field] = value
        return result


class ProductLabelResponse(BaseModel):
    ingredients: IngredientResponse
    nutrition: dict[str, Any] | None = None
    extraction_status: str  # success | partial | failed


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post(
    "/ocr/ingredients",
    response_model=IngredientResponse,
    dependencies=[Depends(_verify_api_key)],
)
async def extract_ingredients(payload: IngredientRequest) -> IngredientResponse:
    # Debug: log incoming request parameters.
    image_domain = urlparse(str(payload.image_url)).netloc
    logger.debug(
        "extract_ingredients called — image_domain=%s language_hint=%s mode=%s",
        image_domain,
        payload.language_hint,
        payload.mode,
    )

    if payload.mode != "ingredients_label":
        logger.warning("Unsupported mode requested: %s", payload.mode)
        raise HTTPException(
            status_code=400,
            detail={"error": "Unsupported mode", "details": f"mode '{payload.mode}' is not supported", "type": "validation_error"},
        )

    claude_api_key = os.getenv("CLAUDE_API_KEY", "").strip()
    if not claude_api_key:
        logger.error("CLAUDE_API_KEY not set — cannot process OCR request")
        raise HTTPException(
            status_code=503,
            detail={
                "error": "Service unavailable",
                "details": "CLAUDE_API_KEY is not configured on the server.",
                "type": "config_error",
            },
        )

    try:
        image_bytes, media_type = await _download_image(str(payload.image_url))
        _validate_image_size(image_bytes)
        processed_bytes, processed_media_type = _compress_if_needed(
            image_bytes, media_type
        )
        return await _extract_with_claude_vision(
            processed_bytes,
            processed_media_type,
            payload.language_hint,
            claude_api_key,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Unhandled error in extract_ingredients")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "Internal server error",
                "details": str(exc),
                "type": type(exc).__name__,
            },
        ) from exc


@app.post(
    "/ocr/product-label",
    response_model=ProductLabelResponse,
    dependencies=[Depends(_verify_api_key)],
)
async def extract_product_label(payload: ProductLabelRequest) -> ProductLabelResponse:
    """Extract both ingredients text and nutrition facts from a product label photo.

    This endpoint is for data extraction only — it does not score or classify the product.
    Extraction results are stored for admin review; no automatic product approval occurs.
    """
    image_domain = urlparse(str(payload.image_url)).netloc
    logger.debug(
        "extract_product_label called — image_domain=%s language_hint=%s",
        image_domain,
        payload.language_hint,
    )

    claude_api_key = os.getenv("CLAUDE_API_KEY", "").strip()
    if not claude_api_key:
        logger.error("CLAUDE_API_KEY not set — cannot process product-label request")
        raise HTTPException(
            status_code=503,
            detail={
                "error": "Service unavailable",
                "details": "CLAUDE_API_KEY is not configured on the server.",
                "type": "config_error",
            },
        )

    try:
        image_bytes, media_type = await _download_image(str(payload.image_url))
        _validate_image_size(image_bytes)
        processed_bytes, processed_media_type = _compress_if_needed(image_bytes, media_type)
        return await _extract_product_label_with_claude(
            processed_bytes,
            processed_media_type,
            payload.language_hint,
            claude_api_key,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Unhandled error in extract_product_label")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "Internal server error",
                "details": str(exc),
                "type": type(exc).__name__,
            },
        ) from exc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


async def _download_image(url: str) -> tuple[bytes, str]:
    """Download image from URL and return (bytes, media_type)."""
    logger.debug("Downloading image from URL domain: %s", urlparse(url).netloc)
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        response = await client.get(url)
        if response.status_code != 200:
            logger.error(
                "Image download failed — HTTP %s for domain %s",
                response.status_code,
                urlparse(url).netloc,
            )
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "Image download failed",
                    "details": f"Remote server returned HTTP {response.status_code}",
                    "type": "image_fetch_error",
                },
            )
        content_type = response.headers.get("content-type", "")
        media_type = _parse_media_type(content_type, response.content)
        size_kb = len(response.content) // 1024
        logger.debug(
            "Image downloaded — size=%d KB content-type=%s resolved_media_type=%s",
            size_kb,
            content_type,
            media_type,
        )
        return response.content, media_type


def _parse_media_type(content_type: str, data: bytes) -> str:
    """Resolve MIME type from Content-Type header or magic bytes."""
    ct = content_type.split(";")[0].strip().lower()
    if ct in ("image/jpeg", "image/png", "image/gif", "image/webp"):
        return ct
    # Fallback: inspect magic bytes.
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    # Default to JPEG — Claude handles it.
    logger.debug("Could not detect MIME from header or magic bytes — defaulting to image/jpeg")
    return "image/jpeg"


def _validate_image_size(image_bytes: bytes) -> None:
    size = len(image_bytes)
    if size > _MAX_RAW_BYTES:
        logger.warning("Image rejected — %d KB exceeds %d KB limit", size // 1024, _MAX_RAW_BYTES // 1024)
        raise HTTPException(
            status_code=413,
            detail={
                "error": "Image too large",
                "details": f"Image is {size // 1024} KB; maximum allowed is {_MAX_RAW_BYTES // 1024} KB.",
                "type": "image_size_error",
            },
        )


def _compress_if_needed(
    image_bytes: bytes, media_type: str
) -> tuple[bytes, str]:
    """
    Compress and/or resize the image using Pillow when it exceeds the
    compression threshold. Returns the (possibly smaller) bytes and the
    resulting media type (always image/jpeg after compression).
    """
    original_size_kb = len(image_bytes) // 1024
    if len(image_bytes) <= _COMPRESS_THRESHOLD_BYTES:
        logger.debug("Image is %d KB — no compression needed", original_size_kb)
        return image_bytes, media_type

    logger.debug("Image is %d KB — attempting Pillow compression", original_size_kb)
    try:
        from PIL import Image  # type: ignore[import-untyped]

        img = Image.open(io.BytesIO(image_bytes))

        max_dim = max(img.width, img.height)
        if max_dim > _MAX_IMAGE_DIM:
            scale = _MAX_IMAGE_DIM / max_dim
            new_w = max(1, int(img.width * scale))
            new_h = max(1, int(img.height * scale))
            logger.debug(
                "Resizing image from %dx%d to %dx%d",
                img.width, img.height, new_w, new_h,
            )
            img = img.resize((new_w, new_h), Image.LANCZOS)

        buf = io.BytesIO()
        img.convert("RGB").save(buf, format="JPEG", quality=85, optimize=True)
        compressed = buf.getvalue()
        logger.debug(
            "Compression complete — %d KB -> %d KB (saved %d KB)",
            original_size_kb,
            len(compressed) // 1024,
            (len(image_bytes) - len(compressed)) // 1024,
        )
        return compressed, "image/jpeg"
    except Exception:
        logger.warning(
            "Pillow compression failed — sending original %d KB image. Traceback:\n%s",
            original_size_kb,
            traceback.format_exc(),
        )
        return image_bytes, media_type


_SYSTEM_PROMPT = """\
You are a strict ingredient extraction engine for Turkish packaged food labels.

Rules you MUST always follow:
- Extract ONLY ingredients that are visibly printed in the image.
- Do NOT invent ingredients.
- Do NOT infer or guess missing ingredients.
- Preserve Turkish characters exactly: ç, ğ, ı, ö, ş, ü.
- Preserve E-codes exactly as printed — for example E250, E330, E621.
- Extract ingredient names only.
- Do NOT output quantities, percentages, or measurement units as ingredients.
- Do NOT output empty parentheses or broken fragments.
- If an ingredient has a meaningful category + detail, extract both.
    Example: "bitkisel yağlar (ayçiçek, palm)" -> "bitkisel yağlar", "ayçiçek yağı", "palm yağı"
    Example: "emülgatör (lesitinler)" -> "emülgatör", "lesitin"
    Example: "kabartıcı (sodyum karbonatlar)" -> "kabartıcı", "sodyum karbonat"
- If an item is unclear or uncertain, list it under UNCERTAIN, not under INGREDIENTS.
- Do NOT give any health advice.
- Do NOT classify ingredient risk.
- Do NOT score the product.
- Do NOT make any medical claims.
- If no ingredients section is visible, leave INGREDIENTS empty and add a WARNING.

Output format rules (strictly enforced):
- Return ONLY the plain-text format shown in the user message. Nothing else.
- Do NOT use JSON. Do NOT use markdown. Do NOT use code fences.
- Use exactly the section headers shown (RAW_TEXT:, INGREDIENTS:, etc.).
- List each item on its own line starting with "- ".
- If a section has no items, write a single line: "- none"\
"""


def _build_user_prompt(language_hint: str) -> str:
    return f"""\
Read the food ingredient label in this image. Language hint: {language_hint}

Return your answer in this EXACT plain-text format — nothing else, no JSON, no markdown:

RAW_TEXT:
<all visible ingredient text, exactly as printed on the label>

INGREDIENTS:
- ingredient 1
- ingredient 2
- ingredient 3

E_CODES:
- E250
- E330

UNCERTAIN:
- any item you could not read clearly

WARNINGS:
- any extraction issue (e.g. image blurry, no ingredients section visible)

Rules:
- Do NOT use JSON or code fences.
- Extract ingredient names only.
- Do NOT output quantities, percentages, or units such as mg, mg/l, g, ml.
- Do NOT output empty parentheses or broken fragments.
- Preserve Turkish characters: ç, ğ, ı, ö, ş, ü.
- Preserve Turkish characters: ç, ğ, ı, ö, ş, ü.
- Preserve E-codes exactly as printed.
- If ingredient has category + details, extract both when meaningful.
- Example: "bitkisel yağlar (ayçiçek, palm)" -> bitkisel yağlar, ayçiçek yağı, palm yağı
- Example: "emülgatör (lesitinler)" -> emülgatör, lesitin
- Example: "kabartıcı (sodyum karbonatlar)" -> kabartıcı, sodyum karbonat
- If a section has no items, write exactly: "- none"\
"""


async def _extract_with_claude_vision(
    image_bytes: bytes,
    media_type: str,
    language_hint: str,
    api_key: str,
) -> IngredientResponse:
    image_size_kb = len(image_bytes) // 1024
    logger.debug(
        "Calling Claude Vision — model=%s image_size=%d KB media_type=%s language_hint=%s",
        _CLAUDE_MODEL,
        image_size_kb,
        media_type,
        language_hint,
    )

    b64_data = base64.standard_b64encode(image_bytes).decode()

    try:
        client = Anthropic(api_key=api_key)
        message = client.messages.create(
            model=_CLAUDE_MODEL,
            max_tokens=2048,
            system=_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": b64_data,
                            },
                        },
                        {
                            "type": "text",
                            "text": _build_user_prompt(language_hint),
                        },
                    ],
                }
            ],
        )
    except APIStatusError as exc:
        logger.error(
            "Claude API returned error status — status=%s message=%s\n%s",
            exc.status_code,
            exc.message,
            traceback.format_exc(),
        )
        raise HTTPException(
            status_code=502,
            detail={
                "error": "Claude API error",
                "details": f"HTTP {exc.status_code}: {exc.message}",
                "type": "claude_api_status_error",
            },
        ) from exc
    except APITimeoutError as exc:
        logger.error("Claude API timed out\n%s", traceback.format_exc())
        raise HTTPException(
            status_code=504,
            detail={
                "error": "Claude API timeout",
                "details": str(exc),
                "type": "claude_api_timeout",
            },
        ) from exc
    except APIConnectionError as exc:
        logger.error("Claude API connection error\n%s", traceback.format_exc())
        raise HTTPException(
            status_code=502,
            detail={
                "error": "Claude API connection error",
                "details": str(exc),
                "type": "claude_api_connection_error",
            },
        ) from exc

    raw_content = message.content[0].text.strip() if message.content else ""
    logger.debug("Claude response received — raw_content_length=%d chars", len(raw_content))

    if not raw_content:
        return _build_fallback_response("", "Claude returned an empty response")

    # Primary path: plain-text section format (what we ask Claude to produce).
    # This avoids all JSON-parsing failure modes: fences, bad escapes, truncation.
    if _looks_like_plain_text_format(raw_content):
        try:
            parsed_plain = _parse_plain_text_response(raw_content)
            ingredient_count = len(parsed_plain.get("ingredients", []))
            logger.debug(
                "Plain-text format parsed — %d ingredients, %d e_codes, %d uncertain",
                ingredient_count,
                len(parsed_plain.get("e_codes", [])),
                len(parsed_plain.get("uncertain_items", [])),
            )
            return _build_response_from_plain(parsed_plain)
        except Exception as exc:
            logger.warning(
                "Plain-text parsing failed, trying JSON fallback — error: %s\n%s",
                exc,
                traceback.format_exc(),
            )

    # Backward-compatible fallback: Claude returned JSON despite instructions.
    logger.debug("Attempting JSON fallback parsing")
    try:
        parsed_json, was_repaired = _parse_claude_json(raw_content)
        if was_repaired:
            logger.debug("Claude JSON was repaired before parsing")
        return _build_response(parsed_json)
    except ValueError as exc:
        logger.error(
            "Neither plain-text nor JSON parsing succeeded — raw_content=%r\n%s",
            raw_content[:500],
            traceback.format_exc(),
        )
        return _build_fallback_response(raw_content, str(exc))


def _looks_like_plain_text_format(text: str) -> bool:
    """Return True when Claude's response is our plain-text section format, not JSON."""
    stripped = text.lstrip()
    # JSON starts with { or [ — skip to JSON fallback path.
    if stripped.startswith("{") or stripped.startswith("["):
        return False
    upper = text.upper()
    return any(
        marker in upper
        for marker in ("RAW_TEXT:", "INGREDIENTS:", "E_CODES:", "UNCERTAIN:", "WARNINGS:")
    )


_ECODE_RE = re.compile(r"\b(E\d{3,4}[a-z]?)\b", re.IGNORECASE)
_UNCERTAIN_MARKERS = ("?", "belirsiz", "unclear", "okunamadı", "okunamadi")
_EMPTY_MARKERS = frozenset(("none", "yok", "-", ""))
_UNITS_RE = re.compile(r"^(mg|g|kg|ml|l|mcg|μg|ug|mg/l|g/l|ml/l)$", re.IGNORECASE)
_NUMERIC_RE = re.compile(r"^[\d\s.,/%+-]+$")
_PUNCT_ONLY_RE = re.compile(r"^[\W_]+$", re.UNICODE)

_CANONICAL_EXPANSIONS: dict[str, str] = {
    "bitkisel yağ": "bitkisel yağlar",
    "bitkisel yağlar": "bitkisel yağlar",
    "palm": "palm yağı",
    "palmiye yağı": "palm yağı",
    "ayçiçek": "ayçiçek yağı",
    "ayçiçeği": "ayçiçek yağı",
    "ayçiçek yağı": "ayçiçek yağı",
    "sunflower": "ayçiçek yağı",
    "sunflower oil": "ayçiçek yağı",
    "kolza": "kanola yağı",
    "kanola": "kanola yağı",
    "hindistan cevizi": "hindistan cevizi yağı",
    "lesitinler": "lesitin",
    "soya lesitini": "lesitin",
    "mono ve digliseritler": "mono ve digliseritler",
    "mono ve digliseritleri": "mono ve digliseritler",
    "mono- ve digliseritler": "mono ve digliseritler",
    "mono- ve digliseritleri": "mono ve digliseritler",
    "yağ asitlerinin mono ve digliseritleri": "mono ve digliseritler",
    "yağ asitlerinin mono- ve digliseritleri": "mono ve digliseritler",
    "sodyum karbonatlar": "sodyum karbonat",
    "kabartıcılar": "kabartıcı",
    "aroma verici": "aroma vericiler",
    "aroma vericiler": "aroma vericiler",
    "arpa malt ekstraktı": "malt ekstraktı",
    "malt ekstraktı": "malt ekstraktı",
    "yağı azaltılmış kakao tozu": "kakao tozu",
    "yağsız süt tozu": "süt tozu",
    "fındık püresi": "fındık",
    "süt tozu": "süt tozu",
    # canonical forms for common variants
    "palm yağı": "palm yağı",
    "kanola yağı": "kanola yağı",
    "hindistan cevizi yağı": "hindistan cevizi yağı",
    "emülgatör": "emülgatör",
    "lesitin": "lesitin",
    "kabartıcı": "kabartıcı",
    "sodyum karbonat": "sodyum karbonat",
    "kalsiyum karbonat": "kalsiyum karbonat",
    "sitrik asit": "sitrik asit",
    "aroma vericiler": "aroma vericiler",
    "antioksidan": "antioksidan",
    "tokoferolce zengin ekstrakt": "tokoferolce zengin ekstrakt",
    "şeker": "şeker",
    "pirinç unu": "pirinç unu",
    "patlamış pirinç": "patlamış pirinç",
    "buğday unu": "buğday unu",
    "bulgur unu": "bulgur unu",
    "kakao tozu": "kakao tozu",
    "fındık": "fındık",
    "peynir altı suyu tozu": "peynir altı suyu tozu",
    "peyniraltı suyu tozu": "peynir altı suyu tozu",
}


def split_top_level_commas(text: str) -> list[str]:
    """Split on commas/semicolons at top-level (ignore commas inside parentheses).

    Returns list of raw fragments (trimmed).
    """
    parts: list[str] = []
    buf: list[str] = []
    depth = 0
    for ch in text:
        if ch == '(':
            depth += 1
            buf.append(ch)
            continue
        if ch == ')':
            if depth > 0:
                depth -= 1
            buf.append(ch)
            continue
        if depth == 0 and (ch == ',' or ch == ';'):
            part = ''.join(buf).strip()
            if part:
                parts.append(part)
            buf = []
            continue
        buf.append(ch)
    tail = ''.join(buf).strip()
    if tail:
        parts.append(tail)
    return parts


def extract_parenthetical_items(token: str) -> list[str]:
    """Extract top-level parenthetical groups from token, handling unclosed parens.

    Returns list of inner strings (raw), empty if none.
    """
    inners: list[str] = []
    stack: list[int] = []
    start = None
    for i, ch in enumerate(token):
        if ch == '(':
            if start is None:
                start = i + 1
            stack.append(i)
        elif ch == ')' and stack:
            stack.pop()
            if not stack and start is not None:
                inners.append(token[start:i].strip())
                start = None
    # If unclosed parentheses (start not None), take trailing substring after first '('
    if start is not None:
        trailing = token[start:].strip()
        if trailing:
            inners.append(trailing)
    return inners


def normalize_ingredient_fragment(text: str) -> str:
    """Normalize a fragment for internal use (clean, collapse spaces, lower).
    Keeps Turkish characters.
    """
    t = clean_ingredient_fragment(text)
    t = re.sub(r"\s+", " ", t).strip().lower()
    return t


def canonicalize_ingredient_name(text: str) -> str:
    """Map a normalized fragment to canonical expansion if known.

    Falls back to the normalized text.
    """
    n = normalize_ingredient_fragment(text)
    if not n:
        return n
    # direct mapping
    if n in _CANONICAL_EXPANSIONS:
        return _CANONICAL_EXPANSIONS[n]
    # try removing trailing 'yağı' variants or plural endings
    stripped = re.sub(r"\s+yağ(?:ı|i)?$", "", n)
    if stripped in _CANONICAL_EXPANSIONS:
        return _CANONICAL_EXPANSIONS[stripped]
    # fallback: return n
    return n


def discard_non_ingredient_fragment(text: str) -> bool:
    """Return True when fragment should be discarded from ingredient list."""
    return should_discard_fragment(text)


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for it in items:
        if not it:
            continue
        k = canonicalize_ingredient_name(it)
        if not k or k in seen:
            continue
        seen.add(k)
        out.append(k)
    return out


def parse_ingredient_text_to_items(text: str) -> list[str]:
    """Parse a single ingredient line into atomic ingredient names.

    This is deterministic and rule-based. Handles top-level commas,
    nested parentheses (best-effort), percentages, units, and known
    category+subingredient patterns.
    """
    if not text or not text.strip():
        return []

    tokens = split_top_level_commas(text)
    collected: list[str] = []
    discarded: list[str] = []

    for tok in tokens:
        tok = tok.strip()
        if not tok:
            continue

        # Extract parenthetical items
        inners = extract_parenthetical_items(tok)

        # Outer base (before first '(')
        outer = tok.split('(', 1)[0].strip()
        outer_norm = canonicalize_ingredient_name(outer) if outer else ''

        # Prefer to add outer if it's a plausible ingredient
        if outer_norm and not discard_non_ingredient_fragment(outer_norm):
            collected.append(outer_norm)
        elif outer and not inners:
            # if no inner items and outer is messy, try cleaning and keep
            cleaned = normalize_ingredient_fragment(outer)
            if cleaned and not discard_non_ingredient_fragment(cleaned):
                collected.append(cleaned)

        # Process inner parenthetical groups
        for inner in inners:
            # split inner by top-level commas/slashes/ve
            parts = re.split(r',|/|;|\s+ve\s+', inner)
            for part in parts:
                p = part.strip()
                if not p:
                    continue
                # clean percent/units
                p = re.sub(r"%\s*\d+", "", p)
                p = re.sub(r"\b(\d+[.,]?\d*\s*(mg|g|kg|ml|l|mg/l|g/l))\b", "", p, flags=re.IGNORECASE)
                p = p.strip(' ,;')
                if not p:
                    continue

                # heuristics: mono- ve digliseritleri -> mono ve digliseritler
                p = re.sub(r"mono\s*[-–—]?\s*ve\s*digliseritleri", "mono ve digliseritler", p, flags=re.IGNORECASE)
                p = re.sub(r"digliseritleri", "digliseritler", p, flags=re.IGNORECASE)
                p = re.sub(r"yağ asitlerinin\s*", "", p, flags=re.IGNORECASE)

                cand = p
                # If outer indicates oils, append 'yağı' when inner is short name
                if outer_norm and 'yağ' in outer_norm and len(cand.split()) <= 2:
                    # avoid double 'yağı'
                    if not re.search(r'yağ', cand, re.IGNORECASE):
                        cand = f"{cand} yağı"

                # canonicalize
                can = canonicalize_ingredient_name(cand)
                if discard_non_ingredient_fragment(can):
                    discarded.append(can)
                    continue
                collected.append(can)

    # final dedupe and preserve order
    return dedupe_preserve_order(collected)


def normalize_ingredient_name(text: str) -> str:
    """Normalize an ingredient name to a canonical, display-safe form."""
    cleaned = clean_ingredient_fragment(text)
    cleaned = re.sub(r"\s+", " ", cleaned).strip().lower()
    cleaned = cleaned.replace("i̇", "i")
    cleaned = cleaned.replace("ı", "ı")
    return _CANONICAL_EXPANSIONS.get(cleaned, cleaned)


def should_discard_fragment(fragment: str) -> bool:
    cleaned = clean_ingredient_fragment(fragment)
    if not cleaned:
        return True
    lowered = cleaned.lower()
    if lowered in _EMPTY_MARKERS:
        return True
    if _UNITS_RE.match(lowered):
        return True
    if _NUMERIC_RE.match(lowered):
        return True
    if _PUNCT_ONLY_RE.match(lowered):
        return True
    if len(lowered) <= 1:
        return True
    if re.match(r"^\d+\s+\D+", lowered) and not lowered.startswith("e"):
        return True
    if lowered in {"()", "[]", "{}"}:
        return True
    return False


def clean_ingredient_fragment(fragment: str) -> str:
    text = fragment.strip()
    if not text:
        return ""
    text = text.replace("•", " ").replace("·", " ")
    text = text.replace("\u2022", " ")
    text = re.sub(r"[\[\]{}]", " ", text)
    text = re.sub(r"\s+", " ", text)
    text = text.strip(" ,;:/-–—")
    text = re.sub(r"\(\s*\)", "", text)
    text = re.sub(r"\b\d+(?:[.,]\d+)?\s*%\b", "", text)
    text = re.sub(r"\b\d+(?:[.,]\d+)?\s*(mg/l|mg|g/l|g|kg|ml/l|ml|l|mcg|μg|ug)\b", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def expand_compound_ingredient(fragment: str) -> list[str]:
    text = clean_ingredient_fragment(fragment)
    if not text:
        return []

    normalized = normalize_ingredient_name(text)
    expansions: list[str] = [normalized]

    if "(" in text and ")" in text:
        outer = clean_ingredient_fragment(text.split("(", 1)[0])
        inner = text[text.find("(") + 1 : text.rfind(")")]
        outer_norm = normalize_ingredient_name(outer)
        if outer_norm:
            expansions.append(outer_norm)

        inner_parts = re.split(r"[,/;]|\s+ve\s+", inner)
        for part in inner_parts:
            candidate = clean_ingredient_fragment(part)
            if not candidate:
                continue
            candidate_norm = normalize_ingredient_name(candidate)
            if candidate_norm in {"palm", "palmiye yağı", "ayçiçek", "ayçiçeği"}:
                candidate_norm = normalize_ingredient_name(candidate_norm)
            if outer_norm in {"bitkisel yağ", "bitkisel yağlar", "yağ", "yağlar", "emülgatör", "kabartıcı", "antioksidan"}:
                if candidate_norm in {"palm", "ayçiçek", "palmiye yağı", "ayçiçeği"}:
                    candidate_norm = normalize_ingredient_name(candidate_norm)
                elif outer_norm in {"bitkisel yağ", "bitkisel yağlar", "yağ", "yağlar"} and candidate_norm:
                    candidate_norm = normalize_ingredient_name(candidate_norm)
            expansions.append(candidate_norm)

    # Smart derivations for known broken fragments.
    if normalized.endswith(" yağı") and normalized[:-5] in {"palm", "ayçiçek"}:
        expansions.append(normalize_ingredient_name(normalized[:-5]))

    return expansions


def dedupe_ingredients(items: list[str]) -> list[str]:
    seen: set[str] = set()
    deduped: list[str] = []
    for item in items:
        normalized = normalize_ingredient_name(item)
        if should_discard_fragment(normalized):
            continue
        if normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)
    return deduped


def _parse_plain_text_response(text: str) -> dict[str, Any]:
    """
    Parse Claude's plain-text section response into a structured dict.

    Expected format (section order may vary):
        RAW_TEXT:
        <free-form visible label text>

        INGREDIENTS:
        - ingredient 1
        - ingredient 2

        E_CODES:
        - E250

        UNCERTAIN:
        - unclear item

        WARNINGS:
        - warning if any
    """
    _HEADER_MAP = {
        "raw_text": "raw_text",
        "ingredients": "ingredients",
        "e_codes": "e_codes",
        "e codes": "e_codes",
        "uncertain": "uncertain",
        "warnings": "warnings",
    }

    raw_text_lines: list[str] = []
    sections: dict[str, list[str]] = {k: [] for k in _HEADER_MAP.values()}
    current: str | None = None

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        lower_no_colon = stripped.lower().rstrip(":")
        if stripped.endswith(":") and lower_no_colon in _HEADER_MAP:
            current = _HEADER_MAP[lower_no_colon]
            continue
        if current == "raw_text":
            # RAW_TEXT is free-form; collect all non-empty lines.
            item = stripped.lstrip("- ").strip()
            if item:
                raw_text_lines.append(item)
        elif current is not None:
            # All other sections are bullet lists.
            item = stripped.lstrip("- ").strip()
            if item and item.lower() not in _EMPTY_MARKERS:
                sections[current].append(item)

    raw_text = " ".join(raw_text_lines).strip()

    # Build ingredient items with confidence and E-code extraction.
    raw_ingredients: list[str] = []
    discarded_fragments: list[str] = []
    for orig in sections["ingredients"]:
        # Use deterministic parser to split into atomic items
        try:
            items = parse_ingredient_text_to_items(orig)
        except Exception:
            # fallback to older expand logic if parser fails for a line
            items = []
            for fragment in expand_compound_ingredient(orig):
                if should_discard_fragment(fragment):
                    discarded_fragments.append(fragment)
                    continue
                items.append(fragment)
        if not items:
            # record discarded or unparseable originals for telemetry
            cleaned = clean_ingredient_fragment(orig)
            if cleaned:
                discarded_fragments.append(cleaned)
            continue
        for fragment in items:
            if should_discard_fragment(fragment):
                discarded_fragments.append(fragment)
                continue
            raw_ingredients.append(fragment)

    cleaned_ingredients = dedupe_ingredients(raw_ingredients)

    ingredients: list[dict[str, Any]] = []
    for name in cleaned_ingredients:
        match = _ECODE_RE.search(name)
        e_code: str | None = match.group(1).upper() if match else None
        has_uncertain = any(m in name.lower() for m in _UNCERTAIN_MARKERS)
        confidence = 0.95 if e_code else (0.6 if has_uncertain else 0.92)
        ingredients.append(
            {"name": name, "original_text": name, "e_code": e_code, "confidence": confidence}
        )

    # Merge E-codes: from the E_CODES section + any embedded in ingredient names.
    e_codes_set: list[str] = []
    for raw_ec in sections["e_codes"]:
        ec = raw_ec.strip().upper()
        if ec and ec not in e_codes_set:
            e_codes_set.append(ec)
    for item in ingredients:
        if item["e_code"] and item["e_code"] not in e_codes_set:
            e_codes_set.append(item["e_code"])

    uncertain_items = [u for u in sections["uncertain"] if u.lower() not in _EMPTY_MARKERS]
    warnings = [w for w in sections["warnings"] if w.lower() not in _EMPTY_MARKERS]
    cleaned_text = ", ".join(item["name"] for item in ingredients)

    return {
        "raw_text": raw_text,
        "cleaned_text": cleaned_text,
        "ingredients": ingredients,
        "e_codes": e_codes_set,
        "uncertain_items": uncertain_items,
        "warnings": warnings,
        "discarded_fragments": dedupe_ingredients(discarded_fragments),
    }


def _compute_quality_score_from_content(
    ingredient_count: int,
    raw_text_len: int,
    uncertain_count: int,
    warnings: list[str],
) -> float:
    """Compute quality score purely from extracted content — no Claude score needed."""
    if ingredient_count >= 10 and raw_text_len > 200:
        score = 0.85
    elif ingredient_count >= 5 and raw_text_len > 100:
        score = 0.75
    elif ingredient_count >= 1:
        score = 0.60
    else:
        score = 0.20

    _BAD_KEYWORDS = (
        "blurry", "no ingredient", "no text", "unclear",
        "bulanık", "okunamadı", "no_ingredient",
    )
    if any(any(kw in w.lower() for kw in _BAD_KEYWORDS) for w in warnings):
        score *= 0.85

    total = ingredient_count + uncertain_count
    if total > 0 and uncertain_count / total > 0.4:
        score *= 0.85

    return float(min(max(score, 0.0), 1.0))


def _build_response_from_plain(parsed: dict[str, Any]) -> IngredientResponse:
    """Build an IngredientResponse from a plain-text-parsed dict."""
    ingredients = [
        IngredientItem(
            name=item["name"],
            original_text=item["original_text"],
            e_code=item.get("e_code"),
            confidence=float(item["confidence"]),
        )
        for item in parsed.get("ingredients", [])
    ]
    uncertain_items: list[str] = parsed.get("uncertain_items", [])
    warnings: list[str] = parsed.get("warnings", [])
    raw_text = str(parsed.get("raw_text", "")).strip()
    quality_score = _compute_quality_score_from_content(
        ingredient_count=len(ingredients),
        raw_text_len=len(raw_text),
        uncertain_count=len(uncertain_items),
        warnings=warnings,
    )
    return IngredientResponse(
        raw_text=raw_text,
        cleaned_text=str(parsed.get("cleaned_text", "")).strip(),
        ingredients=ingredients,
        e_codes=parsed.get("e_codes", []),
        uncertain_items=uncertain_items,
        warnings=warnings,
        quality_score=quality_score,
        discarded_fragments=parsed.get("discarded_fragments", []),
    )


def _parse_claude_json(text: str) -> tuple[dict[str, Any], bool]:
    """
    Parse JSON from Claude's response with progressive repair attempts.

    LLM JSON can occasionally be malformed — this function applies lightweight
    repairs before giving up. The backend must always fail safely; malformed
    JSON must never crash the OCR flow.

    Returns (parsed_dict, was_repaired). Raises ValueError if all attempts fail.
    """
    cleaned = _strip_markdown_fences(text.strip())

    # Attempt 1: direct parse (the happy path).
    try:
        return json.loads(cleaned), False
    except json.JSONDecodeError:
        pass

    # Attempt 2: apply lightweight repairs then retry.
    repaired = _repair_json(cleaned)
    try:
        return json.loads(repaired), True
    except json.JSONDecodeError as exc:
        raise ValueError(f"Claude returned invalid JSON after repair attempt: {exc}") from exc


def _strip_markdown_fences(text: str) -> str:
    """Remove ```json or ``` fences that Claude occasionally wraps output in."""
    if not text.startswith("```"):
        return text
    lines = text.split("\n")
    # Drop the opening fence line (```json or ```).
    inner = lines[1:] if len(lines) > 1 else lines
    # Drop the closing ``` if present.
    if inner and inner[-1].strip() == "```":
        inner = inner[:-1]
    return "\n".join(inner).strip()


def _repair_json(text: str) -> str:
    """
    Apply lightweight repairs to malformed JSON from LLMs.

    Handles the most common LLM JSON failure modes:
    - Smart/curly quotes instead of straight ASCII quotes
    - Trailing commas before } or ]
    - Truncated JSON (missing closing braces or brackets)
    """
    # Normalize smart/curly quotes to straight ASCII quotes.
    text = text.replace("“", '"').replace("”", '"')  # " " → "
    text = text.replace("‘", "'").replace("’", "'")  # ' ' → '

    # Remove trailing commas before a closing brace or bracket.
    text = re.sub(r",\s*([}\]])", r"\1", text)

    # Close obviously truncated JSON by counting unmatched openers.
    open_braces = text.count("{") - text.count("}")
    open_brackets = text.count("[") - text.count("]")
    if open_braces > 0 or open_brackets > 0:
        text = text.rstrip()
        # Close inner arrays before outer objects.
        text += "]" * max(0, open_brackets)
        text += "}" * max(0, open_braces)

    return text


def _build_fallback_response(raw_claude_response: str, reason: str) -> IngredientResponse:
    """
    Return a safe empty response when Claude's JSON cannot be parsed at all.

    LLM JSON can occasionally be malformed; the backend must always fail safely.
    Malformed JSON must never crash the OCR flow — the Flutter client will show
    a warning and the user can retry or fall back to local ML Kit.

    IMPORTANT: raw_claude_response is Claude's raw output (JSON, fences, etc.).
    It must NOT be forwarded as raw_text — that would expose JSON structure to
    the user. Leave raw_text empty; the warnings array explains what happened.
    """
    logger.warning(
        "Returning fallback response — reason: %s | raw_response_length=%d",
        reason,
        len(raw_claude_response),
    )
    return IngredientResponse(
        raw_text="",
        cleaned_text="",
        ingredients=[],
        e_codes=[],
        uncertain_items=[],
        warnings=["Claude returned invalid JSON — ingredient extraction failed", reason],
        quality_score=0.0,
        discarded_fragments=[],
    )


def _compute_quality_score(data: dict[str, Any], claude_score: float) -> float:
    """
    Adjust quality_score when Claude under-reports confidence for readable content.

    Claude occasionally returns quality_score=0.0 even after successfully
    extracting many ingredients (e.g. it scores the image quality, not the
    extraction success). We compute a content-based floor so the Flutter UI
    does not display a false "0% güvenilirlik" for usable results.
    """
    raw_text: str = str(data.get("raw_text", ""))
    ingredient_list = data.get("ingredients", [])
    uncertain_items = data.get("uncertain_items", [])
    warnings = [str(w).lower() for w in data.get("warnings", [])]

    ingredient_count = sum(
        1
        for item in ingredient_list
        if isinstance(item, dict) and str(item.get("name", "")).strip()
    )
    uncertain_count = len(uncertain_items)

    # Content-based floor: longer raw text + more ingredients → higher floor.
    content_floor = 0.0
    if ingredient_count >= 10 and len(raw_text) > 200:
        content_floor = 0.80
    elif ingredient_count >= 5 and len(raw_text) > 100:
        content_floor = 0.70
    elif ingredient_count >= 2 and len(raw_text) > 50:
        content_floor = 0.55

    score = max(claude_score, content_floor)

    # Reduce for explicit quality-degrading warnings.
    _BAD_KEYWORDS = (
        "blurry", "no ingredient", "no text", "unclear",
        "bulanık", "okunamadı", "no_ingredient",
    )
    if any(any(kw in w for kw in _BAD_KEYWORDS) for w in warnings):
        score *= 0.75

    # Reduce when uncertain items dominate.
    total = ingredient_count + uncertain_count
    if total > 0 and uncertain_count / total > 0.4:
        score *= 0.85

    return float(min(max(score, 0.0), 1.0))


def _build_response(data: dict[str, Any]) -> IngredientResponse:
    ingredients: list[IngredientItem] = []
    for item in data.get("ingredients", []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name", "")).strip()
        if not name:
            continue
        e_code_raw = item.get("e_code")
        e_code = str(e_code_raw).strip() if e_code_raw else None
        ingredients.append(
            IngredientItem(
                name=name,
                original_text=str(
                    item.get("original_text", item.get("name", name))
                ).strip(),
                e_code=e_code,
                confidence=float(
                    min(max(item.get("confidence", 0.9), 0.0), 1.0)
                ),
            )
        )

    def _str_list(key: str) -> list[str]:
        return [
            str(x).strip()
            for x in data.get(key, [])
            if str(x).strip()
        ]

    # Use 0.5 as the default when Claude omits quality_score entirely.
    claude_score = float(min(max(data.get("quality_score", 0.5), 0.0), 1.0))
    quality_score = _compute_quality_score(data, claude_score)

    return IngredientResponse(
        raw_text=str(data.get("raw_text", "")).strip(),
        cleaned_text=str(data.get("cleaned_text", "")).strip(),
        ingredients=ingredients,
        e_codes=_str_list("e_codes"),
        uncertain_items=_str_list("uncertain_items"),
        warnings=_str_list("warnings"),
        quality_score=quality_score,
        discarded_fragments=_str_list("discarded_fragments"),
    )


# ---------------------------------------------------------------------------
# Product-label combined extraction (ingredients + nutrition)
# ---------------------------------------------------------------------------

_PRODUCT_LABEL_SYSTEM_PROMPT = """\
You are a strict food label extraction engine for Turkish packaged food products.

Rules you MUST always follow:
- Extract ONLY values that are VISIBLY PRINTED on the label in the image.
- Do NOT invent, estimate, or calculate any value.
- Do NOT give any health advice or classification.
- Do NOT score or rank the product.
- Do NOT make any medical claims.
- Preserve Turkish characters exactly: ç, ğ, ı, ö, ş, ü.
- Preserve E-codes exactly as printed (e.g. E250, E330, E621).

For ingredients:
- Extract ingredient names only (no quantities, no percentages, no units).
- If an ingredient has category + detail, extract both (e.g. "bitkisel yağlar (ayçiçek, palm)" → bitkisel yağlar, ayçiçek yağı, palm yağı).
- List uncertain items under UNCERTAIN.
- If no ingredients section is visible, leave INGREDIENTS empty and add a WARNING.

For nutrition facts:
- Extract only per-100g or per-100ml values (prefer 100g if both are shown).
- Use decimal dot notation (e.g. 9.3, not 9,3).
- If a field is not printed on the label, write: not_visible
- serving_size: copy the serving size text exactly as printed (e.g. "30 g", "1 bardak (250 ml)").
- If no nutrition table is visible, write not_visible for all fields.

Output format rules (strictly enforced):
- Return ONLY the plain-text format shown in the user message.
- Do NOT use JSON. Do NOT use markdown. Do NOT use code fences.
- Use exactly the section headers shown.\
"""


def _build_product_label_user_prompt(language_hint: str) -> str:
    return f"""\
Read this food product label image. Language hint: {language_hint}

Return your answer in this EXACT plain-text format — nothing else, no JSON, no markdown:

RAW_TEXT:
<all visible text on the label, exactly as printed>

INGREDIENTS:
- ingredient 1
- ingredient 2

E_CODES:
- E250

UNCERTAIN:
- any item you could not read clearly

WARNINGS:
- any extraction issue (e.g. image blurry, no ingredients section visible)

NUTRITION_FACTS:
energy_kcal: <value or not_visible>
fat: <value or not_visible>
saturated_fat: <value or not_visible>
carbohydrates: <value or not_visible>
sugars: <value or not_visible>
fiber: <value or not_visible>
proteins: <value or not_visible>
salt: <value or not_visible>
sodium: <value or not_visible>
serving_size: <text or not_visible>

Rules:
- Do NOT use JSON or code fences.
- Extract ingredient names only (no quantities, percentages, or units).
- Preserve Turkish characters: ç, ğ, ı, ö, ş, ü.
- Preserve E-codes exactly as printed.
- For NUTRITION_FACTS: use numeric values with decimal dot (e.g. 9.3). Write not_visible if the field is absent.
- If a section has no items, write exactly: "- none"\
"""


_NUTRITION_FIELD_ALIASES: dict[str, str] = {
    "energy_kcal": "energy_kcal",
    "enerji_kcal": "energy_kcal",
    "energy": "energy_kcal",
    "enerji": "energy_kcal",
    "fat": "fat",
    "yag": "fat",
    "toplam_yag": "fat",
    "saturated_fat": "saturated_fat",
    "doymus_yag": "saturated_fat",
    "saturated": "saturated_fat",
    "carbohydrates": "carbohydrates",
    "karbonhidrat": "carbohydrates",
    "carbs": "carbohydrates",
    "sugars": "sugars",
    "seker": "sugars",
    "sugar": "sugars",
    "fiber": "fiber",
    "lif": "fiber",
    "dietary_fiber": "fiber",
    "proteins": "proteins",
    "protein": "proteins",
    "salt": "salt",
    "tuz": "salt",
    "sodium": "sodium",
    "sodyum": "sodium",
    "serving_size": "serving_size",
    "porsiyon": "serving_size",
}

_NUTRITION_NUMERIC_FIELDS = frozenset({
    "energy_kcal", "fat", "saturated_fat", "carbohydrates",
    "sugars", "fiber", "proteins", "salt", "sodium",
})


def _parse_nutrition_section(lines: list[str]) -> dict[str, Any]:
    """Parse NUTRITION_FACTS key:value lines into a clean dict.

    Only includes fields with valid numeric values (skips not_visible/empty).
    serving_size is kept as a string.
    """
    result: dict[str, Any] = {}
    for line in lines:
        if ":" not in line:
            continue
        raw_key, _, raw_val = line.partition(":")
        key = raw_key.strip().lower().replace(" ", "_").replace("-", "_")
        val = raw_val.strip()

        canonical = _NUTRITION_FIELD_ALIASES.get(key)
        if canonical is None:
            continue
        if not val or val.lower() in {"not_visible", "none", "-", "yok", ""}:
            continue

        if canonical == "serving_size":
            result["serving_size"] = val
            continue

        if canonical in _NUTRITION_NUMERIC_FIELDS:
            # Normalise comma decimal separator.
            val_norm = val.replace(",", ".").split()[0]
            try:
                result[canonical] = float(val_norm)
            except ValueError:
                pass

    return result


async def _extract_product_label_with_claude(
    image_bytes: bytes,
    media_type: str,
    language_hint: str,
    api_key: str,
) -> ProductLabelResponse:
    image_size_kb = len(image_bytes) // 1024
    logger.debug(
        "Calling Claude Vision for product-label — model=%s image_size=%d KB",
        _CLAUDE_MODEL,
        image_size_kb,
    )

    b64_data = base64.standard_b64encode(image_bytes).decode()

    try:
        client = Anthropic(api_key=api_key)
        message = client.messages.create(
            model=_CLAUDE_MODEL,
            max_tokens=3072,
            system=_PRODUCT_LABEL_SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": b64_data,
                            },
                        },
                        {
                            "type": "text",
                            "text": _build_product_label_user_prompt(language_hint),
                        },
                    ],
                }
            ],
        )
    except (APIStatusError, APITimeoutError, APIConnectionError) as exc:
        logger.error("Claude API error in extract_product_label: %s", exc)
        raise HTTPException(
            status_code=502,
            detail={
                "error": "Claude API error",
                "details": str(exc),
                "type": type(exc).__name__,
            },
        ) from exc

    raw_content = message.content[0].text.strip() if message.content else ""
    logger.debug(
        "Claude product-label response — raw_content_length=%d chars",
        len(raw_content),
    )

    if not raw_content:
        fallback_ingredient_resp = _build_fallback_response("", "Claude returned empty response")
        return ProductLabelResponse(
            ingredients=fallback_ingredient_resp,
            nutrition=None,
            extraction_status="failed",
        )

    # Parse the plain-text sections.
    ingredient_response: IngredientResponse
    nutrition_dict: dict[str, Any] | None = None

    if _looks_like_plain_text_format(raw_content):
        try:
            # Split out the NUTRITION_FACTS section before passing to ingredient parser.
            ingredient_lines, nutrition_lines = _split_label_sections(raw_content)
            parsed_plain = _parse_plain_text_response(ingredient_lines)
            ingredient_response = _build_response_from_plain(parsed_plain)
            logger.debug(
                "product-label ingredients parsed — count=%d",
                len(ingredient_response.ingredients),
            )

            if nutrition_lines:
                nutrition_dict = _parse_nutrition_section(nutrition_lines)
                logger.debug(
                    "product-label nutrition parsed — fields=%d has_any=%s",
                    len(nutrition_dict),
                    bool(nutrition_dict),
                )
        except Exception as exc:
            logger.warning("product-label plain-text parsing error: %s", exc)
            ingredient_response = _build_fallback_response(raw_content, str(exc))
    else:
        ingredient_response = _build_fallback_response(raw_content, "Unrecognised response format")

    has_ingredients = len(ingredient_response.ingredients) > 0
    has_nutrition = bool(nutrition_dict)
    if has_ingredients or has_nutrition:
        status = "success"
    else:
        status = "failed"

    return ProductLabelResponse(
        ingredients=ingredient_response,
        nutrition=nutrition_dict if has_nutrition else None,
        extraction_status=status,
    )


def _split_label_sections(text: str) -> tuple[str, list[str]]:
    """Split raw Claude response into ingredient portion and NUTRITION_FACTS lines.

    Returns (ingredient_text_for_plain_parser, nutrition_key_value_lines).
    The ingredient text still contains RAW_TEXT/INGREDIENTS/E_CODES/UNCERTAIN/WARNINGS sections.
    NUTRITION_FACTS lines are returned separately for the nutrition parser.
    """
    ingredient_lines: list[str] = []
    nutrition_lines: list[str] = []
    in_nutrition = False

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.upper().rstrip(":") == "NUTRITION_FACTS":
            in_nutrition = True
            continue
        # Any subsequent known section header exits nutrition mode.
        if in_nutrition and stripped.endswith(":"):
            upper = stripped.upper().rstrip(":")
            if upper in {"RAW_TEXT", "INGREDIENTS", "E_CODES", "UNCERTAIN", "WARNINGS"}:
                in_nutrition = False
                ingredient_lines.append(line)
                continue
        if in_nutrition:
            if stripped:
                nutrition_lines.append(stripped)
        else:
            ingredient_lines.append(line)

    return "\n".join(ingredient_lines), nutrition_lines
