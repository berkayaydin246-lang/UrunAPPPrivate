# OCR Strategy

## Goal
Türkçe ambalaj ve içerik metinlerinde güvenilir OCR sağlamak.

## Default engine
- Yerel varsayılan: ML Kit (`TextRecognitionScript.latin`)
- Neden: hızlı, çevrimdışı, düşük gecikme, basit kullanıcı akışı
- Kullanım alanı: normal tarama, ilk deneme, düşük ağ koşulları

## Fallback yaklaşımı
- Sunucu OCR yalnızca zor görüntüler için kullanılır
- Kullanıcı deneyimi bozulmadan daha güçlü modeller denenebilir
- Sağlık / analiz kararları OCR motorundan değil, kural tabanlı içerik eşleştirmeden gelir

## Engine seçenekleri
- ML Kit: cihaz içi varsayılan
- Google Vision: karşılaştırma ve yüksek kalite doğrulama adayı
- PaddleOCR: sunucu tarafı güçlü fallback adayı
- Tesseract TR: Türkçe odaklı alternatif ve benchmark karşılaştırması

## Result metadata
Her OCR sonucu mümkünse şu bilgileri taşır:
- engineType
- rawText
- cleanedText
- confidenceScore
- processingTimeMs
- warnings
- languageHint

## Quality evaluation
Deterministik kalite denetimi kullanılır:
- düşük güven
- kısa metin
- az satır
- düşük ayırıcı kalitesi
- anlamsız karakter yoğunluğu
- Türkçe karakter zayıflığı
- E-kodu bozulması

## Benchmark screen
Gizli iç ekran:
- path: /internal/ocr-benchmark
- amaç: yerel ve uzak OCR sonuçlarını yan yana görmek
- kullanım: geliştirme, motor karşılaştırma, kalite kontrol

## Endpoint expectation
Uzak OCR servisi şu girdiyi bekler:
- image_url
- engine
- language_hint

Beklenen yanıt alanları:
- text veya cleaned_text
- raw_text
- confidence_score veya confidence
- processing_time_ms
- warnings

## Implementation rule
- Yerel OCR her zaman ilk seçenek kalır
- Sunucu OCR, yalnızca daha iyi sonuç beklenen durumlarda devreye girer
- Benchmark sonuçları analiz kararlarını değiştirmez; sadece OCR motoru seçimini iyileştirir
