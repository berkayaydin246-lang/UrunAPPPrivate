"""
OFF Product Importer + Scorer
Fetches products from Open Food Facts and scores them using deterministic rules
"""

import json
import re
import requests
import time
from typing import List, Dict, Optional
from dataclasses import dataclass

# Open Food Facts requires a clear User-Agent for automated requests.
# Replace the contact email with your real project/support email before production use.
OFF_HEADERS = {
    "User-Agent": "FoodAnalyzerApp/1.0 (contact: your-email@example.com)",
    "Accept": "application/json",
}

OFF_TIMEOUT_SECONDS = 20



@dataclass
class ScoringResult:
    """Scoring result matching our schema"""
    score_label: str  # iyi_secim, orta, dikkatli_tuket, sik_tuketme
    summary: str
    warning_text: Optional[str]
    positive_points: List[str]
    negative_points: List[str]
    consumption_advice: str
    suitable_for_children: bool


class ProductScorer:
    """
    Deterministic rule-based scoring engine
    Maps to our product_reviews schema
    """
    
    def __init__(self):
        # High-risk E codes
        self.high_risk_e_codes = [
            'e102', 'e104', 'e110', 'e122', 'e124', 'e129',  # Artificial colors
            'e249', 'e250', 'e251', 'e252',  # Nitrites/nitrates
            'e320', 'e321',  # BHA/BHT
            'e952',  # Cyclamate
        ]
        
        # Medium-risk E codes
        self.medium_risk_e_codes = [
            'e150c', 'e150d',  # Ammonia caramel
            'e338', 'e339', 'e450', 'e451', 'e452',  # Phosphates
            'e621', 'e627', 'e631',  # MSG and flavor enhancers
        ]
        
        # Processed sugars
        self.processed_sugars = [
            'glikoz şurupu', 'glucose syrup',
            'fruktoz şurupu', 'fructose syrup',
            'mısır şurupu', 'corn syrup',
            'yüksek fruktozlu', 'high fructose'
        ]
    
    def normalize_ingredient(self, text: str) -> str:
        """Normalize ingredient text"""
        if not text:
            return ""
        
        # Turkish char mapping
        tr_map = {
            'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's',
            'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u',
            'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'
        }
        
        normalized = text.lower()
        for tr_char, en_char in tr_map.items():
            normalized = normalized.replace(tr_char, en_char)
        
        return normalized.strip()
    
    def parse_ingredients(self, ingredients_text: str) -> List[str]:
        """
        Parse ingredients text into list
        Example: "Çilek, şeker, sitrik asit (E330)" -> ["çilek", "şeker", "sitrik asit", "e330"]
        """
        if not ingredients_text:
            return []
        
        # Split by comma, semicolon, or "ve"/"and"
        ingredients = re.split(r'[,;]|\bve\b|\band\b', ingredients_text)
        
        parsed = []
        for ing in ingredients:
            ing = ing.strip()
            if not ing:
                continue
            
            # Extract E codes from parentheses
            e_codes = re.findall(r'\(?(E\d+[a-z]*)\)?', ing, re.IGNORECASE)
            
            # Clean parentheses
            clean_ing = re.sub(r'\([^)]*\)', '', ing).strip()
            
            if clean_ing:
                parsed.append(self.normalize_ingredient(clean_ing))
            
            # Add E codes separately
            for e_code in e_codes:
                parsed.append(self.normalize_ingredient(e_code))
        
        return parsed
    
    def score_product(self, ingredients_list: List[str]) -> ScoringResult:
        """
        Score product based on deterministic rules
        Returns ScoringResult matching our schema
        """
        
        score = 100
        positive = []
        negative = []
        warning = None
        
        ingredient_count = len(ingredients_list)
        
        # 1. Ingredient count analysis
        if ingredient_count <= 5:
            score += 15
            positive.append("Çok az sayıda içerik (basit formül)")
        elif ingredient_count <= 10:
            score += 5
            positive.append("Az sayıda içerik")
        elif ingredient_count > 20:
            score -= 15
            negative.append("Çok fazla içerik (yüksek işlenmiş)")
        
        # 2. E-code analysis
        e_codes_found = []
        high_risk_found = []
        medium_risk_found = []
        
        for ing in ingredients_list:
            if ing.startswith('e') and ing[1:].replace('a', '').replace('b', '').replace('c', '').replace('d', '').isdigit():
                e_codes_found.append(ing)
                
                if ing in self.high_risk_e_codes:
                    high_risk_found.append(ing.upper())
                    score -= 25
                elif ing in self.medium_risk_e_codes:
                    medium_risk_found.append(ing.upper())
                    score -= 10
        
        # E-code summary
        if len(e_codes_found) == 0:
            score += 20
            positive.append("Hiç katkı maddesi yok")
        elif len(e_codes_found) <= 3:
            score += 5
            positive.append("Az katkı maddesi")
        elif len(e_codes_found) > 7:
            score -= 15
            negative.append(f"{len(e_codes_found)} katkı maddesi var")
        
        # High-risk warnings
        if high_risk_found:
            negative.append(f"Yüksek riskli katkılar: {', '.join(high_risk_found)}")
            warning = f"Bu ürün yüksek riskli katkı maddeleri içermektedir: {', '.join(high_risk_found)}"
        
        if medium_risk_found:
            negative.append(f"Orta riskli katkılar: {', '.join(medium_risk_found)}")
        
        # 3. Processed sugar check
        has_processed_sugar = False
        for sugar_term in self.processed_sugars:
            if any(sugar_term in ing for ing in ingredients_list):
                has_processed_sugar = True
                break
        
        if has_processed_sugar:
            score -= 15
            negative.append("İşlenmiş şeker içeriyor (glikoz/fruktoz şurubu)")
        
        # 4. Nitrite/nitrate check (E249-E252)
        nitrites = [e for e in e_codes_found if e in ['e249', 'e250', 'e251', 'e252']]
        if nitrites:
            score -= 30
            negative.append(f"Nitrit/nitrat içeriyor ({', '.join([e.upper() for e in nitrites])})")
            if not warning:
                warning = "Bu ürün nitrit/nitrat içermektedir. Sık tüketim önerilmez."
        
        # 5. Palm oil check
        if any('palm' in ing or 'palmiye' in ing for ing in ingredients_list):
            score -= 10
            negative.append("Palmiye yağı içeriyor")
        
        # Clamp score
        score = max(0, min(100, score))
        
        # Determine label
        if score >= 75:
            label = 'iyi_secim'
            advice = "Güvenle tüketebilirsiniz."
        elif score >= 50:
            label = 'orta'
            advice = "Dengeli beslenme kapsamında tüketilebilir."
        elif score >= 25:
            label = 'dikkatli_tuket'
            advice = "Sık tüketim önerilmez. Alternatifler tercih edilebilir."
        else:
            label = 'sik_tuketme'
            advice = "Mümkün olduğunca az tüketin veya alternatif arayın."
        
        # Child suitability
        suitable_for_children = True
        if high_risk_found or nitrites or score < 50:
            suitable_for_children = False
            if not warning:
                warning = "Çocuklar için önerilmez."
        
        # Summary
        summary = f"Bu ürün {ingredient_count} içerik içermektedir"
        if e_codes_found:
            summary += f" ({len(e_codes_found)} katkı maddesi)"
        summary += "."
        
        return ScoringResult(
            score_label=label,
            summary=summary,
            warning_text=warning,
            positive_points=positive if positive else None,
            negative_points=negative if negative else None,
            consumption_advice=advice,
            suitable_for_children=suitable_for_children
        )


