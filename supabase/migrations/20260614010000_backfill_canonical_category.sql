-- Backfill canonical_category and canonical_subcategory from category_tags.
--
-- Run after 20260614000000_add_canonical_category.sql which adds the columns.
-- Safe to re-run: only updates rows where canonical_category IS NULL.
-- Migros scraper tags (short, specific) and old scraper tags (compound) are
-- both handled here so existing products get the right canonical values.

-- ── Süt ve Süt Ürünleri ──────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri', canonical_subcategory = 'Süt'
WHERE canonical_category IS NULL AND 'sut' = ANY(category_tags);

UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri', canonical_subcategory = 'Yoğurt'
WHERE canonical_category IS NULL AND 'yogurt' = ANY(category_tags);

UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri', canonical_subcategory = 'Peynir'
WHERE canonical_category IS NULL AND 'peynir' = ANY(category_tags);

UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri', canonical_subcategory = 'Sütlü Tatlı / Krema'
WHERE canonical_category IS NULL AND 'sutlu_tatli_krema' = ANY(category_tags);

-- Old scraper tag: sut_urunleri covers all dairy — leave sub-category null for
-- rows that need name-based sub classification (done client-side).
UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri'
WHERE canonical_category IS NULL AND 'sut_urunleri' = ANY(category_tags);

-- Old scraper tag: peynir_yogurt covers both peynir and yoğurt — sub determined client-side.
UPDATE products SET canonical_category = 'Süt ve Süt Ürünleri'
WHERE canonical_category IS NULL AND 'peynir_yogurt' = ANY(category_tags);

-- ── Et / Tavuk / Balık ───────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Et / Tavuk / Balık', canonical_subcategory = 'Şarküteri'
WHERE canonical_category IS NULL
  AND (
    'sucuk'   = ANY(category_tags) OR
    'sosis'   = ANY(category_tags) OR
    'salam'   = ANY(category_tags) OR
    'jambon'  = ANY(category_tags) OR
    'pastirma'= ANY(category_tags) OR
    'fume_et' = ANY(category_tags) OR
    'kavurma' = ANY(category_tags)
  );

UPDATE products SET canonical_category = 'Et / Tavuk / Balık', canonical_subcategory = 'Tavuk'
WHERE canonical_category IS NULL AND 'beyaz_et' = ANY(category_tags);

UPDATE products SET canonical_category = 'Et / Tavuk / Balık', canonical_subcategory = 'Kırmızı Et'
WHERE canonical_category IS NULL AND 'kirmizi_et' = ANY(category_tags);

UPDATE products SET canonical_category = 'Et / Tavuk / Balık', canonical_subcategory = 'Balık / Deniz Ürünleri'
WHERE canonical_category IS NULL AND 'balik_deniz_urunleri' = ANY(category_tags);

UPDATE products SET canonical_category = 'Et / Tavuk / Balık', canonical_subcategory = 'Balık / Deniz Ürünleri'
WHERE canonical_category IS NULL AND 'ton_konserve' = ANY(category_tags);

UPDATE products SET canonical_category = 'Et / Tavuk / Balık'
WHERE canonical_category IS NULL
  AND ('et_sarkuteri' = ANY(category_tags) OR 'et-sarkulteri' = ANY(category_tags));

-- ── Atıştırmalık ─────────────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Cips'
WHERE canonical_category IS NULL AND 'cips' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Bisküvi'
WHERE canonical_category IS NULL AND 'biskuvi' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Kuruyemiş'
WHERE canonical_category IS NULL AND 'kuruyemis' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Cips'
WHERE canonical_category IS NULL AND 'cips_kraker' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Bisküvi'
WHERE canonical_category IS NULL AND 'biskuvi_kek' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Çikolata / Gofret'
WHERE canonical_category IS NULL AND 'cikolata_gofret' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık', canonical_subcategory = 'Kuruyemiş'
WHERE canonical_category IS NULL AND 'saglikli_protein' = ANY(category_tags);

UPDATE products SET canonical_category = 'Atıştırmalık'
WHERE canonical_category IS NULL AND 'atistirmalik' = ANY(category_tags);

-- ── İçecekler ────────────────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'İçecekler', canonical_subcategory = 'Gazlı İçecek'
WHERE canonical_category IS NULL AND 'gazli_icecek' = ANY(category_tags);

UPDATE products SET canonical_category = 'İçecekler', canonical_subcategory = 'Gazsız İçecek'
WHERE canonical_category IS NULL AND 'gazsiz_icecek' = ANY(category_tags);

UPDATE products SET canonical_category = 'İçecekler', canonical_subcategory = 'Gazlı İçecek'
WHERE canonical_category IS NULL AND 'enerji_icecekleri' = ANY(category_tags);

UPDATE products SET canonical_category = 'İçecekler'
WHERE canonical_category IS NULL AND 'icecekler' = ANY(category_tags);

-- ── Sos / Konserve / Hazır Gıda ──────────────────────────────────────────────

UPDATE products SET canonical_category = 'Sos / Konserve / Hazır Gıda', canonical_subcategory = 'Soslar'
WHERE canonical_category IS NULL AND 'sos' = ANY(category_tags);

UPDATE products SET canonical_category = 'Sos / Konserve / Hazır Gıda', canonical_subcategory = 'Konserve'
WHERE canonical_category IS NULL AND 'konserve' = ANY(category_tags);

UPDATE products SET canonical_category = 'Sos / Konserve / Hazır Gıda', canonical_subcategory = 'Soslar'
WHERE canonical_category IS NULL AND 'soslar' = ANY(category_tags);

UPDATE products SET canonical_category = 'Sos / Konserve / Hazır Gıda', canonical_subcategory = 'Hazır Yemek'
WHERE canonical_category IS NULL AND 'hazir_yemek' = ANY(category_tags);

-- ── Temel Gıda ───────────────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Temel Gıda'
WHERE canonical_category IS NULL AND 'makarna_bakliyat' = ANY(category_tags);

-- ── Kahvaltılıklar ───────────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Kahvaltılıklar', canonical_subcategory = 'Krem Çikolata / Ezme'
WHERE canonical_category IS NULL AND 'findik_ezmesi' = ANY(category_tags);

UPDATE products SET canonical_category = 'Kahvaltılıklar'
WHERE canonical_category IS NULL
  AND ('kahvaltilik' = ANY(category_tags) OR 'kahvaltiliklar' = ANY(category_tags));

-- ── Diğer ────────────────────────────────────────────────────────────────────

UPDATE products SET canonical_category = 'Diğer', canonical_subcategory = 'Bebek / Çocuk'
WHERE canonical_category IS NULL AND 'bebek_cocuk' = ANY(category_tags);

UPDATE products SET canonical_category = 'Diğer', canonical_subcategory = 'Dondurma / Tatlı'
WHERE canonical_category IS NULL AND 'dondurma_tatli' = ANY(category_tags);
