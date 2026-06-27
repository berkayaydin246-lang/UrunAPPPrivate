"""
Ingredient Intelligence Seed Importer
- Upserts ingredient metadata (ingredient_type, short_purpose, short_risk_summary, etc.)
- Dry-run and real modes
- Batch processing
- Matches by canonical_name and aliases
- Idempotent and safe
"""

import json
import os
import sys
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime
from supabase import create_client, Client
from dotenv import load_dotenv
import re
import time

load_dotenv()


def normalize_name(name: str) -> str:
    """Normalize ingredient name for matching"""
    return re.sub(r'\s+', ' ', name.strip().lower())


@dataclass
class ImportStats:
    """Track import statistics"""
    ingredients_new: int = 0
    ingredients_updated: int = 0
    ingredients_skipped: int = 0
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []


class IngredientIntelligenceImporter:
    """
    Import intelligence metadata for ingredients:
    - ingredient_type: Category/type (e.g., "Rafine bitkisel yağ")
    - short_purpose: Why it's used (1-2 sentences)
    - short_risk_summary: Why it may be concerning (1-2 sentences)
    - caution_groups: Groups to be careful (e.g., ["çocuklar", "diyabet"])
    - processing_role: Where/how used (e.g., "Ultra işlenmiş ürünlerde yaygın")
    - risk_level: low, medium, high
    - category_tags: Product categories (snacks, chocolates, etc.)
    """
    
    def __init__(self, dry_run: bool = True):
        self.dry_run = dry_run
        self.stats = ImportStats()
        
        if not dry_run:
            supabase_url = os.getenv('SUPABASE_URL')
            supabase_key = os.getenv('SUPABASE_ANON_KEY')
            
            if not supabase_url or not supabase_key:
                raise ValueError(
                    "SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env file"
                )
            
            self.supabase: Client = create_client(supabase_url, supabase_key)
            print("✓ Connected to Supabase\n")
        else:
            self.supabase = None
            print("🔍 DRY-RUN MODE - No actual changes will be made\n")
        
        # Cache for faster lookups
        self.ingredients_by_normalized_name = {}  # normalized_name -> {id, name, aliases}
        self.ingredients_by_e_code = {}  # e_code -> id
    
    def load_ingredients_cache(self):
        """Load existing ingredients into cache for matching"""
        if self.dry_run:
            print("🔍 [DRY-RUN] Would load ingredients cache")
            return
        
        print("📥 Loading ingredients cache...")
        
        try:
            response = self.supabase.table('ingredients')\
                .select('id, name, normalized_name, e_code, aliases')\
                .execute()
            
            for ing in response.data:
                normalized = normalize_name(ing.get('normalized_name', ''))
                if normalized:
                    self.ingredients_by_normalized_name[normalized] = ing
                
                if ing.get('e_code'):
                    self.ingredients_by_e_code[ing['e_code'].upper()] = ing['id']
            
            print(f"✓ Cached {len(response.data)} ingredients\n")
        except Exception as e:
            print(f"⚠️  Could not load cache: {e}\n")
            raise
    
    def find_matching_ingredient(
        self, 
        canonical_name: str, 
        aliases: List[str] = None
    ) -> Optional[Dict]:
        """
        Find matching ingredient by:
        1. Canonical name
        2. Aliases
        3. Any name variation
        """
        # Try canonical name first
        canonical_norm = normalize_name(canonical_name)
        if canonical_norm in self.ingredients_by_normalized_name:
            return self.ingredients_by_normalized_name[canonical_norm]
        
        # Try aliases
        if aliases:
            for alias in aliases:
                alias_norm = normalize_name(alias)
                if alias_norm in self.ingredients_by_normalized_name:
                    return self.ingredients_by_normalized_name[alias_norm]
        
        return None
    
    def prepare_update_json(self, intelligence_data: Dict) -> Dict:
        """
        Prepare JSON for updating ingredient with intelligence metadata.
        Only includes non-null fields.
        """
        update_fields = {
            'updated_at': datetime.utcnow().isoformat(),
        }
        
        # Map seed data fields to database fields
        field_mapping = {
            'ingredient_type': 'ingredient_type',
            'short_purpose': 'short_purpose',
            'short_risk_summary': 'short_risk_summary',
            'caution_groups': 'caution_groups',
            'processing_role': 'processing_role',
        }
        
        for seed_field, db_field in field_mapping.items():
            if seed_field in intelligence_data and intelligence_data[seed_field]:
                value = intelligence_data[seed_field]
                
                # Handle arrays (convert lists to postgres arrays)
                if isinstance(value, list):
                    update_fields[db_field] = value
                else:
                    update_fields[db_field] = value
        
        return update_fields
    
    def update_ingredient_intelligence(self, ingredient_id: str, update_data: Dict) -> bool:
        """Update ingredient with intelligence metadata"""
        try:
            self.supabase.table('ingredients').update(update_data).eq('id', ingredient_id).execute()
            return True
        except Exception as e:
            self.stats.errors.append(f"Update failed for {ingredient_id}: {str(e)}")
            return False
    
    def create_ingredient_from_seed(self, seed_data: Dict) -> Optional[str]:
        """Create new ingredient from seed data"""
        try:
            # Prepare insert data
            normalized = normalize_name(seed_data['canonical_name'])
            
            insert_data = {
                'name': seed_data['canonical_name'],
                'normalized_name': normalized,
                'aliases': seed_data.get('aliases', []),
                'risk_level': seed_data.get('risk_level', 'unknown'),
                'ingredient_type': seed_data.get('ingredient_type'),
                'short_purpose': seed_data.get('short_purpose'),
                'short_risk_summary': seed_data.get('short_risk_summary'),
                'caution_groups': seed_data.get('caution_groups'),
                'processing_role': seed_data.get('processing_role'),
                'category': 'additive',  # Default category
                'created_at': datetime.utcnow().isoformat(),
                'updated_at': datetime.utcnow().isoformat(),
            }
            
            response = self.supabase.table('ingredients').insert(insert_data).execute()
            return response.data[0]['id'] if response.data else None
        except Exception as e:
            self.stats.errors.append(
                f"Create failed for {seed_data['canonical_name']}: {str(e)}"
            )
            return None
    
    def import_seed_file(self, seed_file: str) -> Tuple[int, int, int]:
        """
        Import intelligence data from JSON seed file.
        Returns (created, updated, skipped)
        """
        print(f"📖 Loading seed file: {seed_file}\n")
        
        if not os.path.exists(seed_file):
            print(f"❌ File not found: {seed_file}")
            return 0, 0, 0
        
        with open(seed_file, 'r', encoding='utf-8') as f:
            seed_data = json.load(f)
        
        print(f"🔍 Loaded {len(seed_data)} ingredients from seed\n")
        
        # Load cache for matching
        if not self.dry_run:
            self.load_ingredients_cache()
        
        # Process each ingredient
        for i, ingredient in enumerate(seed_data):
            print(f"[{i+1}/{len(seed_data)}] Processing: {ingredient['canonical_name']}...", end=' ')
            
            # Find matching ingredient
            matching = self.find_matching_ingredient(
                ingredient['canonical_name'],
                ingredient.get('aliases')
            )
            
            if matching:
                # Update existing ingredient
                if self.dry_run:
                    print("[DRY-RUN] Would update")
                    self.stats.ingredients_updated += 1
                else:
                    update_data = self.prepare_update_json(ingredient)
                    if self.update_ingredient_intelligence(matching['id'], update_data):
                        print(f"✓ Updated")
                        self.stats.ingredients_updated += 1
                    else:
                        print(f"✗ Update failed")
                        self.stats.ingredients_skipped += 1
            else:
                # Create new ingredient
                if self.dry_run:
                    print("[DRY-RUN] Would create")
                    self.stats.ingredients_new += 1
                else:
                    new_id = self.create_ingredient_from_seed(ingredient)
                    if new_id:
                        print(f"✓ Created (ID: {new_id[:8]}...)")
                        self.stats.ingredients_new += 1
                    else:
                        print(f"✗ Create failed")
                        self.stats.ingredients_skipped += 1
            
            # Rate limit to avoid overwhelming Supabase
            if not self.dry_run and (i + 1) % 10 == 0:
                time.sleep(0.5)
        
        return (
            self.stats.ingredients_new,
            self.stats.ingredients_updated,
            self.stats.ingredients_skipped
        )
    
    def print_summary(self):
        """Print import summary"""
        print("\n" + "="*60)
        print("IMPORT SUMMARY")
        print("="*60)
        print(f"✓ Created:  {self.stats.ingredients_new} new ingredients")
        print(f"✓ Updated:  {self.stats.ingredients_updated} existing ingredients")
        print(f"⊘ Skipped:  {self.stats.ingredients_skipped} ingredients")
        
        if self.stats.errors:
            print(f"\n⚠️  Errors ({len(self.stats.errors)}):")
            for error in self.stats.errors[:5]:  # Show first 5 errors
                print(f"   - {error}")
            if len(self.stats.errors) > 5:
                print(f"   ... and {len(self.stats.errors) - 5} more")
        
        if self.dry_run:
            print("\n[DRY-RUN MODE] No actual changes were made.")
            print("Run with --real to apply changes.")
        
        print("="*60)


def main():
    """CLI entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Import ingredient intelligence metadata from seed file'
    )
    parser.add_argument(
        '--seed',
        default='ingredient_intelligence_seed.json',
        help='Path to seed JSON file (default: ingredient_intelligence_seed.json)'
    )
    parser.add_argument(
        '--real',
        action='store_true',
        help='Actually apply changes (default: dry-run mode)'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Verbose output'
    )
    
    args = parser.parse_args()
    
    # Create importer
    dry_run = not args.real
    importer = IngredientIntelligenceImporter(dry_run=dry_run)
    
    # Run import
    try:
        importer.import_seed_file(args.seed)
        importer.print_summary()
    except Exception as e:
        print(f"❌ Import failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
