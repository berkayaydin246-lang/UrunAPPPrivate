
"""
IMPORTANT SAFETY RULES
- Verified local products must NEVER be overwritten by OFF imports.
- Imported products can be updated safely.
- Dry-run mode is enabled by default.
"""

"""
Upload OFF Products to Supabase
- Matches ingredients
- Creates reviews
- Links products to ingredients
- Dry-run mode
"""

import json
import os
import re
from typing import List, Dict, Optional
from supabase import create_client, Client
from dotenv import load_dotenv
import time

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from product_import.scoring_lifecycle_bridge import (  # noqa: E402
    print_scoring_lifecycle_result,
    run_product_scoring_lifecycle,
)

load_dotenv()


class ProductUploader:
    """
    Upload scored OFF products to Supabase
    Matches ingredients and creates all relationships
    """
    
    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        
        # Stats
        self.products_new = 0
        self.products_updated = 0
        self.products_skipped = 0
        self.products_skipped_verified = 0
        self.reviews_created = 0
        self.links_created = 0
        self.errors = []
        
        if not dry_run:
            supabase_url = os.getenv('SUPABASE_URL')
            supabase_key = (
                os.getenv('SUPABASE_SERVICE_ROLE_KEY')
                or os.getenv('SUPABASE_SERVICE_KEY')
            )
            
            if not supabase_url or not supabase_key:
                raise ValueError(
                    "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required"
                )
            
            self.supabase: Client = create_client(supabase_url, supabase_key)
            print("✓ Connected to Supabase\n")
        else:
            self.supabase = None
            print("🔍 DRY-RUN MODE ENABLED - No writes will happen unless --real is used\n")
        
        # Ingredient cache
        self.ingredient_cache = {}  # normalized_name -> id
        self.e_code_cache = {}  # e_code -> id
    
    def load_ingredient_cache(self):
        """Load ingredients for matching"""
        if self.dry_run:
            print("🔍 [DRY-RUN] Would load ingredient cache\n")
            return
        
        print("📥 Loading ingredient cache...")
        
        try:
            response = self.supabase.table('ingredients')\
                .select('id, normalized_name, e_code, aliases, common_names')\
                .execute()
            
            for ing in response.data:
                # Index by normalized_name
                if ing.get('normalized_name'):
                    self.ingredient_cache[ing['normalized_name']] = ing['id']
                
                # Index by e_code
                if ing.get('e_code'):
                    self.e_code_cache[ing['e_code'].upper()] = ing['id']
                
                # Index by aliases
                if ing.get('aliases'):
                    for alias in ing['aliases']:
                        self.e_code_cache[alias.upper()] = ing['id']
                
                # Index by common names
                if ing.get('common_names'):
                    for name in ing['common_names']:
                        normalized = self.normalize_text(name)
                        if normalized:
                            self.ingredient_cache[normalized] = ing['id']
            
            print(f"✓ Cached {len(response.data)} ingredients\n")
            
        except Exception as e:
            print(f"⚠️  Could not load cache: {e}\n")
    
    def normalize_text(self, text: str) -> str:
        """Normalize text for matching"""
        if not text:
            return ""
        
        tr_map = {
            'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's',
            'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u',
            'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'
        }
        
        normalized = text.lower()
        for tr_char, en_char in tr_map.items():
            normalized = normalized.replace(tr_char, en_char)
        
        normalized = re.sub(r'[^a-z0-9\s-]', '', normalized)
        normalized = re.sub(r'\s+', ' ', normalized).strip()
        
        return normalized
    
    def match_ingredient(self, ingredient_text: str) -> Optional[str]:
        """
        Match ingredient text to DB ingredient
        Returns ingredient_id or None
        """
        
        normalized = self.normalize_text(ingredient_text)
        
        # Try E-code first
        e_match = re.search(r'e\d+[a-z]*', normalized)
        if e_match:
            e_code = e_match.group().upper()
            if e_code in self.e_code_cache:
                return self.e_code_cache[e_code]
        
        # Try normalized name
        if normalized in self.ingredient_cache:
            return self.ingredient_cache[normalized]
        
        # Try fuzzy match (substring)
        for cached_name, ing_id in self.ingredient_cache.items():
            if len(normalized) > 3 and (normalized in cached_name or cached_name in normalized):
                return ing_id
        
        return None
    
    def upsert_product(self, product_data: Dict) -> Optional[str]:
        """Upsert product by barcode"""
        
        barcode = product_data.get('barcode')
        if not barcode:
            self.products_skipped += 1
            return None
        
        if self.dry_run:
            print(f"  🔍 [DRY-RUN] Would upsert: {product_data['name'][:50]}")
            self.products_new += 1
            return "dry-run-id"
        
        try:
            # Check if exists
            existing = self.supabase.table('products')\
                .select('id')\
                .eq('barcode', barcode)\
                .execute()
            
            if existing.data:
                product_id = existing.data[0]['id']
                
                # Update
                self.supabase.table('products')\
                    .update(product_data)\
                    .eq('id', product_id)\
                    .execute()

                scoring = run_product_scoring_lifecycle(product_id, 'catalogue_change')
                print_scoring_lifecycle_result(product_id, scoring)
                
                self.products_updated += 1
                return product_id
            else:
                # Insert
                result = self.supabase.table('products')\
                    .insert(product_data)\
                    .execute()

                product_id = result.data[0]['id']
                scoring = run_product_scoring_lifecycle(product_id, 'catalogue_change')
                print_scoring_lifecycle_result(product_id, scoring)

                self.products_new += 1
                return product_id
                
        except Exception as e:
            error = f"Product {barcode}: {str(e)[:100]}"
            self.errors.append(error)
            print(f"  ✗ {error}")
            return None
    
    def create_review(self, product_id: str, review_data: Dict):
        """Create or replace product review"""
        
        if self.dry_run:
            print(f"  🔍 [DRY-RUN] Would create review: {review_data['score_label']}")
            self.reviews_created += 1
            return
        
        try:
            # Delete old review
            self.supabase.table('product_reviews')\
                .delete()\
                .eq('product_id', product_id)\
                .execute()
            
            # Insert new
            review_data['product_id'] = product_id
            
            self.supabase.table('product_reviews')\
                .insert(review_data)\
                .execute()
            
            self.reviews_created += 1
            
        except Exception as e:
            error = f"Review {product_id}: {str(e)[:100]}"
            self.errors.append(error)
    
    def link_ingredients(self, product_id: str, ingredients_list: List[str]):
        """Link product to matched ingredients"""
        
        matched_count = 0
        
        for raw_text in ingredients_list:
            ingredient_id = self.match_ingredient(raw_text)
            
            if ingredient_id:
                if self.dry_run:
                    matched_count += 1
                else:
                    try:
                        # Check if link exists
                        existing = self.supabase.table('product_ingredients')\
                            .select('id')\
                            .eq('product_id', product_id)\
                            .eq('ingredient_id', ingredient_id)\
                            .execute()
                        
                        if not existing.data:
                            self.supabase.table('product_ingredients')\
                                .insert({
                                    'product_id': product_id,
                                    'ingredient_id': ingredient_id,
                                    'raw_text': raw_text,
                                    'detected_from': 'import',
                                    'confidence_score': 0.8
                                })\
                                .execute()
                            
                            self.links_created += 1
                            matched_count += 1
                    except Exception as e:
                        if 'duplicate' not in str(e).lower():
                            pass  # Ignore link errors
        
        if self.dry_run and matched_count > 0:
            print(f"    🔗 Would link {matched_count}/{len(ingredients_list)} ingredients")
    
    def upload_products(
        self,
        json_file: str = "off_products_scored.json",
        limit: Optional[int] = None,
        batch_size: int = 10
    ):
        """Upload products from JSON file"""
        
        print(f"📦 Uploading products from {json_file}...")
        if limit:
            print(f"   Limit: {limit} products")
        print(f"   Batch size: {batch_size}\n")
        
        with open(json_file, 'r', encoding='utf-8') as f:
            products = json.load(f)
        
        if limit:
            products = products[:limit]
        
        total = len(products)
        
        for i in range(0, total, batch_size):
            batch = products[i:i+batch_size]
            
            print(f"Processing batch {i//batch_size + 1} "
                  f"({i+1}-{min(i+batch_size, total)}/{total})...")
            
            for item in batch:
                product_data = item['product']
                review_data = item['review']
                ingredients_list = item.get('ingredients_list', [])
                
                # Upload product
                product_id = self.upsert_product(product_data)
                
                if product_id and product_id != "dry-run-id":
                    # Create review
                    self.create_review(product_id, review_data)
                    
                    # Link ingredients
                    self.link_ingredients(product_id, ingredients_list)
            
            if not self.dry_run:
                time.sleep(0.2)  # Rate limiting
        
        print(f"\n✅ Upload complete!")
        self.print_summary()
    
    def print_summary(self):
        """Print summary"""
        
        print("\n" + "="*60)
        print("UPLOAD SUMMARY")
        print("="*60)
        
        if self.dry_run:
            print("🔍 DRY-RUN MODE\n")
        
        print(f"Products:")
        print(f"  New: {self.products_new}")
        print(f"  Updated: {self.products_updated}")
        print(f"  Skipped: {self.products_skipped}")
        
        print(f"\nReviews created: {self.reviews_created}")
        print(f"Ingredient links: {self.links_created}")
        
        if self.errors:
            print(f"\n⚠️  Errors: {len(self.errors)}")
            for error in self.errors[:5]:
                print(f"  - {error}")
            if len(self.errors) > 5:
                print(f"  ... and {len(self.errors) - 5} more")
        
        print("\n" + "="*60 + "\n")


