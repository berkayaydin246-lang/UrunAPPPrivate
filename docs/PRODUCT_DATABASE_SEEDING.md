# Product Database Seeding

This pipeline collects product **candidates** and stages them for admin review.

## Why everything goes through `product_staging`

```
sources (manual / OFF / future)  →  product_staging  →  [admin review]  →  products
```

- `products` is the clean, user-facing catalog. **Nothing is imported directly into it.**
- `product_staging` holds unverified candidates with a `quality_score`, `missing_fields`
  and a `status` (`pending` / `needs_review` / `insufficient_data` / `approved` / `rejected`).
- An admin promotes staged rows into `products` via the existing staging admin UI.
- Open Food Facts and any future source are treated as **candidate data only**, never trusted final data.

## Layout

```
scripts/product_import/
  common.py                      # shared: OFF fetch, normalization, scoring, validation, upsert
  import_products_from_barcodes.py
  import_products_from_csv.py
  import_products_from_json.py
  sources/                       # interface for future connectors (see sources/README.md)
  output/
data/
  barcodes_turkey_seed.csv
  manual_seed_products.example.csv
  manual_seed_products.example.json
```

## Requirements

```bash
pip install requests python-dotenv
```

Environment (the scripts fail clearly if these are missing for a real run):

```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_SERVICE_KEY=your-service-role-key
```

> ⚠️ **Never commit the service role key.** Keep it in `.env` (gitignored) or your shell.
> ⚠️ **Never put the service role key in the Flutter app.** The app uses the anon key only.

## A. Import a barcode list (Open Food Facts)

`data/barcodes_turkey_seed.csv` columns: `barcode,name_hint,brand_hint,category_hint`.

```bash
# Dry run (no writes)
python3 scripts/product_import/import_products_from_barcodes.py \
  --input data/barcodes_turkey_seed.csv --source open_food_facts --dry-run

# Real insert
python3 scripts/product_import/import_products_from_barcodes.py \
  --input data/barcodes_turkey_seed.csv --source open_food_facts --real
```

## B. Import a manual CSV

Columns: `barcode,name,brand,category_suggestion,category_tags,ingredients_text,
nutrition_json,image_front_url,image_ingredients_url,image_nutrition_url,source,source_url`.

```bash
python3 scripts/product_import/import_products_from_csv.py \
  --input data/manual_seed_products.example.csv --source manual_seed --dry-run

python3 scripts/product_import/import_products_from_csv.py \
  --input data/manual_seed_products.example.csv --source manual_seed --real
```

## C. Import JSON

A JSON array of ProductCandidate-style objects.

```bash
python3 scripts/product_import/import_products_from_json.py \
  --input data/manual_seed_products.example.json --source manual_seed --dry-run

python3 scripts/product_import/import_products_from_json.py \
  --input data/manual_seed_products.example.json --source manual_seed --real
```

## CLI flags

| Flag | Meaning |
|------|---------|
| `--input PATH` | Input file (required) |
| `--source SRC` | Override source: `manual_seed`, `open_food_facts`, `future_source` |
| `--limit N` | Process at most N rows |
| `--dry-run` | Inspect only; no writes (default when `--real` is absent) |
| `--real` | Write to `product_staging` |
| `--force` | Overwrite existing rows even if approved/rejected or worse quality |
| `--only-missing` | Only fill missing fields; never replace on quality |
| `--min-quality N` | Skip candidates scoring below N |

## Normalization

- **Nutrition** (`nutrition_json`): common per-100g / OFF dash keys are mapped to
  `energy_kcal, fat, saturated_fat, carbohydrates, sugars, fiber, proteins, salt, sodium`.
  When `salt` is absent but `sodium` is present, `salt = sodium * 2.5`.
- **Ingredients**: whitespace collapsed, Turkish characters preserved, stored as raw text
  (no parsing, no health claims, no AI scoring at import time).

## Quality scoring & status

Weights (sum 100): barcode 15, name 15, brand 10, front image 15, ingredients 25,
nutrition 20, category 10.

| Score | Status |
|-------|--------|
| ≥ 70 | `pending` |
| 40–69 | `needs_review` |
| < 40 | `insufficient_data` |

Imports **never** auto-approve.

## Upsert behavior

Candidates match an existing staging row by **(barcode, source)**:

