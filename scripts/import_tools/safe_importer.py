"""
Safe Supabase Importer
- Dry-run mode
- Batch processing
- Idempotent upserts
- Service-role authentication required for catalogue writes
- Matches actual schema
"""

import json
import os
from typing import List, Dict, Optional
from dataclasses import dataclass
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


@dataclass
class ImportStats:
    """Track import statistics"""
    ingredients_new: int = 0
    ingredients_updated: int = 0
    ingredients_skipped: int = 0
    products_new: int = 0
    products_updated: int = 0
    products_skipped: int = 0
    reviews_created: int = 0
    links_created: int = 0
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []


class SafeSupabaseImporter:
    """
    Safe importer that:
    - Never duplicates
    - Has dry-run mode
    - Batches requests
    - Matches schema exactly
    """
    
    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        self.stats = ImportStats()
        
        if not dry_run:
            supabase_url = os.getenv('SUPABASE_URL')
            supabase_key = (
                os.getenv('SUPABASE_SERVICE_ROLE_KEY')
                or os.getenv('SUPABASE_SERVICE_KEY')
            )
            
            if not supabase_url or not supabase_key:
                raise ValueError(
                    "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set"
                )
            
            self.supabase: Client = create_client(supabase_url, supabase_key)
            print("✓ Connected to Supabase\n")
        else:
            self.supabase = None
            print("🔍 DRY-RUN MODE - No actual changes will be made\n")
        
        # Cache for faster lookups
        self.ingredients_cache = {}  # normalized_name -> id
        self.e_code_cache = {}  # e_code -> id
    
    def load_ingredients_cache(self):
        """Load existing ingredients into cache"""
        if self.dry_run:
            print("🔍 [DRY-RUN] Would load ingredients cache")
            return
        
        print("📥 Loading ingredients cache...")
        
        try:
            response = self.supabase.table('ingredients')\
                .select('id, normalized_name, e_code')\
                .execute()
            
            for ing in response.data:
                if ing.get('normalized_name'):
                    self.ingredients_cache[ing['normalized_name']] = ing['id']
                if ing.get('e_code'):
                    self.e_code_cache[ing['e_code'].upper()] = ing['id']
            
            print(f"✓ Cached {len(response.data)} ingredients\n")
        except Exception as e:
            print(f"⚠️  Could not load cache: {e}\n")
    
    def find_ingredient_id(self, normalized_name: str = None, e_code: str = None) -> Optional[str]:
        """Find ingredient ID by normalized_name or e_code"""
        
        # Try e_code first (more specific)
        if e_code:
            e_code_upper = e_code.upper()
            if e_code_upper in self.e_code_cache:
                return self.e_code_cache[e_code_upper]
        
        # Try normalized name
        if normalized_name:
            if normalized_name in self.ingredients_cache:
                return self.ingredients_cache[normalized_name]
        
        return None
    
    def upsert_ingredient(self, ingredient: Dict) -> Optional[str]:
        """
        Upsert ingredient by e_code or normalized_name
        Returns ingredient_id
        """
        
        normalized_name = ingredient.get('normalized_name')
        e_code = ingredient.get('e_code')
        
        # Check if exists
        existing_id = self.find_ingredient_id(normalized_name, e_code)
        
        if self.dry_run:
            if existing_id:
                print(f"  🔍 [DRY-RUN] Would update: {ingredient['name']}")
                self.stats.ingredients_updated += 1
            else:
                print(f"  🔍 [DRY-RUN] Would insert: {ingredient['name']}")
                self.stats.ingredients_new += 1
            return "dry-run-id"
        
        try:
            if existing_id:
                # Update existing
                self.supabase.table('ingredients')\
                    .update(ingredient)\
                    .eq('id', existing_id)\
                    .execute()
                
                self.stats.ingredients_updated += 1
                return existing_id
            else:
                # Insert new
                result = self.supabase.table('ingredients')\
                    .insert(ingredient)\
                    .execute()
                
                new_id = result.data[0]['id']
                
                # Update cache
                if normalized_name:
                    self.ingredients_cache[normalized_name] = new_id
                if e_code:
                    self.e_code_cache[e_code.upper()] = new_id
                
                self.stats.ingredients_new += 1
                return new_id
                
        except Exception as e:
            error_msg = f"Ingredient {ingredient['name']}: {e}"
            self.stats.errors.append(error_msg)
            print(f"  ✗ {error_msg}")
            return None
    
    def import_ingredients(self, json_file: str, batch_size: int = 50):
        """Import ingredients from transformed JSON"""
        
        print(f"📦 Importing ingredients from {json_file}...")
        print(f"   Batch size: {batch_size}\n")
        
        with open(json_file, 'r', encoding='utf-8') as f:
            ingredients = json.load(f)
        
        total = len(ingredients)
        
        for i in range(0, total, batch_size):
            batch = ingredients[i:i+batch_size]
            
            print(f"Processing batch {i//batch_size + 1} ({i+1}-{min(i+batch_size, total)}/{total})...")
            
            for ing in batch:
                self.upsert_ingredient(ing)
            
            if not self.dry_run:
                time.sleep(0.1)  # Rate limiting
        
        print(f"\n✅ Ingredients import complete!")
        print(f"   New: {self.stats.ingredients_new}")
        print(f"   Updated: {self.stats.ingredients_updated}")
        print(f"   Errors: {len(self.stats.errors)}\n")
    
    def upsert_product(self, product: Dict) -> Optional[str]:
        """
        Upsert product by barcode
        Returns product_id
        """
        
        barcode = product.get('barcode')
        
        if not barcode:
            self.stats.products_skipped += 1
            return None
        
        if self.dry_run:
            print(f"  🔍 [DRY-RUN] Would upsert product: {product['name'][:40]}...")
            self.stats.products_new += 1
            return "dry-run-product-id"
        
        try:
            # Check if exists
            existing = self.supabase.table('products')\
                .select('id')\
                .eq('barcode', barcode)\
                .execute()
            
            if existing.data:
                # Update
                product_id = existing.data[0]['id']
                
                self.supabase.table('products')\
                    .update(product)\
                    .eq('id', product_id)\
                    .execute()

                scoring = run_product_scoring_lifecycle(product_id, 'catalogue_change')
                print_scoring_lifecycle_result(product_id, scoring)
                
                self.stats.products_updated += 1
                return product_id
            else:
                # Insert
                result = self.supabase.table('products')\
                    .insert(product)\
                    .execute()

                product_id = result.data[0]['id']
                scoring = run_product_scoring_lifecycle(product_id, 'catalogue_change')
                print_scoring_lifecycle_result(product_id, scoring)

                self.stats.products_new += 1
                return product_id
                
        except Exception as e:
            error_msg = f"Product {barcode}: {e}"
            self.stats.errors.append(error_msg)
            print(f"  ✗ {error_msg}")
            return None
    
    def create_product_review(self, product_id: str, review: Dict):
        """Create or update product review"""
        
        if self.dry_run:
            print(f"  🔍 [DRY-RUN] Would create review for product {product_id}")
            self.stats.reviews_created += 1
            return
        
        try:
            # Delete old review if exists
            self.supabase.table('product_reviews')\
                .delete()\
                .eq('product_id', product_id)\
                .execute()
            
            # Insert new review
            review['product_id'] = product_id
            
            self.supabase.table('product_reviews')\
                .insert(review)\
                .execute()
            
            self.stats.reviews_created += 1
            
        except Exception as e:
            error_msg = f"Review for {product_id}: {e}"
            self.stats.errors.append(error_msg)
    
    def link_product_ingredient(self, product_id: str, ingredient_id: str, raw_text: str):
        """Create product_ingredient link"""
        
        if self.dry_run:
            return
        
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
                
                self.stats.links_created += 1
                
        except Exception as e:
            # Ignore duplicate link errors
            if 'duplicate' not in str(e).lower():
                error_msg = f"Link {product_id}-{ingredient_id}: {e}"
                self.stats.errors.append(error_msg)
    
    def print_summary(self):
        """Print import summary"""
        
        print("\n" + "="*60)
        print("IMPORT SUMMARY")
        print("="*60)
        
        if self.dry_run:
            print("🔍 DRY-RUN MODE (no actual changes made)")
        
        print(f"\nIngredients:")
        print(f"  New: {self.stats.ingredients_new}")
        print(f"  Updated: {self.stats.ingredients_updated}")
        print(f"  Skipped: {self.stats.ingredients_skipped}")
        
        print(f"\nProducts:")
        print(f"  New: {self.stats.products_new}")
        print(f"  Updated: {self.stats.products_updated}")
        print(f"  Skipped: {self.stats.products_skipped}")
        
        print(f"\nReviews created: {self.stats.reviews_created}")
        print(f"Links created: {self.stats.links_created}")
        
        if self.stats.errors:
            print(f"\n⚠️  Errors: {len(self.stats.errors)}")
            for error in self.stats.errors[:10]:
                print(f"  - {error}")
            if len(self.stats.errors) > 10:
                print(f"  ... and {len(self.stats.errors) - 10} more")
        
        print("\n" + "="*60 + "\n")


