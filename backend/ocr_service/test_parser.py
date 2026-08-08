import sys
import types
# Provide a minimal dotenv stub for test-time import if python-dotenv is not installed.
if 'dotenv' not in sys.modules:
    sys.modules['dotenv'] = types.SimpleNamespace(load_dotenv=lambda: None)

from main import (
    _detect_nutrition_basis_candidate,
    _detect_product_state_candidate,
    _extract_explicit_ingredient_percentages,
    _parse_nutrition_section,
    parse_ingredient_text_to_items,
)


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
        "energy_kj: 808 kJ",
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
        "energy_kj": 808.0,
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


def test_kcal_only_does_not_fabricate_energy_kj():
    parsed = _parse_nutrition_section(["energy_kcal: 200"])

    assert parsed == {"energy_kcal": 200.0}
    assert "energy_kj" not in parsed


def test_explicit_basis_candidates_are_detected_conservatively():
    assert _detect_nutrition_basis_candidate("100 g için besin değerleri")[0] == "per100g"
    assert _detect_nutrition_basis_candidate("Her 100 ml'de enerji")[0] == "per100ml"
    assert _detect_nutrition_basis_candidate("Porsiyon başına değerler")[0] == "perServing"


def test_ambiguous_or_product_name_basis_remains_unknown():
    assert _detect_nutrition_basis_candidate("100 g ve 100 ml başına değerler")[0] == "unknown"
    assert _detect_nutrition_basis_candidate("Coca Cola Zero 100 g Paket")[0] == "unknown"


def test_explicit_product_state_is_detected_without_product_type_guessing():
    assert _detect_product_state_candidate("Hazırlandıktan sonra besin değerleri")[0] == "asPrepared"
    assert _detect_product_state_candidate("Satıldığı haliyle değerler")[0] == "asSold"
    assert _detect_product_state_candidate("Hazır çorba")[0] == "unknown"


def test_explicit_ingredient_percentages_are_preserved_not_estimated():
    candidates = _extract_explicit_ingredient_percentages(
        "İçindekiler: elma püresi %20, domates %65, nohut %40"
    )

    assert [(item.ingredient_text, item.percentage) for item in candidates] == [
        ("elma püresi", 20.0),
        ("domates", 65.0),
        ("nohut", 40.0),
    ]
    assert _extract_explicit_ingredient_percentages("elma püresi, domates, nohut") == []
    assert _extract_explicit_ingredient_percentages(
        "%20 daha fazla ürün. İçindekiler: elma püresi, su"
    ) == []


if __name__ == '__main__':
    test_complex_label()
    print('OK')