class OFFProductImporter:
    """Fetch products from Open Food Facts Turkey"""
    
    def __init__(self):
        self.base_url = "https://world.openfoodfacts.org/cgi/search.pl"
        self.scorer = ProductScorer()
        self.products = []
    
    def normalize_name(self, name: str) -> str:
        """Normalize product name"""
        if not name:
            return ""
        
        tr_map = {
            'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's',
            'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u',
            'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'
        }
        
        normalized = name.lower()
        for tr_char, en_char in tr_map.items():
            normalized = normalized.replace(tr_char, en_char)
        
        return re.sub(r'[^a-z0-9\s]', '', normalized).strip()
    
    def extract_product(self, raw_product: Dict) -> Optional[Dict]:
        """
        Extract and transform product from OFF API
        Returns dict matching our products schema + scoring
        """
        
        try:
            barcode = raw_product.get('code')
            if not barcode:
                return None
            
            # Product name - prefer Turkish
            name = (
                raw_product.get('product_name_tr') or
                raw_product.get('product_name') or
                'Bilinmeyen Ürün'
            )
            
            normalized_name = self.normalize_name(name)
            
            # Brand
            brand = raw_product.get('brands', '')
            
            # Ingredients text - prefer Turkish
            ingredients_text = (
                raw_product.get('ingredients_text_tr') or
                raw_product.get('ingredients_text_en') or
                raw_product.get('ingredients_text') or
                ""
            )
            
            # Parse ingredients
            ingredients_list = self.scorer.parse_ingredients(ingredients_text)
            
            # Score product
            scoring = self.scorer.score_product(ingredients_list)
            
            # Image
            image_url = raw_product.get('image_url', '')
            
            # Categories
            categories = raw_product.get('categories', '')
            
            # Nutrition (raw from OFF)
            nutrition_text = json.dumps(raw_product.get('nutriments', {}))
            
            # Quality assessment
            verification_status = 'imported'
            if not ingredients_text or len(ingredients_text) < 10:
                verification_status = 'pending'
            
            return {
                'product': {
                    'barcode': barcode,
                    'name': name,
                    'normalized_name': normalized_name,
                    'brand': brand if brand else None,
                    'category_id': None,  # Will be mapped later
                    'image_url': image_url if image_url else None,
                    'ingredients_text': ingredients_text,
                    'nutrition_text': nutrition_text if nutrition_text != '{}' else None,
                    'source': 'Open Food Facts',
                    'source_url': f"https://world.openfoodfacts.org/product/{barcode}",
                    'verification_status': verification_status
                },
                'review': {
                    'score_label': scoring.score_label,
                    'summary': scoring.summary,
                    'warning_text': scoring.warning_text,
                    'positive_points': scoring.positive_points,
                    'negative_points': scoring.negative_points,
                    'consumption_advice': scoring.consumption_advice,
                    'suitable_for_children': scoring.suitable_for_children
                },
                'ingredients_list': ingredients_list,
                'categories': categories
            }
            
        except Exception as e:
            print(f"⚠️  Error extracting product: {e}")
            return None
    
    def fetch_turkey_products(
        self,
        max_pages: int = 10,
        page_size: int = 100,
        output_file: str = "off_products_scored.json"
    ):
        """Fetch products from OFF Turkey"""
        
        print(f"🇹🇷 Fetching Turkey products from Open Food Facts...")
        print(f"   Max pages: {max_pages}")
        print(f"   Page size: {page_size}\n")
        
        for page in range(1, max_pages + 1):
            params = {
                "action": "process",
                "tagtype_0": "countries",
                "tag_contains_0": "contains",
                "tag_0": "turkey",
                "json": 1,
                "page": page,
                "page_size": page_size,
                "fields": "code,product_name,product_name_tr,brands,categories,"
                         "ingredients_text,ingredients_text_tr,ingredients_text_en,"
                         "image_url,nutriments"
            }
            
            try:
                response = requests.get(self.base_url, params=params, timeout=15)
                response.raise_for_status()
                data = response.json()
                
                products_in_page = data.get('products', [])
                
                if not products_in_page:
                    print(f"✓ Page {page}: No more products, stopping.")
                    break
                
                for raw_product in products_in_page:
                    extracted = self.extract_product(raw_product)
                    if extracted:
                        self.products.append(extracted)
                
                print(f"✓ Page {page}: {len(products_in_page)} products fetched "
                      f"(total: {len(self.products)})")
                
                time.sleep(0.5)  # Rate limiting
                
            except requests.exceptions.RequestException as e:
                print(f"✗ Page {page}: HTTP error - {e}")
                continue
            except json.JSONDecodeError as e:
                print(f"✗ Page {page}: JSON parse error - {e}")
                continue
        
        print(f"\n🎉 Fetched {len(self.products)} products!")
        
        # Save to JSON
        print(f"💾 Saving to {output_file}...")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(self.products, f, ensure_ascii=False, indent=2)
        
        # Stats
        self.print_stats()
    
    def print_stats(self):
        """Print statistics"""
        total = len(self.products)
        
        score_dist = {}
        for p in self.products:
            label = p['review']['score_label']
            score_dist[label] = score_dist.get(label, 0) + 1
        
        pending = len([p for p in self.products 
                           if p['product']['verification_status'] == 'pending'])
        
        with_warning = len([p for p in self.products 
                           if p['review']['warning_text']])
        
        child_safe = len([p for p in self.products 
                         if p['review']['suitable_for_children']])
        
        print(f"\n📊 Statistics:")
        print(f"   Total: {total}")
        print(f"\n   Score distribution:")
        for label in ['iyi_secim', 'orta', 'dikkatli_tuket', 'sik_tuketme']:
            count = score_dist.get(label, 0)
            pct = (count / total * 100) if total > 0 else 0
            print(f"     {label}: {count} ({pct:.1f}%)")
        
        print(f"\n   Needs review: {pending}")
        print(f"   With warnings: {with_warning}")
        print(f"   Child-safe: {child_safe}")


def main():
    """Main function"""
    import sys
    
    max_pages = 10
    if '--pages' in sys.argv:
        idx = sys.argv.index('--pages')
        if idx + 1 < len(sys.argv):
            max_pages = int(sys.argv[idx + 1])
    
    importer = OFFProductImporter()
    importer.fetch_turkey_products(
        max_pages=max_pages,
        page_size=100,
        output_file="off_products_scored.json"
    )
    
    print("\n✅ Done! Next step:")
    print("   python upload_products.py --dry-run")
    print("\n💡 To fetch more pages, use: python fetch_off_products.py --pages 50\n")


if __name__ == "__main__":
    main()