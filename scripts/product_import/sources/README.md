# Import sources

Connector modules for future product data sources live here.

Currently supported sources (handled in `common.py`):

- **manual_seed** — highest trust; data curated by us.
- **open_food_facts** — medium/low trust; candidate data only.
- **future_source** — reserved interface for future marketplace/connector
  sources. **Not implemented.** Do not add aggressive scraping, anti-bot
  bypassing, or image hotlinking that violates a site's terms. New connectors
  must produce normalized `ProductCandidate` dicts (see `common.make_candidate`)
  and only ever write to `product_staging`.
- **web_scraper:&lt;id&gt;** — implemented by the automatic web discovery
  pipeline (`../scrape_products_from_web.py` + `../web_scraper/`). It reads
  operator-configured URLs from `data/web_product_sources.yaml`, extracts
  product data (name, brand, image, ingredients, nutrition, optional barcode),
  quality-scores it (barcode-optional), and stages candidates in
  `product_staging` only. See `docs/PRODUCT_DATABASE_SEEDING.md` →
  "Automatic Web Product Discovery".
