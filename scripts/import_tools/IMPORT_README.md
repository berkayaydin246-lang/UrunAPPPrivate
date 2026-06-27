# Food Analyzer Import System

Safe, idempotent data import system for Food Analyzer App.

## ✅ Schema Compliance

All scripts match your actual Supabase schema:

### `ingredients`
- `id`, `name`, `normalized_name`, `alternative_names`, `aliases`
- `common_names`, `english_names`, `e_code`
- `category`, `additive_group`, `risk_level`
- `short_description`, `long_description`, `child_warning`
- `source_references`, `source_url`

### `products`
- `id`, `barcode`, `name`, `normalized_name`, `brand`
- `category_id`, `image_url`, `ingredients_text`, `nutrition_text`
- `source`, `source_url`, `verification_status`

### `product_reviews`
- `product_id`, `score_label`, `summary`, `warning_text`
- `positive_points`, `negative_points`, `consumption_advice`
- `suitable_for_children`

### `product_ingredients`
- `product_id`, `ingredient_id`, `raw_text`
- `detected_from`, `confidence_score`

---

## 📦 What's Included

```
scripts/
├── transform_ingredients.py   # Transform seed data to schema
├── safe_importer.py          # Import ingredients (dry-run first)
├── fetch_off_products.py     # Fetch from Open Food Facts
└── upload_products.py        # Upload products + reviews + links
```

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
pip install requests supabase python-dotenv
```

### 2. Setup Environment

Create `.env` file:

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here
```

**Important:** Only `SUPABASE_ANON_KEY` is needed (no service_role key required).

### 3. Transform Ingredients

```bash
cd scripts
python transform_ingredients.py
```

Output: `ingredients_transformed.json` (matches your schema)

### 4. Test Import (Dry-Run)

```bash
python safe_importer.py
```

This shows what WOULD be imported without making changes.

### 5. Import Ingredients (Real)

```bash
python safe_importer.py --real
```

Imports ~100 ingredients with E-codes and descriptions.

### 6. Fetch OFF Products

```bash
python fetch_off_products.py --pages 10
```

Fetches ~1000 Turkish products with automatic scoring.

Output: `off_products_scored.json`

### 7. Test Product Upload (Dry-Run)

```bash
python upload_products.py --limit 10
```

Test with 10 products first.

### 8. Upload Products (Real)

```bash
python upload_products.py --real --limit 100
```

Start with 100 products, then increase.

---

## 🎯 Import Strategy

### Ingredients First

Ingredients must be imported before products (for matching).

```bash
# Transform
python transform_ingredients.py

# Dry-run
python safe_importer.py

# Real import
python safe_importer.py --real
```

### Products Second

Products are imported with:
- `source = 'Open Food Facts'`
- `verification_status = 'imported'`
- Automatic scoring (deterministic rules)
- Ingredient matching and linking

```bash
# Fetch from OFF
python fetch_off_products.py --pages 5

# Dry-run
python upload_products.py --limit 10

# Real import
python upload_products.py --real --limit 100
```

---

## 📊 Scoring System

Products are scored using deterministic rules:

### Score Calculation

Starting score: **100**

**Penalties:**
- High-risk E-code (E102, E250, etc): **-25 each**
- Medium-risk E-code (E621, E338, etc): **-10 each**
- Processed sugar (glucose syrup, HFCS): **-15**
- Nitrite/nitrate (E249-E252): **-30**
- Too many ingredients (>20): **-15**
- Too many E-codes (>7): **-15**
- Palm oil: **-10**

**Bonuses:**
- No E-codes: **+20**
- Few ingredients (≤5): **+15**
- Few E-codes (≤3): **+5**

### Score Labels

- **iyi_secim**: 75-100 points
- **orta**: 50-74 points
- **dikkatli_tuket**: 25-49 points
- **sik_tuketme**: 0-24 points

### Child Safety

Products with high-risk E-codes, nitrites, or score <50 are marked:
```json
"suitable_for_children": false
```

---

## 🔧 Command Reference

### Transform Ingredients

```bash
python transform_ingredients.py
```

### Import Ingredients

```bash
# Dry-run (default)
python safe_importer.py

# Real import
python safe_importer.py --real

# Custom batch size
python safe_importer.py --real --batch 100
```

### Fetch Products

```bash
# Default: 10 pages (~1000 products)
python fetch_off_products.py

# Custom page count
python fetch_off_products.py --pages 50

# Output: off_products_scored.json
```

### Upload Products

```bash
# Dry-run with limit
python upload_products.py --limit 10

# Real import
python upload_products.py --real

# Batch processing
python upload_products.py --real --limit 500 --batch 20
```