- No match → insert.
- Match → update only when the new candidate has a higher `quality_score` **or** fills
  currently-empty fields. Worse data never overwrites better data. `admin_notes` is preserved.
- If the existing row is `approved`/`rejected`, it is skipped unless `--force` is passed.
- `--only-missing` fills gaps only and never replaces on score.

## Validation (before insert)

- `barcode` must be 8–14 digits.
- `source` must be one of the supported values.
- `nutrition_json` must be a JSON object when provided.
- `category_tags` must be a list when provided.
- `name` must be present for a `pending` candidate (otherwise it scores lower and lands in review).

## Verify after a real import

```sql
select barcode, name, brand, quality_score, missing_fields, status, source
from product_staging
order by created_at desc
limit 20;
```

## Admin approval into `products`

Use the existing staging admin UI (`/internal/product-staging`). Approval creates or
enriches a `products` row by barcode and flips the staging row to `approved`. This import
pipeline does not touch `products`.

---

# Automatic Web Product Discovery

Barcode import answers *"given this barcode, what does Open Food Facts know?"*.
The **web discovery scraper** answers the harder question *"find products on the
web and turn them into candidates"* — without typing barcodes one by one.

```
configured source URLs  →  scrape + extract  →  normalize + quality-score  →  product_staging  →  [admin review]  →  products
```

It writes to **`product_staging` only**, never auto-approves, and never invents
missing data — exactly like the barcode importer. The difference is the input:
instead of a barcode list, it crawls **operator-configured** product/category
pages.

## Why scraped data goes to `product_staging`

Web data is the *least* trustworthy source: names, images and tables vary wildly
per site. So every scraped product is a **candidate** scored by the same
deterministic rules and parked for admin review. Nothing scraped is ever shown
to end users until an admin approves it into `products`.

## Layout

```
scripts/product_import/
  scrape_products_from_web.py        # CLI entry point
  web_scraper/
    base.py                          # polite, rate-limited HTTP fetcher
    source_config.py                 # reads data/web_product_sources.yaml
    extractors.py                    # JSON-LD, OpenGraph/meta, Turkish sections, links
    nutrition_parser.py              # Turkish nutrition tables → nutrition_json
    ingredient_parser.py             # ingredients text extraction + cleanup
    image_scoring.py                 # pick a clean front/vitrine image
    runner.py                        # orchestration + quality + dedupe/merge + upsert
    tests/                           # stdlib unittest tests
data/
  web_product_sources.yaml           # ACTIVE config (operator fills in URLs)
  web_product_sources.example.yaml   # commented template
```

## Requirements

```bash
pip install requests pyyaml beautifulsoup4 python-dotenv
# or: pip install -r scripts/product_import/requirements.txt
```

## Configure sources

**Normal use is source/category discovery** — you configure category/listing
URLs *once*, and the scraper then finds product detail URLs automatically. You do
**not** enter every product URL by hand. `--url` direct mode (below) exists only
for testing/debugging a single page.

Nothing is hardcoded. The scraper only visits URLs you place in
`data/web_product_sources.yaml` (copy from the `.example.yaml`). Each source:

| Field | Meaning |
|-------|---------|
| `id` | short id; becomes `source = "web_scraper:<id>"` |
| `enabled` | toggle |
| `type` | `product_pages` (direct URLs) or `category_pages` (discover → visit) |
| `base_url` | optional, resolves relative links |
| `product_urls` | list of product detail URLs (`product_pages`) |
| `category_urls` | list of `{category, url}` discovery pages (`category_pages`) |
| `product_link_selector` | optional CSS selector for product links on a listing |
| `link_selector` | back-compat alias of `product_link_selector` |
| `product_link_patterns` | extra URL substrings marking a product link (e.g. `-p-`) |
| `exclude_link_patterns` | extra URL substrings to skip (added to built-ins) |
| `max_pages_per_category` | listing pages per category (pagination is a future TODO) |
| `next_page_selector` | reserved for future pagination |

Link discovery first tries a configured CSS selector; otherwise it uses generic
URL hints (`/p/`, `/product/`, `/urun/`, `/ürün/`, `-p-`, `/dp/`, `/pr/` plus
your `product_link_patterns`) and filters out cart/login/search/category/static
links (built-in excludes plus your `exclude_link_patterns`).

### How product links are discovered (href, JSON, script)

