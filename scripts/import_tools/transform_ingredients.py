"""
Transform ingredients_seed.json to match our actual schema
Maps old structure to new ingredients table structure
"""

import json
import re
from typing import Dict, List, Optional


def normalize_name(name: str) -> str:
    """
    Normalize ingredient name for matching
    - lowercase
    - remove special chars
    - trim whitespace
    """
    if not name:
        return ""
    
    # Turkish character mapping
    tr_map = {
        'ı': 'i', 'İ': 'i', 'ş': 's', 'Ş': 's',
        'ğ': 'g', 'Ğ': 'g', 'ü': 'u', 'Ü': 'u',
        'ö': 'o', 'Ö': 'o', 'ç': 'c', 'Ç': 'c'
    }
    
    normalized = name.lower()
    for tr_char, en_char in tr_map.items():
        normalized = normalized.replace(tr_char, en_char)
    
    # Remove special chars except spaces and hyphens
    normalized = re.sub(r'[^a-z0-9\s-]', '', normalized)
    
    # Collapse multiple spaces
    normalized = re.sub(r'\s+', ' ', normalized).strip()
    
    return normalized


def map_category(old_category: str) -> str:
    """Map old category to additive_group"""
    category_map = {
        'renklendirici': 'Renklendirici',
        'koruyucu': 'Koruyucu',
        'antioksidan': 'Antioksidan',
        'asitlik_düzenleyici': 'Asitlik Düzenleyici',
        'kıvam_arttırıcı': 'Kıvam Arttırıcı',
        'tatlandırıcı': 'Tatlandırıcı',
        'emülgatör': 'Emülgatör',
        'lezzet_arttırıcı': 'Lezzet Arttırıcı',
        'kabartıcı': 'Kabartma Maddesi',
        'nem_tutucu': 'Nem Tutucu',
        'sertleştirici': 'Sertleştirici',
        'köpük_önleyici': 'Köpük Önleyici',
        'şişirici': 'Dolgu Maddesi',
        'temel_malzeme': 'Temel Malzeme',
        'yağ': 'Yağ',
    }
    
    return category_map.get(old_category, old_category)


def transform_ingredient(old_ing: Dict) -> Dict:
    """
    Transform old ingredient structure to new schema
    
    Old schema:
    - e_number, name_tr, name_en, category, description, risk_level, health_info
    
    New schema:
    - name, normalized_name, alternative_names, aliases, common_names, english_names
    - e_code, category, additive_group, risk_level
    - short_description, long_description, child_warning
    - source_references, source_url
    """
    
    name_tr = old_ing.get('name_tr', '')
    name_en = old_ing.get('name_en', '')
    e_number = old_ing.get('e_number')
    
    # Primary name is Turkish
    name = name_tr
    normalized = normalize_name(name_tr)
    
    # Alternative names and aliases
    alternative_names = []
    aliases = []
    english_names = []
    
    if name_en and name_en != name_tr:
        english_names.append(name_en)
        alternative_names.append(name_en)
    
    if e_number:
        aliases.append(e_number.upper())
        aliases.append(e_number.lower())
    
    # Common names (Turkish variations)
    common_names = [name_tr]
    
    # Category mapping
    old_category = old_ing.get('category', '')
    additive_group = map_category(old_category)
    
    # Description handling
    description = old_ing.get('description', '')
    health_info = old_ing.get('health_info', '')
    
    short_description = description[:200] if description else ''
    
    long_description = f"{description}\n\n{health_info}" if health_info else description
    
    # Risk level mapping
    risk_level = old_ing.get('risk_level', 'low')
    
    # Child warning - high risk items should warn parents
    child_warning = None
    if risk_level == 'high':
        if 'çocuk' in health_info.lower() or 'hiperaktiv' in health_info.lower():
            child_warning = "Çocuklar için önerilmez"
    
    # Category - using Turkish category for now
    category = old_category if old_category != 'temel_malzeme' else None
    
    return {
        'name': name,
        'normalized_name': normalized,
        'alternative_names': alternative_names if alternative_names else None,
        'aliases': aliases if aliases else None,
        'common_names': common_names if common_names else None,
        'english_names': english_names if english_names else None,
        'e_code': e_number.upper() if e_number else None,
        'category': category,
        'additive_group': additive_group if additive_group != 'Temel Malzeme' else None,
        'risk_level': risk_level,
        'short_description': short_description,
        'long_description': long_description,
        'child_warning': child_warning,
        'source_references': None,
        'source_url': None
    }


def transform_all_ingredients(input_file: str, output_file: str):
    """Transform all ingredients from old to new schema"""
    
    print(f"📖 Reading {input_file}...")
    with open(input_file, 'r', encoding='utf-8') as f:
        old_ingredients = json.load(f)
    
    print(f"🔄 Transforming {len(old_ingredients)} ingredients...")
    
    new_ingredients = []
    for old_ing in old_ingredients:
        try:
            new_ing = transform_ingredient(old_ing)
            new_ingredients.append(new_ing)
        except Exception as e:
            print(f"⚠️  Error transforming {old_ing.get('name_tr')}: {e}")
    
    print(f"💾 Writing {len(new_ingredients)} ingredients to {output_file}...")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(new_ingredients, f, ensure_ascii=False, indent=2)
    
    print(f"✅ Done! Transformed {len(new_ingredients)} ingredients")
    
    # Stats
    with_e_code = len([i for i in new_ingredients if i['e_code']])
    high_risk = len([i for i in new_ingredients if i['risk_level'] == 'high'])
    with_child_warning = len([i for i in new_ingredients if i['child_warning']])
    
    print(f"\n📊 Statistics:")
    print(f"  Total: {len(new_ingredients)}")
    print(f"  With E-code: {with_e_code}")
    print(f"  High risk: {high_risk}")
    print(f"  Child warnings: {with_child_warning}")


if __name__ == "__main__":
    transform_all_ingredients(
        "ingredients_seed.json",
        "ingredients_transformed.json"
    )