---

## 🛡️ Safety Features

### Idempotent Operations

All scripts use upsert logic:
- **Ingredients**: matched by `e_code` or `normalized_name`
- **Products**: matched by `barcode`
- **Reviews**: deleted and recreated (not duplicated)
- **Links**: checked before insertion

### Dry-Run Mode

Every script has dry-run mode (default):
```bash
python upload_products.py          # Dry-run
python upload_products.py --real   # Actual changes
```

### Batch Limits

Test with small batches first:
```bash
python upload_products.py --limit 10    # Test with 10 products
python upload_products.py --limit 100   # Then 100
python upload_products.py --real        # Finally, all
```

### No Service Role Key

All scripts use `SUPABASE_ANON_KEY` only.

Row-level security (RLS) policies control access.

---

## 📈 Expected Results

### After Ingredient Import

```
✅ Ingredients import complete!
   New: 98
   Updated: 2
   Errors: 0
```

Your `ingredients` table will have:
- ~100 ingredients
- E-codes (E250, E330, etc.)
- Risk levels (low/medium/high)
- Turkish descriptions
- Child warnings for high-risk items

### After Product Import

```
✅ Upload complete!

Products:
  New: 856
  Updated: 44
  Skipped: 0

Reviews created: 900
Ingredient links: 4,231
```

Your database will have:
- ~900 products from Turkey
- Each with score_label and review
- Linked to matched ingredients
- `verification_status = 'imported'`

---

## 🔍 Verification

### Check Ingredients

```sql
SELECT COUNT(*) FROM ingredients;
SELECT COUNT(*) FROM ingredients WHERE e_code IS NOT NULL;
SELECT * FROM ingredients WHERE risk_level = 'high';
```

### Check Products

```sql
SELECT COUNT(*) FROM products;
SELECT COUNT(*) FROM products WHERE verification_status = 'imported';
SELECT * FROM products WHERE barcode = '8690632022758';
```

### Check Reviews

```sql
SELECT 
  score_label, 
  COUNT(*) 
FROM product_reviews 
GROUP BY score_label;
```

### Check Links

```sql
SELECT COUNT(*) FROM product_ingredients;
```

---

## ⚠️ Troubleshooting

### "SUPABASE_URL not found"

Create `.env` file with your credentials.

### "ingredients cache empty"

Run ingredient import first:
```bash
python safe_importer.py --real
```

### "off_products_scored.json not found"

Fetch products first:
```bash
python fetch_off_products.py
```

### Duplicate key errors

Normal - script skips existing records.

### Low ingredient match rate

Expected for first import. Match rate improves as ingredient DB grows.

Add missing ingredients manually or via admin panel.

---

## 🎓 Best Practices

### Start Small

1. Import ingredients first (required)
2. Fetch 5 pages (~500 products)
3. Test upload with `--limit 10`
4. Check database manually
5. Upload batch of 100
6. Verify in app
7. Upload rest

### Progressive Expansion

```bash
# Week 1: Core ingredients + 500 products
python fetch_off_products.py --pages 5
python upload_products.py --real --limit 500

# Week 2: Add 1000 more
python fetch_off_products.py --pages 10
python upload_products.py --real

# Week 3: Full import
python fetch_off_products.py --pages 50
python upload_products.py --real
```

### Quality Control

After each batch:
- Check `verification_status = 'needs_review'`
- Review products with warnings
- Verify ingredient matching worked
- Test in Flutter app

---

## 📝 Notes

### Verification Status

Imported products have:
```
verification_status = 'imported'
```

Products missing ingredients_text:
```
verification_status = 'needs_review'
```

Admin should review before publishing.

### Source Attribution

All products include:
```json
{
  "source": "Open Food Facts",
  "source_url": "https://world.openfoodfacts.org/product/{barcode}"
}
```

### Scoring Philosophy

Scoring is **deterministic and rule-based**.

No AI/ML involved - all rules are explicit and auditable.

Rules match your `SCORING_RULES.md` document.

---

## 🚦 Import Checklist

- [ ] `.env` file created with Supabase credentials
- [ ] Dependencies installed (`pip install -r requirements.txt`)
- [ ] Ingredients transformed (`python transform_ingredients.py`)
- [ ] Ingredients imported (`python safe_importer.py --real`)
- [ ] OFF products fetched (`python fetch_off_products.py --pages 5`)
- [ ] Products tested (`python upload_products.py --limit 10`)
- [ ] Products uploaded (`python upload_products.py --real --limit 100`)
- [ ] Database verified (SQL queries)
- [ ] App tested with imported data