Many sites do not expose product links as plain `<a href>`. Discovery therefore
runs three strategies and merges/dedupes the results:

1. **`<a href>`** — configured CSS selector, else generic URL hints.
2. **Embedded JSON** — `__NEXT_DATA__`, `application/json`, `window.__INITIAL_STATE__`,
   `window.__NUXT__`, and ld+json are safely `json.loads`-parsed (never executed)
   and walked for `url` / `slug` / `seoUrl` / `productUrl` / `path` values.
   Escaped JSON is handled (`\/`, `/`, `%2F` → `/`).
3. **Raw script text** — product paths/URLs matched directly out of script bodies.

URLs are reconstructed against `base_url`. The scraper never *invents* a URL from
a product name alone — a slug/path must already be present.

### When a category yields no product links

Some sites (e.g. **Migros**) render their listing entirely **client-side / via an
API** — the served HTML contains no product URLs at all, in any of href, JSON or
script. In that case the scraper does **not** fake results and does **not** switch
to browser automation. It logs rich debug stats to the run-log
`skipped[].debug` (`html_length`, `href_link_count`, `pattern_link_count`,
`script_count`, `script_product_url_count`, `json_product_url_count`,
`first_10_candidate_paths`, configured patterns/excludes, `api_endpoint_hints`)
and prints:

```
Category page fetched but no product detail links found.
  href_links=0 script_candidates=0 json_candidates=0 scripts=9 html_length=168911
  -> Category page appears client-rendered or API-backed. Add a source-specific
     API adapter or product_urls (or check product_link_patterns).
```

For such sites you have two controlled options (no anti-bot bypass, no
aggressive crawling):
- list specific `product_urls` for that source (type `product_pages`), or
- enable a source-specific **API adapter** (below).

Direct product URL scraping (`--url`) is unaffected and remains the way to test a
single page; only **category discovery** depends on links being present in the
HTML/JSON.

### Source-specific API adapters (opt-in)

Generic discovery handles static/SSR HTML. For **API-backed** sites an adapter
can discover product detail URLs from the site's *public* listing API. Adapters
live in `scripts/product_import/web_scraper/source_adapters/` and are **opt-in**
via the source's `adapter:` field. They run **only as a fallback** when generic
discovery returns zero links, and they are deliberately conservative:

- they **never guess/brute-force** endpoints — they use a configured
  `api_url_template`, or an endpoint already visible in the page HTML;
- they **never** use browser automation, bypass anti-bot, or scrape private
  pages;
- they **never** build a product URL from a name alone — a slug/path must exist;
- they respect `--limit`, `max_pages_per_category`, the fetcher delay/timeout,
  and stop on `403`/`429` instead of retry-spamming;
- results still flow through the normal pipeline into `product_staging` — nothing
  is auto-approved.

Enable for a source like Migros:

```yaml
sources:
  - id: migros
    enabled: true
    type: category_pages
    base_url: "https://www.migros.com.tr"
    adapter: "migros"
    category_urls:
      - category: salam
        url: "https://www.migros.com.tr/salam-c-112d6"
    product_link_patterns: ["-p-"]
    adapter_config:
      api_url_template: ""        # put a PUBLIC listing API template here when known
      category_id: "112d6"        # else parsed from the -c-<id> URL suffix
      page_param: "page"
      max_pages: 1
```

`api_url_template` placeholders: `{category_id}`, `{category_slug}`, `{page}`,
`{category_url}`. The adapter walks the returned JSON for product URL/slug fields
(`url`, `link`, `href`, `productUrl`, `seoUrl`, `slug`, `path`, `canonicalUrl`),
builds absolute URLs against `base_url`, and filters with
`product_link_patterns` / `exclude_link_patterns`.

**Migros specifics.** Migros' public category API
(`/rest/search/screens/<slug>-c-<id>`) returns products under
`data.searchInfo.storeProductInfos[*]`, and the product detail slug lives in
each item's **`prettyName`** field (e.g. `namet-7-24-hindi-salam-60-g-p-d749eb`)
rather than a `url`/`href`/`seoUrl`. The adapter therefore builds detail URLs as
`base_url + "/" + prettyName` — **only** when `prettyName` contains the `-p-`
product marker (so brand `-b-` / category `-c-` prettyNames are skipped), and
**never** from a product name. `IN_SALE` items are ordered first. It sends safe
public headers (`Accept`, `Accept-Language: tr`, `Referer`, `X-FORWARDED-REST`,
`X-PWA`, `X-Device-PWA`) and no cookies. Pagination is honored only when the
template contains `{page}` and `max_pages > 1`; otherwise just the first page is
fetched.

