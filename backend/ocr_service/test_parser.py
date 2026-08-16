import sys
import types
# Provide a minimal dotenv stub for test-time import if python-dotenv is not installed.
if 'dotenv' not in sys.modules:
    sys.modules['dotenv'] = types.SimpleNamespace(load_dotenv=lambda: None)

from main import (
    ProductLabelResponse,
    _build_product_label_evidence_candidates,
    _detect_nutrition_basis_candidate,
    _detect_product_state_candidate,
    _extract_basis_declaration_text,
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
    assert _detect_nutrition_basis_candidate("Coca Cola Zero 100 g Paket")[0] == "unknown"


def test_combined_100g_100ml_declaration_stays_ambiguous_never_split():
    # A SINGLE combined header never identifies which values belong to
    # which unit — this must stay "unknown", the same as any other
    # generic/ambiguous form, never "both100gAnd100ml" (that value is
    # reserved for two genuinely SEPARATE declarations — see below).
    assert _detect_nutrition_basis_candidate("100 g / ml")[0] == "unknown"
    assert _detect_nutrition_basis_candidate("100g/ml")[0] == "unknown"
    assert _detect_nutrition_basis_candidate("Besin değerleri 100 g / 100 ml")[0] == "unknown"


def test_two_separate_explicit_declarations_are_structured_not_collapsed():
    # OCR basis contract fix (Section 3/6): when the SAME text explicitly
    # states two SEPARATE, individually-unambiguous declarations (no
    # combined slash), the backend must not silently guess or collapse to
    # unknown — it hands back a structured signal so the frozen project
    # rule (select per_100g) can be applied by the CLI, not this backend.
    value, evidence = _detect_nutrition_basis_candidate(
        "100 g ve 100 ml başına değerler"
    )
    assert value == "both100gAnd100ml"
    assert evidence is None


def test_extract_basis_declaration_text_only_reads_the_dedicated_line():
    assert _extract_basis_declaration_text([
        "basis_declaration: 100 g'da",
        "energy_kj: 420",
    ]) == "100 g'da"
    assert _extract_basis_declaration_text(["basis_declaration: not_visible"]) == ""
    assert _extract_basis_declaration_text(["energy_kj: 420"]) == ""
    assert _extract_basis_declaration_text([]) == ""


def test_basis_is_recovered_from_isolated_nutrition_facts_not_ingredient_raw_text():
    # Section: OCR basis-evidence contract fix — the actual bug. The
    # nutrition table's basis header lives ONLY in the isolated
    # NUTRITION_FACTS `basis_declaration:` line; the ingredient-side
    # RAW_TEXT here deliberately contains no basis wording at all. This
    # must still recover per100g — proving basis is no longer sourced from
    # ingredient RAW_TEXT.
    ingredient_raw_text = "Şeker, buğday unu, bitkisel yağ, tuz"
    nutrition_lines = [
        "basis_declaration: 100 g için",
        "energy_kj: 420",
        "sugars: 4",
    ]

    evidence = _build_product_label_evidence_candidates(
        nutrition_lines, ingredient_raw_text
    )

    assert evidence is not None
    assert evidence.nutrition_basis == "per100g"
    assert evidence.nutrition_basis_text == "100 g için"


def test_unrelated_100g_in_ingredient_raw_text_cannot_manufacture_a_basis():
    # This is the EXACT regression the bug report described: the
    # ingredient/RAW_TEXT side mentions "100 g" for a reason that has
    # nothing to do with the nutrition table (e.g. a promotional claim),
    # and the NUTRITION_FACTS section never printed a basis header at all
    # (not_visible). The basis must remain unknown — never manufactured
    # from the unrelated ingredient-side mention.
    ingredient_raw_text = "Kutusunda 100 g hediye ürün içerir. İçindekiler: şeker, un."
    nutrition_lines = [
        "basis_declaration: not_visible",
        "energy_kj: 420",
    ]

    evidence = _build_product_label_evidence_candidates(
        nutrition_lines, ingredient_raw_text
    )

    assert evidence is None or evidence.nutrition_basis == "unknown"


def test_generic_combined_form_in_nutrition_facts_stays_ambiguous():
    # basis stays "unknown" for a combined declaration — and since nothing
    # else here is worth reporting either (no product-state wording, no
    # ingredient percentages), the function correctly returns None rather
    # than a fabricated non-null "unknown" candidate. Ambiguous either way.
    evidence = _build_product_label_evidence_candidates(
        ["basis_declaration: 100 g / ml", "energy_kj: 420"],
        "Şeker, un",
    )

    assert evidence is None or evidence.nutrition_basis == "unknown"


def test_two_separate_declarations_in_nutrition_facts_are_represented_safely():
    evidence = _build_product_label_evidence_candidates(
        ["basis_declaration: 100 g için ve 100 ml için", "energy_kj: 420"],
        "Şeker, un",
    )

    assert evidence is not None
    assert evidence.nutrition_basis == "both100gAnd100ml"


def test_product_label_response_never_exposes_the_full_raw_claude_response():
    # No field on the public response model may carry the raw Claude
    # completion text — only the already-structured
    # ingredients/nutrition/evidence_candidates contract.
    field_names = set(ProductLabelResponse.model_fields.keys())
    assert field_names == {
        "ingredients",
        "nutrition",
        "extraction_status",
        "extraction_schema_version",
        "evidence_candidates",
    }
    for suspicious in ("raw_content", "raw_response", "claude_response", "full_text"):
        assert suspicious not in field_names


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