---

## 🎯 Next Steps

After successful import:

1. **Review draft products** via admin panel
2. **Add missing ingredients** manually
3. **Improve matching** by adding aliases to ingredients
4. **Fetch more products** incrementally
5. **Set up user submissions** to grow database
6. **Monitor quality** through admin dashboard

---

## 💡 Tips

- Always dry-run first
- Start with small batches
- Check database after each batch
- Keep OFF rate-limited (built-in delays)
- Ingredients cache speeds up matching
- Missing matches are normal initially
- Build ingredient DB over time

---

## 🆘 Support

Issues with import? Check:

1. `.env` file exists and has correct credentials
2. Ingredient import ran successfully
3. JSON files exist in scripts/ directory
4. Database tables match schema
5. RLS policies allow inserts

For schema questions, see main project README.

---

## Comprehensive Risk Library Import

This project now includes a broad packaged-food risk/signal library for Turkey:

- `scripts/import_tools/risk_ingredient_library_seed.json` (generated seed)
- `scripts/import_tools/build_risk_ingredient_library_seed.py` (seed generator)
- `scripts/import_tools/validate_risk_ingredient_library.py` (quality checks)
- `scripts/import_tools/import_risk_ingredient_library.py` (Supabase importer)

### 1. Build or refresh the seed

```bash
python scripts/import_tools/build_risk_ingredient_library_seed.py
```

### 2. Validate the seed

```bash
python scripts/import_tools/validate_risk_ingredient_library.py
```

Validation checks:

- no duplicate `canonical_name`
- required `consumer_section`
- required `risk_level`
- normalized/de-duplicated `aliases`

### 3. Dry-run import

```bash
python scripts/import_tools/import_risk_ingredient_library.py
```

### 4. Real import

```bash
python scripts/import_tools/import_risk_ingredient_library.py --real
```

### Notes

- Importer matches ingredients by canonical name, aliases, and E-codes.
- Library tone is calm and consumer-friendly, with short deterministic summaries.
- Unknown ingredients remain an internal/debug concern and are not surfaced in normal user UI.

---

**Happy Importing! 🎉**


---

## SAFETY RECOMMENDATIONS

### Never import large batches immediately

Recommended rollout:

```bash
python upload_products.py --limit 10
python upload_products.py --real --limit 10
```

Test with small batches first before importing hundreds or thousands of products.

### Verified Product Protection

Local verified products are considered higher quality than imported OFF data.

Rules:
- verified products must never be overwritten
- imported products can be updated
- pending products can be updated
- user_submitted products can be updated

### Verification Status Rules

Allowed values:
- verified
- pending
- imported
- user_submitted
- rejected

OFF imports should use:
- imported
- pending (if data incomplete)

---

## 🧠 Ingredient Intelligence Metadata (NEW)

Populate ingredient explanation cards with curated, educational metadata.

### What's Intelligence Metadata?

Each ingredient can have:

```json
{
  "ingredient_type": "Sentetik renklendirici",
  "short_purpose": "Kırmızı/sarı renk sağlamak",
  "short_risk_summary": "Bazı kişilerde hiperaktiviteye neden olabilir",
  "caution_groups": ["çocuklar", "ADHD bulguları"],
  "processing_role": "Meşrubatlar, enerji içecekleri",
  "risk_level": "medium",
  "category_tags": ["soft drinks", "snacks"]
}
```

### Database Schema

Add these columns to `ingredients` table:

```sql
ALTER TABLE ingredients ADD COLUMN ingredient_type TEXT NULL;
ALTER TABLE ingredients ADD COLUMN short_purpose TEXT NULL;
ALTER TABLE ingredients ADD COLUMN short_risk_summary TEXT NULL;
ALTER TABLE ingredients ADD COLUMN caution_groups TEXT[] NULL;
ALTER TABLE ingredients ADD COLUMN processing_role TEXT NULL;
```

### Import Intelligence Seeds

**Step 1: Verify seed file exists**

```bash
ls ingredient_intelligence_seed.json
```

File should contain 150+ curated ingredients with metadata.

**Step 2: Test import (dry-run)**

```bash
python import_ingredient_intelligence.py
```

Shows what WOULD be imported:
```
✓ Created:  45 new ingredients
✓ Updated:  102 existing ingredients
⊘ Skipped:  3 ingredients
```

**Step 3: Apply metadata**

```bash
python import_ingredient_intelligence.py --real
```

Updates existing ingredients and creates new ones with metadata.

### Upsert Logic