Working example:

```
adapter_used=migros
adapter_product_urls=10
adapter_endpoint=https://www.migros.com.tr/rest/search/screens/salam-c-112d6
migros_store_product_count=30
migros_prettyname_url_count=30
page_count=2 hit_count=38
```

If no template is configured and none is visible in the HTML, the adapter logs a
clear warning instead of guessing. Adapter debug stats (`adapter_used`,
`endpoint_called`, `product_count`, `raw_count`, `migros_store_product_count`,
`migros_prettyname_url_count`, `first_5_prettyname_urls`, `page_count`,
`hit_count`, `errors`, `warnings`) are saved under `skipped[].debug.adapter` in
the run log.

If no usable URLs are configured the scraper prints and exits without crawling:

```
No product source URLs configured. Add category/product URLs to data/web_product_sources.yaml.
```

## Dry-run (inspect only, writes nothing)

```bash
python3 scripts/product_import/scrape_products_from_web.py \
  --source all --limit 20 --dry-run
```

Single source + category:

```bash
python3 scripts/product_import/scrape_products_from_web.py \
  --source migros --category cips --limit 50 --dry-run
```

Direct single URL — **testing/debugging only** (does not need any configured
source); normal bulk runs use `--source`:

```bash
python3 scripts/product_import/scrape_products_from_web.py \
  --url "https://example.com/product/..." --dry-run
```

## Real staging insert

```bash
python3 scripts/product_import/scrape_products_from_web.py \
  --source all --limit 20 --real
```

Real mode needs `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` (same as the other
importers; never commit them, never ship them in the Flutter app).

### Web scraper CLI flags

| Flag | Meaning |
|------|---------|
| `--source ID|all` | source id from config, or `all` (default) |
| `--category CAT` | restrict to a configured category |
| `--url URL` | scrape one product URL directly |
| `--config PATH` | sources YAML (default `data/web_product_sources.yaml`) |
| `--limit N` | max pages to crawl this run (default 20) |
| `--delay S` | delay between requests (default 1.5s) |
| `--timeout S` | per-request timeout (default 15s) |
| `--min-quality N` | skip candidates scoring below N |
| `--dry-run` / `--real` | inspect only (default) / write to staging |
| `--force` | overwrite `approved`/`rejected` staging rows |

## What gets extracted

1. **JSON-LD** `schema.org/Product`: name, brand, image(s),
   `gtin13/gtin14/gtin/sku` → barcode (optional), description, category;
   `BreadcrumbList` → category.
2. **OpenGraph/meta**: `og:title`, `og:image`, `og:description`, `<title>`.
3. **Turkish labeled sections**: `İçindekiler`, `İçerik`, `Besin Değerleri`,
   `Alerjenler`, `Ürün Bilgileri`, `Net miktar`.

### Generic multi-strategy nutrition extraction

The nutrition extractor is **site-agnostic** (not Migros-specific). It tries, in
order, and merges results:

1. **DOM scan** — any small element whose text is a nutrient label
   (`Enerji/Kalori, Yağ, Doymuş yağ, Karbonhidrat, Şeker, Protein, Tuz, Lif,
   Sodyum`) paired with a nearby numeric value. This covers real `<table>`s,
   `<div>/<span>` row layouts and `<dl>` lists alike, **including hidden tab
   panels**.
2. **Embedded JSON** — `<script type="application/json">` / `__NEXT_DATA__` is
   safely `json.loads`-parsed (never executed) and walked for nutrient
   label/value pairs.
3. **Labeled-text fallback** — when no structure is found, the text around a
   `Besin Değerleri` / `100 g` heading is parsed.

Nutrition keys are the app's canonical per-100g keys
(`energy_kcal, fat, saturated_fat, carbohydrates, sugars, fiber, proteins, salt,
sodium`, plus `energy_kj` when present — **no** `_100g` suffix) so scraped rows
render in the existing product detail / admin UI. Decimal comma/dot are both
handled, `kJ` is converted to kcal (and `energy_kcal` is derived from kJ when
only kJ exists), `mg` → g for salt/sodium, and `salt = sodium * 2.5` is derived
when salt is missing. `Doymuş yağ` is never parsed as plain `Yağ`. **Per-serving**
tables are *not* normalized — they are flagged in
`raw_source_payload.nutrition_warnings` for the admin instead of guessing; an
unknown basis is assumed per-100g but also flagged.