def main():
    """Interactive main function"""
    
    import sys
    
    print("="*60)
    print("SAFE SUPABASE IMPORTER")
    print("="*60)
    print()
    
    # Check if dry-run
    dry_run = True
    if '--real' in sys.argv:
        confirm = input("⚠️  You are about to make REAL changes. Continue? (yes/no): ")
        if confirm.lower() != 'yes':
            print("Cancelled.")
            return
        dry_run = False
    
    importer = SafeSupabaseImporter(dry_run=dry_run)
    
    if not dry_run:
        importer.load_ingredients_cache()
    
    # Import ingredients
    if os.path.exists('ingredients_transformed.json'):
        batch_size = 50
        if '--batch' in sys.argv:
            idx = sys.argv.index('--batch')
            if idx + 1 < len(sys.argv):
                batch_size = int(sys.argv[idx + 1])
        
        importer.import_ingredients('ingredients_transformed.json', batch_size=batch_size)
    else:
        print("⚠️  ingredients_transformed.json not found!")
        print("   Run: python transform_ingredients.py first\n")
    
    # Print summary
    importer.print_summary()
    
    if dry_run:
        print("💡 To run for real, use: python safe_importer.py --real")
        print("💡 To set batch size, use: python safe_importer.py --batch 100\n")


if __name__ == "__main__":
    main()