The importer matches ingredients by:
1. Canonical name (exact normalized match)
2. Aliases (any name variation)
3. E-code (if present)

If ingredient exists → **updates** with new metadata
If ingredient doesn't exist → **creates** new one

All upserts are **idempotent** - safe to run multiple times.

### Included Seed Data

`ingredient_intelligence_seed.json` includes 150+ common ingredients:

**High-risk additives:**
- Sodyum nitrit (E250)
- Tartrazin (E102)
- Allura red (E129)
- Aspartam, sukraloz, asesülam K

**Common ingredients:**
- Palmiye yağı, şeker, tuz
- Aroma vericileri, emülgatörler
- Mısır şurubu, glikoz şurubu

**Natural/healthy ingredients:**
- Yulaf, tam tahıl
- Fındık, badem, kakao
- Probiyotikler, lif

**Processing additives:**
- Koruyucular (benzoat, sorbat)
- Kıvam vericileri (ksantan gam, karagenan)
- Renklendirici (karamel renk)

**Turkish language explanations:**
- Calm, educational tone
- No fear-based language
- Non-alarmist health descriptions
- 1-3 sentence summaries
- Practical caution groups

### Tone Guidelines

All metadata follows strict guidelines:

✅ **DO:**
- "Yüksek tüketimde… ilişkilendirilebilir"
- "Bazı kişilerde hassasiyet oluşturabilir"
- "Ultra işlenmiş ürünlerde yaygın görülür"

❌ **DON'T:**
- "Causes cancer!"
- "DANGEROUS!"
- "Avoid at all costs"
- Medical diagnoses
- Disease claims

### Using in Flutter App

Intelligence metadata displays in:

1. **Ingredient Match Card** (search results)
   - Quick type/purpose/risk
   - Caution groups as tags
   - Color-coded risk level

2. **Ingredient Detail Page** (full view)
   - All metadata sections
   - Processing role context
   - Source references

3. **Product Analysis**
   - Cards show educational information
   - Helps users understand detected ingredients
   - Maintains calm, deterministic approach

### Example Workflow

```bash
# 1. Check what's in seed file
head -30 ingredient_intelligence_seed.json

# 2. Dry-run import
python import_ingredient_intelligence.py

# 3. Review output
# Should show ~150 ingredients to be created/updated

# 4. Apply to database
python import_ingredient_intelligence.py --real

# 5. Test in Flutter app
# Run app and search for product
# Ingredient cards should now show metadata
```

### Updating Seeds

To add new ingredients or improve explanations:

1. Edit `ingredient_intelligence_seed.json`
2. Add/modify entries following existing format
3. Run import with `--real`
4. Script handles upserts safely

Example new entry:

```json
{
  "canonical_name": "Sentetik Vanilya",
  "aliases": ["synthetic vanilla", "vanillin"],
  "ingredient_type": "Aroma vericisi",
  "short_purpose": "Vanilya aroması vermek",
  "short_risk_summary": "Genel olarak güvenli, doğal vanilya alternatifi",
  "caution_groups": [],
  "processing_role": "Şekerli ürünler, tatlılar, içecekler",
  "risk_level": "low",
  "category_tags": ["desserts", "soft drinks"]
}
```

### Verification

Check metadata in database:

```sql
-- Count ingredients with metadata
SELECT COUNT(*) FROM ingredients 
WHERE ingredient_type IS NOT NULL;

-- View complete metadata for ingredient
SELECT name, ingredient_type, short_purpose, short_risk_summary, caution_groups
FROM ingredients
WHERE normalized_name = 'palmiye yagi';

-- Find high-risk ingredients
SELECT name, risk_level, caution_groups
FROM ingredients
WHERE risk_level = 'high'
ORDER BY name;
```

### Scaling Intelligence Data

Initial seed covers ~150 common ingredients.

To expand:
1. Identify missing ingredients from products
2. Add to seed file
3. Include proper metadata
4. Run import
5. Repeat

Over time, your ingredient database becomes increasingly curated with educational content.

---

**Note:** Intelligence import is safe, idempotent, and designed for incremental expansion.

### RLS Note

If writes fail:
- your Supabase RLS policies may block anon-key writes
- create temporary admin import policies if needed

---

## Open Food Facts 403 Fix

`fetch_off_products.py` now sends a clear User-Agent:

```text
FoodAnalyzerApp/1.0 (contact: your-email@example.com)
```

Before production usage, replace `your-email@example.com` with your real contact/support email.

Test:

```bash
python fetch_off_products.py --pages 1
```

If 403 continues:
- reduce page size
- wait and retry later
- ensure User-Agent includes a real contact email
