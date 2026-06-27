-- Seed data for Food Analyzer App
-- Turkish market examples with realistic products and ingredients

-- ============================================================================
-- CATEGORIES
-- ============================================================================
INSERT INTO categories (id, name, parent_id, default_processing_level, default_warning)
VALUES
  ('550e8400-e29b-41d4-a716-446655440001', 'İşlenmiş Et', NULL, NULL, 'Yüksek işlenmiş ürün'),
  ('550e8400-e29b-41d4-a716-446655440002', 'Süt Ürünleri', NULL, NULL, NULL),
  ('550e8400-e29b-41d4-a716-446655440003', 'Bisküvi / Atıştırmalık', NULL, NULL, 'Yüksek şeker içeriği'),
  ('550e8400-e29b-41d4-a716-446655440004', 'İçecek', NULL, NULL, 'Şeker içerebilir'),
  ('550e8400-e29b-41d4-a716-446655440005', 'Hazır Gıda', NULL, NULL, 'Yüksek tuz içeriği');

-- ============================================================================
-- INGREDIENTS
-- ============================================================================
INSERT INTO ingredients (id, name, normalized_name, alternative_names, aliases, common_names, english_names, e_code, category, additive_group, risk_level, short_description, long_description, child_warning, source_references, source_url)
VALUES
  -- Additives and preservatives
  ('650e8400-e29b-41d4-a716-446655440001', 'Sodyum Nitrit', 'sodyum nitrit', ARRAY['nitrit'], ARRAY['e250','nitrit'], ARRAY['nitrit'], ARRAY['sodium nitrite'], 'E250', 'Korunucu', 'Nitritler', 'high', 'İşlenmiş ette kullanılan koruyucu', 'İşlenmiş et ürünlerinde renk ve bozulmayı önlemek için kullanılır. Düzenli tüketim önerilmez.', 'Çocuklara sık verilmemelidir', ARRAY['https://www.openfoodfacts.org', 'https://tr.wikipedia.org/wiki/Sodyum_nitrit'], NULL),
  ('650e8400-e29b-41d4-a716-446655440002', 'Sodyum Polifosfat', 'sodyum polifosfat', ARRAY['polifosfat','E452'], ARRAY['e452'], ARRAY['polifosfat'], ARRAY['sodium polyphosphate'], 'E452', 'Stabilizatör', 'Polifosfatlar', 'medium', 'Ürünün dokusunu ve nemini korumaya yardımcı olur', 'Aşırı miktarda tüketim önerilmez', ARRAY['https://www.openfoodfacts.org', 'https://en.wikipedia.org/wiki/Polyphosphate'], NULL),
  ('650e8400-e29b-41d4-a716-446655440003', 'Askorbik Asit', 'askorbik asit', ARRAY['vitamin c'], ARRAY[], ARRAY['askorbik asit'], ARRAY['ascorbic acid', 'vitamin C'], 'E300', 'Antioksidan', 'Asitler', 'low', 'İçerik koruması için kullanılan doğal bileşik', 'Vitamin C takviyesi olarak bilinir; normal kullanımlarda güvenlidir.', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440004', 'Sitrik Asit', 'sitrik asit', ARRAY['E330'], ARRAY[], ARRAY['sitrik asit'], ARRAY['citric acid'], 'E330', 'Asitlik düzenleyici', 'Asitler', 'low', 'Tadı ve asitlik dengesini ayarlamak için kullanılır', 'Doğal kaynaklıdır; normal kullanımlarda güvenlidir.', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440005', 'Glikoz Şurubu', 'glikoz şurubu', ARRAY['glucose syrup','glukoz'], ARRAY['glukoz şurubu'], ARRAY['glikoz şurubu'], ARRAY['glucose syrup'], NULL, 'Tatlandırıcı', NULL, 'high', 'İşlenmiş şeker şurubu', 'Şeker içeriği yüksektir; sık tüketim önerilmez.', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440006', 'Fruktoz Şurubu', 'fruktoz şurubu', ARRAY['fructose syrup'], ARRAY['fruktoz şurubu'], ARRAY['fruktoz şurubu'], ARRAY['fructose syrup'], NULL, 'Tatlandırıcı', NULL, 'high', 'Mısır kaynaklı işlenmiş şurup', 'Hızlı şeker yükselmesine katkıda bulunabilir; dikkatli tüketim önerilir.', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440007', 'Palm Yağı', 'palm yağı', ARRAY['palm oil'], ARRAY['palm yağı'], ARRAY['palm yağı'], ARRAY['palm oil'], NULL, 'Yağ', 'Bitkisel yağ', 'medium', 'Tropikal bitkiden elde edilen yaygın kullanılan yağ', 'Doymuş yağ içeriği nedeniyle dengeli tüketim önerilir.', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440008', 'Lesitin', 'lesitin', ARRAY['lecithin'], ARRAY['lesitin'], ARRAY['lesitin'], ARRAY['lecithin'], NULL, 'Emülgatör', 'Emülgatörler', 'low', 'Gıda emülsiyonlarını stabilize etmek için kullanılır', NULL, ARRAY['https://en.wikipedia.org/wiki/Lecithin'], NULL),
  ('650e8400-e29b-41d4-a716-446655440009', 'Potasyum Sorbat', 'potasyum sorbat', ARRAY['sorbat','E202'], ARRAY['e202'], ARRAY['potasyum sorbat'], ARRAY['potassium sorbate'], 'E202', 'Korunucu', 'Sorbatiçikler', 'low', 'Maya ve küf oluşumunu engellemek için kullanılır', 'Çocuklarda olağan kullanımlarda genellikle güvenlidir.', ARRAY['https://www.openfoodfacts.org', 'https://en.wikipedia.org/wiki/Potassium_sorbate'], NULL),
  ('650e8400-e29b-41d4-a716-446655440010', 'Sodyum Benzoat', 'sodyum benzoat', ARRAY['benzoat','E211'], ARRAY['e211'], ARRAY['sodyum benzoat'], ARRAY['sodium benzoate'], 'E211', 'Korunucu', 'Benzoatlar', 'medium', 'Koruyucu olarak yaygın kullanılır; önerilen sınırlar içinde kullanım önerilir', 'Çocuklara sık verilmemelidir', ARRAY['https://www.openfoodfacts.org', 'https://en.wikipedia.org/wiki/Sodium_benzoate'], NULL),
  ('650e8400-e29b-41d4-a716-446655440011', 'Tuz', 'tuz', ARRAY['sodyum klorür','salt'], ARRAY['sofra tuzu'], ARRAY['tuz'], ARRAY['salt'], NULL, 'Baharat', NULL, 'low', 'Yemeklere tat vermek için kullanılan temel mineral', 'Aşırı tuz tüketiminden kaçının', NULL, NULL),
  ('650e8400-e29b-41d4-a716-446655440012', 'Süt', 'süt', ARRAY['milk','inek sütü'], ARRAY['süt'], ARRAY['süt'], ARRAY['milk'], NULL, 'Temel bileşen', NULL, 'low', 'Doğal hayvansal protein kaynağı', 'Süt alerjisi olan çocuklara verilmemelidir', NULL, NULL;

-- ============================================================================
-- PRODUCTS
-- ============================================================================
INSERT INTO products (id, barcode, name, normalized_name, brand, category_id, image_url, ingredients_text, nutrition_text, source, verification_status)
VALUES
  -- 1. Processed meat example
  ('750e8400-e29b-41d4-a716-446655440001', '8690000000001', 'Sucuk', 'sucuk', 'Yerel Gıda', '550e8400-e29b-41d4-a716-446655440001', NULL, 'Sığır eti, sodyum nitrit, sodyum polifosfat, tuz, baharat', 'Protein 20g, Yağ 25g, Karbonhidrat 2g', 'seed', 'verified'),
  
  -- 2. Simple dairy example
  ('750e8400-e29b-41d4-a716-446655440002', '8690000000002', 'Süzme Yoğurt', 'suzme yogurt', 'Yerel Kasap', '550e8400-e29b-41d4-a716-446655440002', NULL, 'Inek sütü, doğal mayalar', 'Protein 8g, Yağ 3g, Karbonhidrat 6g', 'seed', 'verified'),
  
  -- 3. Biscuit/snack example
  ('750e8400-e29b-41d4-a716-446655440003', '8690000000003', 'Çikolatalı Bisküvi', 'cikotali biskuvi', 'Tatlı Gıda', '550e8400-e29b-41d4-a716-446655440003', NULL, 'Un, şeker, glikoz şurubu, palm yağı, kakaopuls, lesitin', 'Protein 3g, Yağ 8g, Karbonhidrat 18g', 'seed', 'verified'),
  
  -- 4. Beverage example
  ('750e8400-e29b-41d4-a716-446655440004', '8690000000004', 'Meyve Suyu İçeceği', 'meyve suyu iceğegi', 'Meyveci', '550e8400-e29b-41d4-a716-446655440004', NULL, 'Su, meyve konsantresi, glikoz şurubu, sitrik asit, potasyum sorbat', 'Protein 0g, Yağ 0g, Karbonhidrat 12g', 'seed', 'verified'),
  
  -- 5. Ready food example
  ('750e8400-e29b-41d4-a716-446655440005', '8690000000005', 'Hazır Makarna Soslu', 'hazir makarna soslu', 'Hızlı Gıda', '550e8400-e29b-41d4-a716-446655440005', NULL, 'Buğday unı, tuz, lesitin, sodoum benzoat, baharat, tomatoas tozu', 'Protein 4g, Yağ 1g, Karbonhidrat 22g', 'seed', 'verified');

-- ============================================================================
-- PRODUCT_REVIEWS
-- ============================================================================
INSERT INTO product_reviews (id, product_id, score_label, summary, warning_text, positive_points, negative_points, consumption_advice, suitable_for_children)
VALUES
  -- Review for Sucuk
  ('850e8400-e29b-41d4-a716-446655440001', '750e8400-e29b-41d4-a716-446655440001', 'dikkatli_tuket', 
   'İşlenmiş et ürünü', 
   'Sodyum nitrit içeriğinden dolayı sık tüketimi önerilmez',
   ARRAY['Lezzetli', 'Pratik'],
   ARRAY['Yüksek tuz', 'Yüksek işlenmiş katkı maddesi', 'Sık tüketimde sağlık riski'],
   'Ayda birkaç kez tüketim uygun. Düzenli tüketimden kaçının.',
   false),
  
  -- Review for Yoğurt
  ('850e8400-e29b-41d4-a716-446655440002', '750e8400-e29b-41d4-a716-446655440002', 'iyi_secim',
   'Doğal ve besleyici',
   NULL,
   ARRAY['Doğal bileşenler', 'Yüksek protein', 'Besleyici'],
   ARRAY[],
   'Düzenli tüketim sağlıklı bir seçimdir.',
   true),
  
  -- Review for Biscuit
  ('850e8400-e29b-41d4-a716-446655440003', '750e8400-e29b-41d4-a716-446655440003', 'dikkatli_tuket',
   'Şekerli atıştırmalık',
   'Yüksek şeker ve palm yağı içeriği',
   ARRAY['Lezzetli', 'Uygun fiyat'],
   ARRAY['Yüksek şeker', 'Doymuş yağ', 'Katkı maddesi'],
   'Ara sıra tüketim. Çocuklara sınırlı verilmelidir.',
   false),
  
  -- Review for Beverage
  ('850e8400-e29b-41d4-a716-446655440004', '750e8400-e29b-41d4-a716-446655440004', 'orta',
   'Şekerli içecek',
   'Yapay şeker şurubundan dolayı aşırı tüketim uygun değil',
   ARRAY['Lezzetli tat', 'Serinletici'],
   ARRAY['Glikoz şurubu', 'Yüksek şeker'],
   'Haftada birkaç kez tüketim yapılabilir. Su içmeyi tercih edin.',
   true),
  
  -- Review for Ready Pasta
  ('850e8400-e29b-41d4-a716-446655440005', '750e8400-e29b-41d4-a716-446655440005', 'orta',
   'Pratik hazır gıda',
   'Yüksek tuz ve katkı maddeleri',
   ARRAY['Hızlı ve pratik', 'Ekonomik'],
   ARRAY['Yüksek tuz', 'Katkı maddeleri', 'Beslenme değeri sınırlı'],
   'Ek sebze ile servis yapın. Harfi harfine hazırlanmış şekilde sık tüketmekten kaçının.',
   true);

-- ============================================================================
-- PRODUCT_INGREDIENTS (Links)
-- ============================================================================
INSERT INTO product_ingredients (product_id, ingredient_id, raw_text, detected_from, confidence_score)
VALUES
  -- Sucuk
  ('750e8400-e29b-41d4-a716-446655440001', '650e8400-e29b-41d4-a716-446655440001', 'Sodyum Nitrit', 'label', 0.95),
  ('750e8400-e29b-41d4-a716-446655440001', '650e8400-e29b-41d4-a716-446655440002', 'Sodyum Polifosfat', 'label', 0.95),
  ('750e8400-e29b-41d4-a716-446655440001', '650e8400-e29b-41d4-a716-446655440011', 'Tuz', 'label', 0.95),
  
  -- Yoğurt
  ('750e8400-e29b-41d4-a716-446655440002', '650e8400-e29b-41d4-a716-446655440012', 'Inek sütü', 'label', 0.99),
  
  -- Bisküvi
  ('750e8400-e29b-41d4-a716-446655440003', '650e8400-e29b-41d4-a716-446655440005', 'Glikoz Şurubu', 'label', 0.90),
  ('750e8400-e29b-41d4-a716-446655440003', '650e8400-e29b-41d4-a716-446655440007', 'Palm Yağı', 'label', 0.88),
  ('750e8400-e29b-41d4-a716-446655440003', '650e8400-e29b-41d4-a716-446655440008', 'Lesitin', 'label', 0.85),
  
  -- Meyve Suyu
  ('750e8400-e29b-41d4-a716-446655440004', '650e8400-e29b-41d4-a716-446655440005', 'Glikoz Şurubu', 'label', 0.92),
  ('750e8400-e29b-41d4-a716-446655440004', '650e8400-e29b-41d4-a716-446655440004', 'Sitrik Asit', 'label', 0.95),
  ('750e8400-e29b-41d4-a716-446655440004', '650e8400-e29b-41d4-a716-446655440009', 'Potasyum Sorbat', 'label', 0.90),
  
  -- Hazır Makarna
  ('750e8400-e29b-41d4-a716-446655440005', '650e8400-e29b-41d4-a716-446655440011', 'Tuz', 'label', 0.95),
  ('750e8400-e29b-41d4-a716-446655440005', '650e8400-e29b-41d4-a716-446655440008', 'Lesitin', 'label', 0.80),
  ('750e8400-e29b-41d4-a716-446655440005', '650e8400-e29b-41d4-a716-446655440010', 'Sodyum Benzoat', 'label', 0.85);