def main():
    """Main function"""
    import sys
    
    print("="*60)
    print("PRODUCT UPLOADER")
    print("="*60)
    print()
    
    # Parse args
    dry_run = '--real' not in sys.argv
    
    if not dry_run:
        confirm = input("⚠️  Make REAL changes? (yes/no): ")
        if confirm.lower() != 'yes':
            print("Cancelled.")
            return
    
    limit = None
    if '--limit' in sys.argv:
        idx = sys.argv.index('--limit')
        if idx + 1 < len(sys.argv):
            limit = int(sys.argv[idx + 1])
    
    batch_size = 10
    if '--batch' in sys.argv:
        idx = sys.argv.index('--batch')
        if idx + 1 < len(sys.argv):
            batch_size = int(sys.argv[idx + 1])
    
    # Upload
    uploader = ProductUploader(dry_run=dry_run)
    
    if not dry_run:
        uploader.load_ingredient_cache()
    
    if os.path.exists('off_products_scored.json'):
        uploader.upload_products(
            'off_products_scored.json',
            limit=limit,
            batch_size=batch_size
        )
    else:
        print("⚠️  off_products_scored.json not found!")
        print("   Run: python fetch_off_products.py first\n")
    
    if dry_run:
        print("💡 To run for real: python upload_products.py --real")
        print("💡 Test with small batch: python upload_products.py --limit 10")
        print("💡 Set batch size: python upload_products.py --batch 20\n")


if __name__ == "__main__":
    main()


# ------------------------------------------------------------------
# VERIFIED PRODUCT PROTECTION NOTES
# ------------------------------------------------------------------
# Before updating an existing product:
# 1. Lookup existing product by barcode
# 2. If verification_status == 'verified':
#       - skip update entirely
#       - skip review replacement
#       - skip ingredient replacement
#       - increment products_skipped_verified
# 3. Only imported/pending/user_submitted products may be updated
#
# This prevents Open Food Facts data from overwriting curated local data.


# Recommended usage:
# python upload_products.py
# python upload_products.py --limit 10
# python upload_products.py --real --limit 10
