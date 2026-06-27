# Production OCR Backend

## Goal
Bu backend, paketli gıda etiketlerinden güvenilir içerik çıkarımı yapmak için üretim ortamı OCR hattını tanımlar.

## Why this exists
- ML Kit hızlı önizleme için kalır.
- Nihai içerik çıkarımı cihaz içi OCR'a bırakılmaz.
- Sunucu tarafı OCR daha güçlü metin çıkarımı ve yapılandırılmış içerik ayrıştırma sağlar.
- Skor hesaplama yine uygulamadaki deterministik analiz motorunda kalır.

## Recommended architecture
### Option A: Supabase Edge Function + external OCR APIs
- Hızlı başlangıç
- Supabase ile tek platform
- Ancak Google Cloud Vision + OpenAI entegrasyonları Python kadar rahat değildir

### Option B: FastAPI service
- **Recommended**
- Google Cloud Vision ve OpenAI entegrasyonları Python'da daha kolaydır
- İyi hata yönetimi, ayrı ölçekleme ve daha temiz yapı sağlar

## Backend contract
### Request
POST `/ocr/ingredients`

```json
{
  "image_url": "https://...",
  "language_hint": "tr",
  "mode": "ingredients_label"
}
```

### Response
```json
{
  "raw_text": "...",
  "cleaned_text": "...",
  "ingredients": [
    {
      "name": "sodyum nitrit",
      "original_text": "sodyum nitrit",
      "e_code": "E250",
      "confidence": 0.97
    }
  ],
  "e_codes": ["E250"],
  "uncertain_items": [],
  "warnings": [],
  "quality_score": 0.0
}
```

## Rules
- Sadece görünen içerikler çıkarılmalı
- Uydurma içerik üretülmemeli
- Emin olunmayan öğeler `uncertain_items` alanına yazılmalı
- Türkçe karakterler korunmalı
- E-kodları korunmalı
- Sağlık tavsiyesi verilmemeli
- JSON only dönülmeli

## Environment variables
- `OCR_BACKEND_URL`
- `OCR_BACKEND_API_KEY`

## Mobile behavior
- `OCR_BACKEND_URL` yoksa uygulama şu mesajı gösterir:
  - `Gelişmiş OCR servisi henüz yapılandırılmadı.`
- Kullanıcı yine de `Hızlı OCR` ile devam edebilir
- Manuel düzeltme her zaman açık kalır

## Final scoring rule
- Üretim OCR yalnızca yapılandırılmış içerik listesi sağlar
- Ürün skoru, uygulamadaki mevcut deterministik içerik eşleştirme ve analiz motoru tarafından belirlenir
- AI ürün puanı vermez