### Ingredients, title, brand, category

Ingredients are extracted generically (labeled section → embedded JSON), HTML
tags stripped, label prefix removed, whitespace collapsed, trailing marketing
trimmed, Turkish characters preserved. No tokenizing, no risk analysis, no
invented ingredients — that stays in the deterministic Dart engine after
approval.

Titles have retailer suffixes stripped (`- Migros`, `| Trendyol`, etc.). Brand
falls back to a **cautious** inference from a small known-brand list, and only on
a confident first-token match — it is never invented. Category comes from JSON-LD
category, then breadcrumb, then the configured source category.

## Image selection

Multiple image candidates are gathered (JSON-LD, `og:image`, gallery, near-title)
and **scored deterministically** to prefer a clean front/vitrine packshot and
penalize banners, logos, shelf/aisle photos, category thumbnails, campaign art
and tiny images. The best URL is stored as `image_front_url`; all scored
candidates are kept in `raw_source_payload.image_candidates` for the admin. A
better image never replaces a worse one on merge.

> Storage upload is optional and not enabled by default — we keep the image URL.
> If/when a storage helper is wired in, selected images can be uploaded to
> `product-staging/front/{safe_source_id}/{hash_or_barcode}.jpg`.

## Quality scoring (barcode-optional)

Web products often have no barcode, so scoring does **not** require one. Weights
sum to 100 without a barcode; a present barcode is a capped bonus.

| Field | Weight |
|-------|--------|
| name | 18 |
| brand | 12 |
| front image | 18 |
| ingredients | 25 |
| nutrition | 20 |
| category | 7 |
| barcode | +10 bonus (optional) |

| Score | Status |
|-------|--------|
| ≥ 80 | `pending` |
| 50–79 | `needs_review` |
| < 50 | `insufficient_data` |

Scraping **never** auto-approves.

## Avoiding duplicate products

Candidates dedupe against existing staging rows by a priority key:

1. **barcode** (when present) + source
2. **source_url** + source
3. normalized **name + brand** (for barcode-less products) within the source

On a match, only empty fields are filled, the better-scored image wins,
`admin_notes` is preserved, and quality is recomputed. `approved`/`rejected`
rows are never overwritten unless `--force` is passed. Cross-source duplicates of
the same physical product (e.g. OFF + web) remain a review-time decision for the
admin.

## Handling products without a barcode

This is the main reason the scraper exists. Barcode-less candidates are fully
supported: they score and stage normally (the `barcode` column is simply null),
dedupe on source_url / name+brand, and appear in the admin queue with a
`barcode` chip in `missing_fields`. Approval still requires a barcode in the
current admin flow, so the admin can add one before approving.

## Review in admin

Scraped rows show up in the existing staging admin UI (`/internal/product-staging`)
exactly like imported rows, with the usual `missing_fields` chips
(`ingredients`, `nutrition`, `category`, `image`). No admin UI changes were made.

## Run logs

Every run writes `scripts/product_import/output/web_scrape_{timestamp}.json`
containing all candidates, skipped URLs, errors and per-source stats.

## Tests

```bash
python3 -m unittest discover -s scripts/product_import/web_scraper/tests
```

Covers the Turkish nutrition parser, ingredient cleanup, image scoring,
dedupe/merge key logic, and barcode-optional quality scoring.

## ⚠️ Source reliability warning

Web sources are the least reliable input. Names, images and tables differ per
site and change without notice. Treat every scraped row as **unverified** —
that is exactly why it lands in `product_staging` for human review. Be a polite
guest: only configure public pages you are permitted to read, keep the request
delay reasonable, do **not** scrape authenticated/private pages, and do **not**
attempt to bypass anti-bot protections. Pages that return `403`/`429` are
skipped, not retried.

---

## Scope note (barcode import)

The barcode importer and bulk Open Food Facts import remain candidate-only and
must never write to `products` directly. Do not add aggressive scraping, anti-bot
bypassing, or image hotlinking that violates a source's terms.
