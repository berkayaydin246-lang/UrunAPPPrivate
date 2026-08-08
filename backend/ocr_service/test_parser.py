import sys
import types
# Provide a minimal dotenv stub for test-time import if python-dotenv is not installed.
if 'dotenv' not in sys.modules:
    sys.modules['dotenv'] = types.SimpleNamespace(load_dotenv=lambda: None)

from main import _parse_nutrition_section, parse_ingredient_text_to_items


def test_complex_label():
    input_text = (
        "Şeker, bitkisel yağlar (ayçiçek, palm), emülgatör (yağ asitlerinin mono- ve digliseritleri), "
        "antioksidan (tokoferolce zengin ekstrakt), peyniraltı suyu tozu (süt ürünü), "
        "patlamış pirinç (%12) (pirinç unu %44), buğday unu, arpa malt ekstraktı, tuz, "
        "emülgatör (lesitinler), aroma vericiler, kabartıcı (sodyum karbonatlar)"
    )

    expected = [
        'şeker',
        'bitkisel yağlar',
        'ayçiçek yağı',
        'palm yağı',
        'emülgatör',
        'mono ve digliseritler',
        'antioksidan',
        'tokoferolce zengin ekstrakt',
        'peynir altı suyu tozu',
        'süt ürünü',
        'patlamış pirinç',
        'pirinç unu',
        'buğday unu',
        'malt ekstraktı',
        'tuz',
        'lesitin',
        'aroma vericiler',
        'kabartıcı',
        'sodyum karbonat',
    ]

    parsed = parse_ingredient_text_to_items(input_text)
    print('PARSED:', parsed)
    assert all(e in parsed for e in expected)
    # ensure unwanted fragments absent
    for bad in ['palm', '(%12)', '%12', '%44', '7 yağı', 'pirinç unu ()']:
        assert not any(bad in p for p in parsed)


def test_nutrition_section_uses_canonical_numeric_fields():
    parsed = _parse_nutrition_section([
        "energy_kcal: 193 kcal",
        "fat: 3,4 g",
        "saturated_fat: 1.2",
        "carbohydrates: 27",
        "sugars: 5.5",
        "fiber: not_visible",
        "proteins: 8",
        "salt: 0.7",
        "sodium: 0.28",
        "serving_size: 30 g",
    ])

    assert parsed == {
        "energy_kcal": 193.0,
        "fat": 3.4,
        "saturated_fat": 1.2,
        "carbohydrates": 27.0,
        "sugars": 5.5,
        "proteins": 8.0,
        "salt": 0.7,
        "sodium": 0.28,
        "serving_size": "30 g",
    }


def test_nutrition_section_rejects_non_finite_and_negative_values():
    parsed = _parse_nutrition_section([
        "energy_kcal: NaN",
        "fat: inf",
        "sugars: -1",
        "salt: not_visible",
    ])

    assert parsed == {}


if __name__ == '__main__':
    test_complex_label()
    print('OK')
