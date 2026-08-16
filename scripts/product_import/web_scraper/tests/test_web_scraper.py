#!/usr/bin/env python3
"""Lightweight unit tests for the web scraper pipeline (stdlib unittest).

Run:
    python3 -m unittest discover -s scripts/product_import/web_scraper/tests
or:
    python3 scripts/product_import/web_scraper/tests/test_web_scraper.py
"""
from __future__ import annotations

import os
import re
import sys
import unittest
from unittest.mock import MagicMock, patch

# Make `scripts/product_import` importable so `web_scraper` + `common` resolve.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(_HERE)))

import fix_migros_product_images_only as migros_image_fix  # noqa: E402
from scoring_lifecycle_bridge import run_product_scoring_lifecycle  # noqa: E402
from web_scraper import (  # noqa: E402
    extractors,
    image_scoring,
    ingredient_parser,
    nutrition_parser,
    runner,
    source_adapters,
    source_config,
)
from web_scraper.base import FetchResult  # noqa: E402
from web_scraper.source_adapters.migros_adapter import (  # noqa: E402
    MigrosAdapter,
    _category_slug,
    _extract_dynamic_brands,
    _render_template,
)


class ScoringLifecycleBridgeTest(unittest.TestCase):
    @patch("scoring_lifecycle_bridge.subprocess.run")
    def test_bridge_passes_only_identity_and_trigger_to_dart(self, run_mock):
        run_mock.return_value = MagicMock(
            returncode=0,
            stdout="final_score_ready=true\naudit_status=inserted\n",
            stderr="",
        )
        environment = {
            "SUPABASE_URL": "https://abcdefghijklmnopqrst.supabase.co",
            "SUPABASE_SERVICE_ROLE_KEY": "never-print-this-secret",
        }

        with patch.dict(os.environ, environment, clear=True):
            result = run_product_scoring_lifecycle(
                "16dc5dac-4f37-4072-8e98-c2556ff76adf",
                "staging_approval",
            )

        self.assertTrue(result.succeeded)
        command = run_mock.call_args.args[0]
        self.assertIn("tool/product_scoring_lifecycle.dart", command)
        self.assertIn("staging_approval", command)
        self.assertNotIn(environment["SUPABASE_SERVICE_ROLE_KEY"], command)

    @patch("scoring_lifecycle_bridge.subprocess.run")
    def test_bridge_fails_closed_without_service_environment(self, run_mock):
        with patch.dict(os.environ, {}, clear=True):
            result = run_product_scoring_lifecycle(
                "16dc5dac-4f37-4072-8e98-c2556ff76adf",
                "catalogue_change",
            )

        self.assertFalse(result.succeeded)
        self.assertEqual(result.error, "missing_scoring_lifecycle_environment")
        run_mock.assert_not_called()


class NutritionParserTest(unittest.TestCase):
    def test_turkish_per_100g_table(self):
        text = (
            "Besin Değerleri (100 g)\n"
            "Enerji 2000 kJ / 478 kcal\n"
            "Yağ 25,5 g\n"
            "Doymuş yağ 12 g\n"
            "Karbonhidrat 60 g\n"
            "Şekerler 30 g\n"
            "Lif 2 g\n"
            "Protein 6,5 g\n"
            "Tuz 1,2 g\n"
        )
        data, warnings = nutrition_parser.parse_nutrition(text)
        self.assertEqual(data["energy_kcal"], 478)
        self.assertEqual(data["fat"], 25.5)
        self.assertEqual(data["saturated_fat"], 12)
        self.assertEqual(data["carbohydrates"], 60)
        self.assertEqual(data["sugars"], 30)
        self.assertEqual(data["fiber"], 2)
        self.assertEqual(data["proteins"], 6.5)
        self.assertEqual(data["salt"], 1.2)
        self.assertEqual(warnings, [])

    def test_saturated_not_swallowed_by_fat(self):
        text = "100 g\nYağ 10 g\nDoymuş yağ 3 g\n"
        data, _ = nutrition_parser.parse_nutrition(text)
        self.assertEqual(data["fat"], 10)
        self.assertEqual(data["saturated_fat"], 3)

    def test_salt_derived_from_sodium_mg(self):
        text = "100 ml\nSodyum 400 mg\n"
        data, _ = nutrition_parser.parse_nutrition(text)
        self.assertEqual(data["sodium"], 0.4)
        self.assertEqual(data["salt"], 1.0)  # 0.4 * 2.5

    def test_per_serving_not_normalized(self):
        text = "Porsiyon başına (1 porsiyon)\nEnerji 200 kcal\nYağ 5 g"
        data, warnings = nutrition_parser.parse_nutrition(text)
        self.assertEqual(data, {})
        self.assertIn("nutrition_per_serving_not_normalized", warnings)

    def test_energy_only_kj_converts(self):
        text = "100 g\nEnerji 418 kJ\n"
        data, _ = nutrition_parser.parse_nutrition(text)
        self.assertAlmostEqual(data["energy_kcal"], 99.9, places=1)


class IngredientParserTest(unittest.TestCase):
    def test_strips_label_and_whitespace(self):
        raw = "İçindekiler:   Buğday   unu,  şeker,\n bitkisel yağ  "
        cleaned = ingredient_parser.clean_ingredients(raw)
        self.assertEqual(cleaned, "Buğday unu, şeker, bitkisel yağ")

    def test_trims_marketing_tail(self):
        raw = (
            "İçindekiler: Süt, kakao, fındık. "
            "Saklama koşulları: serin ve kuru yerde saklayınız."
        )
        cleaned = ingredient_parser.clean_ingredients(raw)
        self.assertEqual(cleaned, "Süt, kakao, fındık")

    def test_returns_none_for_empty(self):
        self.assertIsNone(ingredient_parser.clean_ingredients(""))
        self.assertIsNone(ingredient_parser.clean_ingredients("  "))

    def test_keeps_turkish_characters(self):
        cleaned = ingredient_parser.clean_ingredients("İçerik: çikolata, fındık ezmesi")
        self.assertIn("çikolata", cleaned)
        self.assertIn("fındık", cleaned)


class ImageScoringTest(unittest.TestCase):
    def test_prefers_schema_packshot_over_banner(self):
        cands = [
            image_scoring.ImageCandidate(
                url="https://cdn.example.com/banner/raf-kampanya.jpg", in_gallery=True
            ),
            image_scoring.ImageCandidate(
                url="https://cdn.example.com/product/urun-front-800x800.jpg",
                in_schema=True,
            ),
        ]
        best, scored = image_scoring.pick_best_image(cands, name="Cips", brand="Lay's")
        self.assertIsNotNone(best)
        self.assertIn("product", best.url)
        self.assertGreater(scored[0].score, scored[1].score)

    def test_tiny_image_penalized(self):
        cand = image_scoring.ImageCandidate(
            url="https://cdn.example.com/thumb/icon-50x50.png"
        )
        scored = image_scoring.score_image(cand)
        self.assertLess(scored.score, 0)

    def test_all_bad_returns_none_best(self):
        cands = [
            image_scoring.ImageCandidate(url="https://x/logo.svg"),
            image_scoring.ImageCandidate(url="https://x/category-thumb.gif"),
        ]
        best, _ = image_scoring.pick_best_image(cands)
        self.assertIsNone(best)


class DedupeAndMergeTest(unittest.TestCase):
    def test_dedupe_key_prefers_barcode(self):
        c = {"barcode": "8690000000001", "source_url": "https://x/p/1", "name": "X"}
        self.assertEqual(runner.dedupe_key(c), ("barcode", "8690000000001"))

    def test_dedupe_key_falls_back_to_source_url(self):
        c = {"barcode": "", "source_url": "https://x/p/1", "name": "X"}
        self.assertEqual(runner.dedupe_key(c), ("source_url", "https://x/p/1"))

    def test_dedupe_key_name_brand_when_no_barcode_or_url(self):
        c = {"name": "Çikolatalı Gofret", "brand": "Eti"}
        kind, n, b = runner.dedupe_key(c)
        self.assertEqual(kind, "name_brand")
        self.assertEqual(n, "cikolataligofret")
        self.assertEqual(b, "eti")

    def test_merge_fills_missing_and_recomputes_quality(self):
        existing = {
            "name": "Gofret", "brand": None, "ingredients_text": None,
            "nutrition_json": None, "image_front_url": None,
            "category_suggestion": None, "barcode": None,
            "source": "web_scraper:retailer", "admin_notes": "checked",
            "raw_source_payload": {"image_best_score": 0},
        }
        incoming = {
            "brand": "Eti",
            "ingredients_text": "Buğday unu, şeker, bitkisel yağ, kakao",
            "nutrition_json": {"energy_kcal": 480, "fat": 25},
            "image_front_url": "https://x/product/front-800x800.jpg",
            "image_source": "web_scraper:retailer",
            "category_suggestion": "kek",
            "brand_source": "web_scraper:retailer",
            "source": "web_scraper:retailer",
            "raw_source_payload": {"image_best_score": 50},
        }
        merged = runner.merge_fill_missing(existing, incoming)
        self.assertEqual(merged["brand"], "Eti")
        self.assertEqual(merged["image_front_url"], "https://x/product/front-800x800.jpg")
        self.assertEqual(merged["image_url"], "https://x/product/front-800x800.jpg")
        self.assertEqual(merged["admin_notes"], "checked")  # preserved
        self.assertNotIn("ingredients", merged["missing_fields"])
        self.assertGreater(merged["quality_score"], 0)

    def test_merge_keeps_better_existing_image(self):
        existing = {
            "name": "X", "image_front_url": "https://x/product/good-800x800.jpg",
            "raw_source_payload": {"image_best_score": 60}, "source": "web_scraper:a",
        }
        incoming = {
            "name": "X", "image_front_url": "https://x/thumb/bad-50x50.jpg",
            "raw_source_payload": {"image_best_score": 5}, "source": "web_scraper:a",
        }
        merged = runner.merge_fill_missing(existing, incoming)
        self.assertEqual(merged["image_front_url"], "https://x/product/good-800x800.jpg")


class QualityScoringWithoutBarcodeTest(unittest.TestCase):
    def test_full_data_without_barcode_is_usable(self):
        candidate = {
            "name": "Çikolatalı Gofret",
            "brand": "Eti",
            "image_front_url": "https://x/product/front.jpg",
            "ingredients_text": "Buğday unu, şeker, bitkisel yağ, kakao, fındık",
            "nutrition_json": {"energy_kcal": 500, "fat": 25, "sugars": 30},
            "category_suggestion": "gofret",
            # no barcode
        }
        score, missing, status = runner.evaluate_quality_web(candidate)
        # name+brand+image+ingredients+nutrition+category = 100 even w/o barcode
        self.assertGreaterEqual(score, 80)
        self.assertEqual(status, "pending")
        self.assertIn("barcode", missing)

    def test_barcode_is_bonus_only(self):
        base = {
            "name": "Gofret", "brand": "Eti",
            "image_front_url": "https://x/p.jpg",
            "ingredients_text": "Buğday unu, şeker, bitkisel yağ, kakao",
            "nutrition_json": {"energy_kcal": 500},
            "category_suggestion": "gofret",
        }
        without = runner.evaluate_quality_web(base)[0]
        with_barcode = runner.evaluate_quality_web({**base, "barcode": "8690000000001"})[0]
        self.assertGreaterEqual(with_barcode, without)
        self.assertLessEqual(with_barcode, 100)

    def test_sparse_candidate_is_insufficient(self):
        score, _missing, status = runner.evaluate_quality_web({"name": "X"})
        self.assertLess(score, 50)
        self.assertEqual(status, "insufficient_data")


def _nutrition_from_html(html: str):
    soup = extractors.make_soup(html)
    nutri = extractors.extract_nutrition(soup)
    return nutrition_parser.build_nutrition(
        nutri["pairs"], basis_text=nutri["basis_text"], fallback_text=nutri["fallback_text"]
    )


class GenericNutritionExtractionTest(unittest.TestCase):
    def test_real_table_style(self):
        html = """
        <table>
          <tr><th>Besin Değeri</th><th>100 g / ml</th></tr>
          <tr><td>Enerji (kcal)</td><td>199.0</td></tr>
          <tr><td>Enerji (kJ)</td><td>827.0</td></tr>
          <tr><td>Yağ (g)</td><td>15.0</td></tr>
          <tr><td>Doymuş yağ (g)</td><td>3.0</td></tr>
          <tr><td>Karbonhidrat (g)</td><td>5.0</td></tr>
          <tr><td>Şeker (g)</td><td>0.0</td></tr>
          <tr><td>Protein (g)</td><td>11.0</td></tr>
          <tr><td>Tuz (g)</td><td>1.8</td></tr>
        </table>
        """
        data, _ = _nutrition_from_html(html)
        self.assertEqual(data["energy_kcal"], 199.0)
        self.assertEqual(data["energy_kj"], 827.0)
        self.assertEqual(data["fat"], 15.0)
        self.assertEqual(data["saturated_fat"], 3.0)
        self.assertEqual(data["carbohydrates"], 5.0)
        self.assertEqual(data["sugars"], 0.0)
        self.assertEqual(data["proteins"], 11.0)
        self.assertEqual(data["salt"], 1.8)

    def test_div_row_style(self):
        html = """
        <div>
          <div>Besin Değerleri</div>
          <div><span>Yağ (g)</span><span>15,0</span></div>
          <div><span>Doymuş yağ (g)</span><span>3,0</span></div>
        </div>
        """
        data, _ = _nutrition_from_html(html)
        self.assertEqual(data["fat"], 15.0)
        self.assertEqual(data["saturated_fat"], 3.0)

    def test_basis_per_100_generic_from_table_header(self):
        # "100 g / ml" genuinely names BOTH units without identifying which
        # values belong to which — basis remediation Section B: this must
        # classify as per_100_generic, never guessed as either single unit,
        # but still proceeds with value extraction (no unknown warning —
        # we DO know it's some per-100 basis, just not which exact unit).
        html = """
        <table>
          <tr><th>Besin Değeri</th><td class="value">100 g / ml</td></tr>
          <tr><td>Enerji (kcal)</td><td>248.0</td></tr>
          <tr><td>Yağ (g)</td><td>20.0</td></tr>
          <tr><td>Protein (g)</td><td>11.0</td></tr>
          <tr><td>Tuz (g)</td><td>2.0</td></tr>
        </table>
        """
        soup = extractors.make_soup(html)
        nutri = extractors.extract_nutrition(soup)
        self.assertEqual(
            nutrition_parser.detect_basis(nutri["basis_text"]),
            nutrition_parser.BASIS_PER_100_GENERIC,
        )
        _data, warnings = nutrition_parser.build_nutrition(
            nutri["pairs"],
            basis_text=nutri["basis_text"],
            fallback_text=nutri["fallback_text"],
        )
        self.assertNotIn("nutrition_basis_unknown_assumed_per_100", warnings)

    def test_detect_basis_recognizes_combined_g_ml_variants_as_generic(self):
        for header in ("100 g / ml", "100 g/ml", "100g/ml"):
            self.assertEqual(
                nutrition_parser.detect_basis(f"Besin Değerleri {header} Enerji 200"),
                nutrition_parser.BASIS_PER_100_GENERIC,
                header,
            )

    def test_detect_basis_recognizes_gram_only_variants_as_per_100g(self):
        for header in ("100 g", "100g", "100 gr", "100gr"):
            self.assertEqual(
                nutrition_parser.detect_basis(f"Besin Değerleri {header} Enerji 200"),
                nutrition_parser.BASIS_PER_100G,
                header,
            )

    def test_detect_basis_recognizes_ml_only_as_per_100ml(self):
        for header in ("100 ml", "100ml"):
            self.assertEqual(
                nutrition_parser.detect_basis(f"Besin Değerleri {header} Enerji 200"),
                nutrition_parser.BASIS_PER_100ML,
                header,
            )

    def test_detect_basis_bare_per_100_phrase_is_generic(self):
        self.assertEqual(
            nutrition_parser.detect_basis("per 100 Enerji 200"),
            nutrition_parser.BASIS_PER_100_GENERIC,
        )

    def test_detect_basis_both_units_named_separately_is_generic(self):
        # Both a gram AND a millilitre mention appear, just not combined
        # into one "g / ml" token — still ambiguous, still generic.
        self.assertEqual(
            nutrition_parser.detect_basis(
                "100 g toz halinde veya 100 ml hazırlanmış olarak Enerji 200"
            ),
            nutrition_parser.BASIS_PER_100_GENERIC,
        )

    def test_section_o_liquid_food_soup_header_never_silently_resolved(self):
        # Section O of the basis remediation pass: a soup/oil-style label
        # naming both units in one combined header (as opposed to two fully
        # separate value columns, which this scraper does not yet extract —
        # see nutrition_parser.py's BASIS rule documentation) must stay
        # BASIS_PER_100_GENERIC — never silently resolved to per-100g via
        # the official tie-break rule, since that rule only applies once
        # two genuinely separate value sets are actually extracted.
        self.assertEqual(
            nutrition_parser.detect_basis("Çorba Besin Değerleri 100 g / ml Enerji 45"),
            nutrition_parser.BASIS_PER_100_GENERIC,
        )

    def test_detect_basis_raw_text_retained_in_candidate(self):
        html = """
        <table>
          <tr><th>Besin Değeri</th><td class="value">100 g</td></tr>
          <tr><td>Enerji (kcal)</td><td>248.0</td></tr>
        </table>
        """
        soup = extractors.make_soup(html)
        nutri = extractors.extract_nutrition(soup)
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/product-p-abc",
            jsonld={"name": "Test Ürün"},
            meta={},
            sections={},
            image_candidates=[],
            category="et",
            nutrition_basis=nutrition_parser.detect_basis(nutri["basis_text"]),
            nutrition_basis_raw_text=nutri["basis_text"],
        )
        self.assertEqual(
            candidate["raw_source_payload"]["nutrition_basis"],
            nutrition_parser.BASIS_PER_100G,
        )
        self.assertIn(
            "100 g",
            candidate["raw_source_payload"]["nutrition_basis_raw_text"],
        )

    def test_text_fallback_style(self):
        html = (
            "<html><body><p>Besin Değerleri 100 g için Enerji 199 kcal Yağ 15 g "
            "Doymuş yağ 3 g Karbonhidrat 5 g Şeker 0 g Protein 11 g Tuz 1.8 g</p>"
            "</body></html>"
        )
        data, _ = _nutrition_from_html(html)
        self.assertEqual(data["energy_kcal"], 199.0)
        self.assertEqual(data["fat"], 15.0)
        self.assertEqual(data["saturated_fat"], 3.0)
        self.assertEqual(data["sugars"], 0.0)
        self.assertEqual(data["salt"], 1.8)

    def test_embedded_json_style(self):
        html = """
        <script type="application/json">
        {"product":{"nutrition":[
          {"label":"Enerji (kcal)","value":"250"},
          {"label":"Yağ","value":"12,5"},
          {"label":"Doymuş yağ","value":"4"}
        ]}}
        </script>
        """
        data, _ = _nutrition_from_html(html)
        self.assertEqual(data["energy_kcal"], 250.0)
        self.assertEqual(data["fat"], 12.5)
        self.assertEqual(data["saturated_fat"], 4.0)


class ClassifyLabelTest(unittest.TestCase):
    def test_saturated_vs_plain_fat(self):
        self.assertEqual(nutrition_parser.classify_label("Doymuş yağ"), "saturated_fat")
        self.assertEqual(nutrition_parser.classify_label("Toplam yağ"), "fat")

    def test_energy_kcal_vs_kj(self):
        self.assertEqual(nutrition_parser.classify_label("Enerji (kcal)"), "energy_kcal")
        self.assertEqual(nutrition_parser.classify_label("Enerji (kJ)"), "energy_kj")
        self.assertEqual(nutrition_parser.classify_label("Enerji", "827 kJ"), "energy_kj")

    def test_sugar_maps_to_sugars(self):
        self.assertEqual(nutrition_parser.classify_label("Şeker"), "sugars")
        self.assertEqual(nutrition_parser.classify_label("Şekerler"), "sugars")

    def test_unrelated_label_is_none(self):
        self.assertIsNone(nutrition_parser.classify_label("Fatura No"))
        self.assertIsNone(nutrition_parser.classify_label("Yağmur"))


class TitleAndBrandTest(unittest.TestCase):
    def test_strips_retailer_suffix(self):
        self.assertEqual(runner.clean_title("Pınar Salam - Migros"), "Pınar Salam")
        self.assertEqual(runner.clean_title("Eti Popkek | Trendyol"), "Eti Popkek")

    def test_infers_known_brand_confidently(self):
        self.assertEqual(runner.infer_brand("Pınar Salam Hindi 700 g"), "Pınar")
        self.assertEqual(runner.infer_brand("Coca-Cola 1 L"), "Coca-Cola")

    def test_does_not_invent_unknown_brand(self):
        self.assertIsNone(runner.infer_brand("Bilinmeyen Marka Cips"))

    def test_infers_turkish_charcuterie_brands(self):
        self.assertEqual(runner.infer_brand("Namet 7 / 24 Hindi Salam 60 G"), "Namet")
        self.assertEqual(runner.infer_brand("Polonez Macar Salam 50 G"), "Polonez")
        self.assertEqual(runner.infer_brand("Maret Pratik Dana Macar Salam 50 G"), "Maret")

    def test_infers_meat_dairy_breakfast_brands(self):
        self.assertEqual(runner.infer_brand("Gedik Piliç Baget 1 Kg"), "Gedik")
        self.assertEqual(runner.infer_brand("Orvital Organik Bütün Piliç"), "Orvital")
        self.assertEqual(runner.infer_brand("Sütaş Kaymaklı Yoğurt 500 G"), "Sütaş")
        self.assertEqual(runner.infer_brand("İçim Süzme Peynir 250 G"), "İçim")
        self.assertEqual(runner.infer_brand("Bahçıvan Tam Yağlı Beyaz Peynir"), "Bahçıvan")
        self.assertEqual(runner.infer_brand("Şenpiliç Piliç But 1 Kg"), "Şenpiliç")

    def test_longest_brand_match_wins(self):
        # Multi-word brand should beat any shorter prefix interpretation.
        self.assertEqual(
            runner.infer_brand("Anadolu Lezzetleri Kaşar Peyniri 400 G"),
            "Anadolu Lezzetleri",
        )
        self.assertEqual(
            runner.infer_brand("Trabzon Çiftliği Tereyağı 500 G"),
            "Trabzon Çiftliği",
        )


class LinkDiscoveryTest(unittest.TestCase):
    def test_generic_patterns_and_excludes(self):
        html = """
        <a href="/pinar-salam-hindi-700-g-p-d74a2d">product</a>
        <a href="/cips-kategori-c-100">category</a>
        <a href="/sepet">cart</a>
        <a href="/login">login</a>
        <a href="https://cdn/x.css">style</a>
        <a href="/urun/eti-popkek-123">product2</a>
        """
        soup = extractors.make_soup(html)
        links = extractors.discover_product_links(
            soup, "https://www.migros.com.tr", product_link_patterns=["-p-"]
        )
        self.assertTrue(any("-p-d74a2d" in u for u in links))
        self.assertTrue(any("/urun/eti-popkek-123" in u for u in links))
        self.assertFalse(any("/sepet" in u for u in links))
        self.assertFalse(any("/login" in u for u in links))
        self.assertFalse(any(".css" in u for u in links))

    def test_respects_css_selector(self):
        html = """
        <a class="pcard" href="/p/abc">a</a>
        <a href="/p/zzz">b</a>
        """
        soup = extractors.make_soup(html)
        links = extractors.discover_product_links(
            soup, "https://x", product_link_selector="a.pcard"
        )
        self.assertEqual(links, ["https://x/p/abc"])


class EmbeddedLinkDiscoveryTest(unittest.TestCase):
    def test_normal_href(self):
        soup = extractors.make_soup('<a href="/abc-p-123">x</a>')
        links = extractors.discover_product_links(soup, "https://example.com")
        self.assertIn("https://example.com/abc-p-123", links)

    def test_script_json_product_array(self):
        soup = extractors.make_soup(
            '<script>{"products":[{"name":"Test","url":"/test-product-p-abc123"}]}</script>'
        )
        links = extractors.discover_product_links(soup, "https://example.com")
        self.assertIn("https://example.com/test-product-p-abc123", links)

    def test_escaped_json_url(self):
        soup = extractors.make_soup(
            '<script>{"url":"https:\\/\\/www.example.com\\/test-product-p-abc123"}</script>'
        )
        links = extractors.discover_product_links(soup, "https://www.example.com")
        self.assertIn("https://www.example.com/test-product-p-abc123", links)

    def test_next_data_nested_products(self):
        soup = extractors.make_soup(
            '<script id="__NEXT_DATA__" type="application/json">'
            '{"props":{"pageProps":{"products":[{"slug":"/test-product-p-abc123"}]}}}'
            "</script>"
        )
        links = extractors.discover_product_links(soup, "https://example.com")
        self.assertIn("https://example.com/test-product-p-abc123", links)

    def test_excludes_non_product_links(self):
        html = (
            '<a href="/sepet">cart</a>'
            '<a href="/login">login</a>'
            '<script>{"a":"/banner.jpg","b":"/app.css","c":"/main.js",'
            '"url":"/real-product-p-1"}</script>'
        )
        soup = extractors.make_soup(html)
        links = extractors.discover_product_links(soup, "https://example.com")
        self.assertIn("https://example.com/real-product-p-1", links)
        self.assertFalse(any("/sepet" in u for u in links))
        self.assertFalse(any("/login" in u for u in links))
        self.assertFalse(any(u.endswith((".jpg", ".css", ".js")) for u in links))

    def test_stats_reported_when_empty(self):
        soup = extractors.make_soup("<html><body>no products here</body></html>")
        links, stats = extractors.discover_with_stats(soup, "https://example.com")
        self.assertEqual(links, [])
        self.assertIn("html_length", stats)
        self.assertIn("script_count", stats)
        self.assertIn("api_endpoint_hints", stats)
        self.assertEqual(stats["json_product_url_count"], 0)


class SuspiciousIngredientsTest(unittest.TestCase):
    def test_real_ingredient_list_passes(self):
        self.assertFalse(
            ingredient_parser.is_suspicious(
                "Dana eti, baharat karışımı, tuz, su, patates nişastası"
            )
        )

    def test_too_short_is_suspicious(self):
        self.assertTrue(ingredient_parser.is_suspicious("Hindi eti"))
        self.assertTrue(ingredient_parser.is_suspicious(""))
        self.assertTrue(ingredient_parser.is_suspicious(None))

    def test_net_amount_only_is_suspicious(self):
        self.assertTrue(ingredient_parser.is_suspicious("Net Miktar 300 g paket"))

    def test_nutrition_labels_mixed_is_suspicious(self):
        self.assertTrue(
            ingredient_parser.is_suspicious(
                "Besin Değerleri Enerji 248 kcal Yağ 20 g Protein 11 g"
            )
        )

    def test_no_separator_few_tokens_is_suspicious(self):
        self.assertTrue(ingredient_parser.is_suspicious("Piliç But Baget Izgara"))

    def test_quality_score_lowered_for_suspicious_ingredients(self):
        base = {
            "name": "X Ürün", "brand": "Marka",
            "image_front_url": "https://x/p.jpg",
            "nutrition_json": {"energy_kcal": 100.0},
            "category_suggestion": "kek",
            "source_url": "https://x/p-1",
            "barcode": "8690000000001",
        }
        good = runner.evaluate_quality_web(
            {**base, "ingredients_text": "Buğday unu, şeker, bitkisel yağ, kakao"}
        )
        bad = runner.evaluate_quality_web(
            {**base, "ingredients_text": "Net Miktar 300 gram ambalaj bilgisi x"}
        )
        self.assertGreater(good[0], bad[0])  # suspicious loses the 25 points
        self.assertIn("ingredients_suspicious", bad[1])
        self.assertLess(bad[0], 100)  # can never auto-approve at min-score 100


class AutoApprovalEligibilityTest(unittest.TestCase):
    def _row(self, **over):
        row = {
            "id": "staging-x",
            "source": "web_scraper:migros",
            "status": "pending",
            "quality_score": 100,
            "name": "Namet Macar Salam Kg",
            "brand": "Namet",
            "image_front_url": "https://img/namet.jpg",
            "ingredients_text": "dana eti, baharat, tuz, su",
            "nutrition_json": {"energy_kcal": 248.0, "fat": 20.0},
            "source_url": "https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff",
            "barcode": None,
        }
        row.update(over)
        return row

    def test_perfect_web_scraper_product_eligible(self):
        self.assertIsNone(runner.auto_approve_block_reason(self._row(), 100))

    def test_score_below_min_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(quality_score=88), 100),
            "score_too_low",
        )

    def test_missing_brand_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(brand=""), 100),
            "missing_brand",
        )

    def test_missing_nutrition_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(nutrition_json={}), 100),
            "missing_nutrition",
        )

    def test_missing_ingredients_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(ingredients_text=None), 100),
            "missing_ingredients",
        )

    def test_suspicious_ingredients_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(
                self._row(ingredients_text="Net Miktar 300 gram paket bilgi"), 100
            ),
            "suspicious_ingredients",
        )

    def test_missing_image_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(image_front_url=None), 100),
            "missing_image",
        )

    def test_missing_source_url_left_for_review(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(source_url=""), 100),
            "missing_source_url",
        )

    def test_non_web_scraper_source_ineligible(self):
        self.assertEqual(
            runner.auto_approve_block_reason(
                self._row(source="open_food_facts", barcode="8690000000001"), 100
            ),
            "ineligible_source",
        )

    def test_non_pending_status_not_approved(self):
        self.assertEqual(
            runner.auto_approve_block_reason(self._row(status="approved"), 100),
            "not_pending",
        )

    def test_dedupe_key_prefers_barcode_then_source_url(self):
        self.assertEqual(
            runner.approval_dedupe_key(self._row(barcode="8690000000001")),
            ("barcode", "8690000000001"),
        )
        self.assertEqual(
            runner.approval_dedupe_key(self._row()),
            (
                "source_url",
                "https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff",
            ),
        )

    def test_product_insert_map_no_fake_barcode(self):
        m = runner._product_insert_map(self._row())
        self.assertIsNone(m["barcode"])  # never invented
        self.assertEqual(m["verification_status"], "pending")
        self.assertEqual(m["source"], "web_scraper:migros")
        self.assertIn("nutrition_text", m)
        self.assertEqual(
            m["source_url"],
            "https://www.migros.com.tr/namet-macar-salam-kg-p-d749ff",
        )


class IngredientsExtractionTest(unittest.TestCase):
    def test_embedded_json_ingredients(self):
        html = """
        <script type="application/json">
        {"data":{"icindekiler":"Buğday unu, şeker, bitkisel yağ, kakao, fındık"}}
        </script>
        """
        soup = extractors.make_soup(html)
        raw = extractors.extract_ingredients_text(soup)
        cleaned = ingredient_parser.clean_ingredients(raw)
        self.assertIn("Buğday unu", cleaned)


class _JsonStubFetcher:
    """Stub fetcher: serves JSON for known endpoints and simple product HTML."""

    def __init__(self, json_map=None, html_map=None):
        self.json_map = json_map or {}
        self.html_map = html_map or {}
        self.json_calls: list[str] = []
        self.html_calls: list[str] = []

    def get_json(self, url, headers=None):
        self.json_calls.append(url)
        data = self.json_map.get(url)
        if data is None:
            return None, FetchResult(url=url, status=404, error="http 404")
        return data, FetchResult(url=url, status=200, ok=True, final_url=url)

    def get(self, url):
        self.html_calls.append(url)
        html = self.html_map.get(url)
        if html is None:
            html = "<html><body>no product links here</body></html>"
        return FetchResult(url=url, status=200, html=html, ok=True, final_url=url)


def _migros_source(**adapter_config):
    return source_config.Source(
        id="migros",
        adapter="migros",
        base_url="https://www.migros.com.tr",
        product_link_patterns=["-p-"],
        exclude_link_patterns=["/sepet"],
        adapter_config=adapter_config,
    )


class AdapterRegistryTest(unittest.TestCase):
    def test_get_adapter_selects_migros(self):
        adapter = source_adapters.get_adapter("migros")
        self.assertIsInstance(adapter, MigrosAdapter)

    def test_unknown_adapter_is_none(self):
        self.assertIsNone(source_adapters.get_adapter("does-not-exist"))
        self.assertIsNone(source_adapters.get_adapter(""))

    def test_can_handle_requires_opt_in_and_host(self):
        adapter = MigrosAdapter()
        src = _migros_source()
        self.assertTrue(adapter.can_handle(src, "https://www.migros.com.tr/salam-c-112d6"))
        other = source_config.Source(id="other", adapter="other")
        self.assertFalse(adapter.can_handle(other, "https://x/y"))


class UrlTemplateTest(unittest.TestCase):
    def test_renders_placeholders(self):
        out = _render_template(
            "https://x/api/categories/{category_id}/products?{page_param}={page}",
            category_id="112d6",
            category_slug="salam",
            category_url="https://x/salam-c-112d6",
            page=2,
            page_param="page",
        )
        self.assertEqual(out, "https://x/api/categories/112d6/products?page=2")


class AdapterJsonExtractionTest(unittest.TestCase):
    def test_discovers_two_product_urls_from_api(self):
        endpoint = "https://www.migros.com.tr/api/112d6?page=1"
        src = _migros_source(
            api_url_template="https://www.migros.com.tr/api/{category_id}?page={page}",
            category_id="112d6",
        )
        data = {
            "products": [
                {"name": "Test", "url": "/test-product-p-abc123"},
                {"title": "Other", "seoUrl": "/other-product-p-def456"},
            ]
        }
        fetcher = _JsonStubFetcher(json_map={endpoint: data})
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, src, "https://www.migros.com.tr/salam-c-112d6", "salam", 10
        )
        self.assertIn("https://www.migros.com.tr/test-product-p-abc123", urls)
        self.assertIn("https://www.migros.com.tr/other-product-p-def456", urls)
        self.assertEqual(debug["adapter_used"], "migros")
        self.assertEqual(debug["product_count"], 2)
        self.assertEqual(debug["endpoint_called"], endpoint)

    def test_no_endpoint_returns_zero_with_warning(self):
        src = _migros_source(api_url_template="")
        fetcher = _JsonStubFetcher()  # get() returns generic HTML with no API hints
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, src, "https://www.migros.com.tr/salam-c-112d6", "salam", 10
        )
        self.assertEqual(urls, [])
        self.assertTrue(
            any("no API endpoint" in w for w in debug["warnings"]),
            debug["warnings"],
        )


class MigrosStoreProductInfosTest(unittest.TestCase):
    def _run(self, store_infos, limit=10, page_count=2, hit_count=38):
        endpoint = "https://www.migros.com.tr/rest/search/screens/salam-c-112d6"
        src = _migros_source(api_url_template=endpoint, category_id="112d6")
        data = {
            "successful": True,
            "data": {
                "searchInfo": {
                    "pageCount": page_count,
                    "hitCount": hit_count,
                    "storeProductInfos": store_infos,
                }
            },
        }
        fetcher = _JsonStubFetcher(json_map={endpoint: data})
        return MigrosAdapter().discover_product_urls(
            fetcher, src, "https://www.migros.com.tr/salam-c-112d6", "salam", limit
        )

    def test_builds_urls_from_pretty_name(self):
        urls, debug = self._run(
            [
                {
                    "name": "Namet 7 / 24 Hindi Salam 60 G",
                    "prettyName": "namet-7-24-hindi-salam-60-g-p-d749eb",
                    "status": "IN_SALE",
                },
                {
                    "name": "Pınar Aç Bitir Salam",
                    "prettyName": "pinar-ac-bitir-salam-p-d74abc",
                    "status": "IN_SALE",
                },
            ]
        )
        self.assertEqual(
            urls,
            [
                "https://www.migros.com.tr/namet-7-24-hindi-salam-60-g-p-d749eb",
                "https://www.migros.com.tr/pinar-ac-bitir-salam-p-d74abc",
            ],
        )
        self.assertEqual(debug["migros_store_product_count"], 2)
        self.assertEqual(debug["migros_prettyname_url_count"], 2)
        self.assertEqual(debug["page_count"], 2)
        self.assertEqual(debug["hit_count"], 38)
        self.assertEqual(debug["product_count"], 2)

    def test_skips_product_without_pretty_name(self):
        urls, _ = self._run(
            [
                {"name": "No Slug Salam", "status": "IN_SALE"},
                {"name": "Has Slug", "prettyName": "has-slug-p-d7ffff", "status": "IN_SALE"},
            ]
        )
        self.assertEqual(urls, ["https://www.migros.com.tr/has-slug-p-d7ffff"])

    def test_skips_pretty_name_without_p_marker(self):
        # brand/category prettyNames use -b-/-c-, not -p-, so must be skipped.
        urls, _ = self._run(
            [
                {"name": "Brandish", "prettyName": "namet-b-316", "status": "IN_SALE"},
                {"name": "Categorish", "prettyName": "hindi-salam-c-112db", "status": "IN_SALE"},
                {"name": "Real", "prettyName": "real-product-p-d70001", "status": "IN_SALE"},
            ]
        )
        self.assertEqual(urls, ["https://www.migros.com.tr/real-product-p-d70001"])

    def test_limit_is_respected(self):
        infos = [
            {"name": f"P{i}", "prettyName": f"p-{i}-p-d7{i:04d}", "status": "IN_SALE"}
            for i in range(20)
        ]
        urls, debug = self._run(infos, limit=5)
        self.assertEqual(len(urls), 5)
        self.assertEqual(debug["product_count"], 5)

    def test_in_sale_ordered_first(self):
        urls, _ = self._run(
            [
                {"name": "Out", "prettyName": "out-p-d70002", "status": "OUT_OF_STOCK"},
                {"name": "In", "prettyName": "in-p-d70003", "status": "IN_SALE"},
            ]
        )
        self.assertEqual(urls[0], "https://www.migros.com.tr/in-p-d70003")


class _PaginatingStub:
    """Stub fetcher serving paged Migros JSON keyed by a query parameter.

    `pages` maps page-number → list of prettyNames. `param` is the query
    parameter the fake server honors; requests using any other parameter (or
    none) return page 1 (simulating an ignored/unknown pagination param).
    """

    def __init__(self, pages, page_count, hit_count, param="sayfa"):
        self.pages = pages
        self.page_count = page_count
        self.hit_count = hit_count
        self.param = param
        self.calls: list[str] = []

    def _page_of(self, url):
        m = re.search(rf"[?&]{self.param}=(\d+)", url)
        return int(m.group(1)) if m else 1

    def get_json(self, url, headers=None):
        self.calls.append(url)
        names = self.pages.get(self._page_of(url), [])
        data = {
            "data": {
                "searchInfo": {
                    "pageCount": self.page_count,
                    "hitCount": self.hit_count,
                    "storeProductInfos": [
                        {"name": n, "prettyName": n, "status": "IN_SALE"}
                        for n in names
                    ],
                }
            }
        }
        return data, FetchResult(url=url, status=200, ok=True, final_url=url)

    def get(self, url):
        return FetchResult(url=url, status=200, html="<html></html>", ok=True, final_url=url)


class MigrosPaginationTest(unittest.TestCase):
    def _src(self):
        return _migros_source(
            api_url_template="https://www.migros.com.tr/rest/search/screens/{category_slug}",
            max_pages=3,
        )

    def test_category_slug_from_url(self):
        self.assertEqual(
            _category_slug("https://www.migros.com.tr/sucuk-c-404"), "sucuk-c-404"
        )
        self.assertEqual(
            _category_slug("https://www.migros.com.tr/salam-c-112d6"), "salam-c-112d6"
        )

    def test_fetches_all_pages_up_to_limit(self):
        pages = {
            1: [f"p1-{i}-p-d1{i:02d}" for i in range(30)],
            2: [f"p2-{i}-p-d2{i:02d}" for i in range(30)],
            3: [f"p3-{i}-p-d3{i:02d}" for i in range(10)],
        }
        fetcher = _PaginatingStub(pages, page_count=3, hit_count=70, param="sayfa")
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, self._src(), "https://www.migros.com.tr/sucuk-c-404", "sucuk", 70
        )
        self.assertEqual(len(urls), 70)
        self.assertEqual(debug["product_count"], 70)
        self.assertEqual(debug["page_count"], 3)
        self.assertEqual(debug["hit_count"], 70)
        self.assertEqual(debug["fetched_pages"], [1, 2, 3])
        self.assertEqual(debug["urls_per_page"], {1: 30, 2: 30, 3: 10})
        self.assertEqual(debug["pagination_param_used"], "sayfa")
        # base (page-1) endpoint reported, not a paginated URL
        self.assertEqual(
            debug["endpoint_called"],
            "https://www.migros.com.tr/rest/search/screens/sucuk-c-404",
        )

    def test_stops_when_limit_reached_without_extra_pages(self):
        pages = {
            1: [f"p1-{i}-p-d1{i:02d}" for i in range(30)],
            2: [f"p2-{i}-p-d2{i:02d}" for i in range(30)],
            3: [f"p3-{i}-p-d3{i:02d}" for i in range(10)],
        }
        fetcher = _PaginatingStub(pages, page_count=3, hit_count=70, param="sayfa")
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, self._src(), "https://www.migros.com.tr/sucuk-c-404", "sucuk", 10
        )
        self.assertEqual(len(urls), 10)
        # limit satisfied by page 1 → no second page fetched
        self.assertEqual(debug["fetched_pages"], [1])
        self.assertNotIn("sayfa=2", "".join(fetcher.calls))

    def test_salam_can_fetch_into_second_page(self):
        pages = {
            1: [f"s1-{i}-p-d1{i:02d}" for i in range(30)],
            2: [f"s2-{i}-p-d2{i:02d}" for i in range(30)],
        }
        fetcher = _PaginatingStub(pages, page_count=2, hit_count=60, param="sayfa")
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, self._src(), "https://www.migros.com.tr/salam-c-112d6", "salam", 38
        )
        self.assertEqual(len(urls), 38)  # 30 from page 1 + 8 from page 2
        self.assertEqual(debug["fetched_pages"], [1, 2])

    def test_duplicate_page_protection_warns_and_stops(self):
        # Server ignores every pagination param → always returns page 1.
        page1 = [f"d-{i}-p-d1{i:02d}" for i in range(30)]
        fetcher = _PaginatingStub(
            {1: page1, 2: page1, 3: page1},
            page_count=3,
            hit_count=70,
            param="__none__",  # no adapter candidate matches → always page 1
        )
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, self._src(), "https://www.migros.com.tr/sucuk-c-404", "sucuk", 70
        )
        self.assertEqual(len(urls), 30)  # only first page, no infinite loop
        self.assertEqual(debug["fetched_pages"], [1])
        self.assertIsNone(debug["pagination_param_used"])
        self.assertTrue(
            any("pagination parameter not found" in w for w in debug["warnings"]),
            debug["warnings"],
        )


class ApiMetadataTest(unittest.TestCase):
    """Brand and image from Migros API metadata are used when the detail page yields none."""

    def _run_with_store_info(self, store_info: dict, product_slug: str) -> list[dict]:
        """Stub a Migros API response with one product and scrape its detail page."""
        category_url = "https://www.migros.com.tr/peynir-c-55"
        api_endpoint = "https://www.migros.com.tr/rest/search/screens/peynir-c-55"
        product_url = f"https://www.migros.com.tr/{product_slug}"
        src = _migros_source(api_url_template=api_endpoint)
        data = {
            "data": {
                "searchInfo": {
                    "pageCount": 1,
                    "hitCount": 1,
                    "storeProductInfos": [store_info],
                }
            }
        }
        fetcher = _JsonStubFetcher(
            json_map={api_endpoint: data},
            html_map={
                category_url: "<html><body></body></html>",
                product_url: (
                    f"<html><head><title>{store_info.get('name', 'Ürün')}</title></head>"
                    "<body><h1>Ürün</h1></body></html>"
                ),
            },
        )
        opts = {**src.discovery_options(), "source": src}
        work = [("category", category_url, "peynir", "migros", opts)]
        run = runner.run_scrape(work, limit=5, delay=0, timeout=5, fetcher=fetcher)
        return run.candidates

    def test_api_brand_lente_used_when_page_has_none(self):
        info = {
            "name": "Lente Gouda Kimyonlu 200 G",
            "prettyName": "lente-gouda-kimyonlu-200-g-p-abc123",
            "status": "IN_SALE",
            "brand": {"name": "Lente"},
        }
        candidates = self._run_with_store_info(info, "lente-gouda-kimyonlu-200-g-p-abc123")
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["brand"], "Lente")
        self.assertEqual(candidates[0].get("brand_source_method"), "api_metadata")

    def test_api_brand_gedik_used_when_page_has_none(self):
        info = {
            "name": "Gedik Parça Kavurma 500 G",
            "prettyName": "gedik-parca-kavurma-500-g-p-abc456",
            "status": "IN_SALE",
            "brand": {"name": "Gedik"},
        }
        candidates = self._run_with_store_info(info, "gedik-parca-kavurma-500-g-p-abc456")
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["brand"], "Gedik")
        self.assertEqual(candidates[0].get("brand_source_method"), "api_metadata")

    def test_url_metadata_in_adapter_debug(self):
        """_urls_from_store_infos returns metadata for each URL."""
        from web_scraper.source_adapters.migros_adapter import _urls_from_store_infos
        store_infos = [
            {
                "name": "Lente Gouda 200 G",
                "prettyName": "lente-gouda-200-g-p-abc",
                "status": "IN_SALE",
                "brand": {"name": "Lente"},
            }
        ]
        urls, meta = _urls_from_store_infos(
            store_infos, "https://www.migros.com.tr", []
        )
        self.assertEqual(len(urls), 1)
        url = urls[0]
        self.assertIn(url, meta)
        self.assertEqual(meta[url]["api_brand"], "Lente")
        self.assertEqual(meta[url]["api_name"], "Lente Gouda 200 G")

    def test_title_fallback_trakya_ciftligi(self):
        self.assertEqual(
            runner.infer_brand("Trakya Çiftliği Vegan Mavi Damar Peynir 200 G"),
            "Trakya Çiftliği",
        )

    def test_title_fallback_hasmandira(self):
        self.assertEqual(
            runner.infer_brand("Hasmandıra Göğermiş Peynir Kg"),
            "Hasmandıra",
        )

    def test_title_fallback_guneydogu(self):
        self.assertEqual(
            runner.infer_brand("Güneydoğu Yarım Yağlı Örgü Peynir 500 G"),
            "Güneydoğu",
        )

    def test_api_brand_takes_priority_over_title_fallback(self):
        """When API says 'Lente', candidate.brand must be 'Lente' even if title fallback would differ."""
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/lente-gouda-p-abc",
            jsonld={"name": "Lente Gouda Kimyonlu 200 G"},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={"api_brand": "Lente", "api_name": None, "api_image_url": None,
                          "api_category": None, "api_sku": None},
        )
        self.assertEqual(candidate["brand"], "Lente")
        self.assertEqual(candidate.get("brand_source_method"), "api_metadata")

    def test_assemble_uses_api_name_when_page_has_none(self):
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/some-product-p-xyz",
            jsonld={},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={"api_brand": "Eker", "api_name": "Eker Taze Kaşar 400 G",
                          "api_image_url": None, "api_category": None, "api_sku": None},
        )
        self.assertEqual(candidate["name"], "Eker Taze Kaşar 400 G")
        self.assertEqual(candidate["brand"], "Eker")
        self.assertEqual(candidate.get("brand_source_method"), "api_metadata")


class JunkIngredientsTest(unittest.TestCase):
    """Ingredients that are clearly UI/policy text are rejected and cleared."""

    def test_iade_kosullari_is_junk(self):
        text = "İade Koşulları: Satın aldığınız ürünü 14 gün içinde iade edebilirsiniz."
        self.assertEqual(
            ingredient_parser.ingredient_quality(text),
            ingredient_parser.INGREDIENT_QUALITY_REJECTED_JUNK,
        )
        self.assertTrue(ingredient_parser.is_junk(text))

    def test_iade_surecini_is_junk(self):
        text = "İade Sürecini Nasıl Başlatabilirim? Müşteri hizmetleri arayınız."
        self.assertEqual(
            ingredient_parser.ingredient_quality(text),
            ingredient_parser.INGREDIENT_QUALITY_REJECTED_JUNK,
        )

    def test_sepete_ekle_is_junk(self):
        text = "Sepete Ekle butonuna tıklayarak alışverişinizi tamamlayın."
        self.assertTrue(ingredient_parser.is_junk(text))

    def test_valid_ingredients_ok(self):
        text = "Dana eti, tuz, baharat karışımı, su, patates nişastası"
        self.assertEqual(
            ingredient_parser.ingredient_quality(text),
            ingredient_parser.INGREDIENT_QUALITY_OK,
        )
        self.assertFalse(ingredient_parser.is_junk(text))

    def test_net_amount_only_is_suspicious_not_junk(self):
        text = "Net Miktar 300 gram paket"
        quality = ingredient_parser.ingredient_quality(text)
        # net-amount text is suspicious (or missing), never junk
        self.assertNotEqual(quality, ingredient_parser.INGREDIENT_QUALITY_REJECTED_JUNK)
        self.assertIn(
            quality,
            (ingredient_parser.INGREDIENT_QUALITY_SUSPICIOUS,
             ingredient_parser.INGREDIENT_QUALITY_MISSING),
        )

    def test_junk_text_cleared_in_assembled_candidate(self):
        """assemble_candidate sets ingredients_text=None when raw text is junk."""
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/product-p-abc",
            jsonld={"name": "Test Ürün"},
            meta={},
            sections={},
            image_candidates=[],
            category="et",
            ingredients_raw="İade Koşulları: 14 gün içinde iade edebilirsiniz.",
        )
        self.assertIsNone(candidate["ingredients_text"])
        self.assertEqual(
            candidate.get("ingredient_quality"),
            ingredient_parser.INGREDIENT_QUALITY_REJECTED_JUNK,
        )

    def test_junk_ingredients_block_auto_approve(self):
        """A staged row with junk ingredients is blocked from auto-approval."""
        row = {
            "id": "x", "source": "web_scraper:migros", "status": "pending",
            "quality_score": 100,
            "name": "Test Ürün", "brand": "Marka",
            "image_front_url": "https://x/p.jpg",
            "ingredients_text": "İade Koşulları: 14 gün içinde iade edebilirsiniz.",
            "nutrition_json": {"energy_kcal": 100.0},
            "source_url": "https://x/p-1",
        }
        reason = runner.auto_approve_block_reason(row, 100)
        self.assertEqual(reason, "suspicious_ingredients")

    def test_empty_is_missing_not_junk(self):
        self.assertEqual(
            ingredient_parser.ingredient_quality(None),
            ingredient_parser.INGREDIENT_QUALITY_MISSING,
        )
        self.assertEqual(
            ingredient_parser.ingredient_quality(""),
            ingredient_parser.INGREDIENT_QUALITY_MISSING,
        )


class DynamicBrandFacetTest(unittest.TestCase):
    """Dynamic brand list from Migros aggregationGroups drives title-prefix matching."""

    _BRANDS = ["Muratbey", "Bahçıvan", "Lente", "Trakya Çiftliği", "La Vache Qui Rit"]

    # ── _extract_dynamic_brands helper ─────────────────────────────────────────

    def test_extracts_brands_from_aggregation_groups(self):
        search_info = {
            "aggregationGroups": [
                {"type": "CATEGORY", "aggregationInfos": [{"label": "Peynir"}]},
                {
                    "type": "BRAND",
                    "label": "Markalar",
                    "aggregationInfos": [
                        {"label": "Muratbey"},
                        {"label": "Bahçıvan"},
                        {"label": "Lente"},
                    ],
                },
            ]
        }
        brands = _extract_dynamic_brands(search_info)
        self.assertEqual(brands, ["Muratbey", "Bahçıvan", "Lente"])

    def test_returns_empty_when_no_brand_group(self):
        search_info = {"aggregationGroups": [{"type": "CATEGORY", "aggregationInfos": []}]}
        self.assertEqual(_extract_dynamic_brands(search_info), [])

    # ── _match_dynamic_brand function ──────────────────────────────────────────

    def test_match_dynamic_brand_exact_prefix(self):
        from web_scraper.runner import _match_dynamic_brand
        brand = _match_dynamic_brand("Bahçıvan Beyaz Peynir 400 G", self._BRANDS)
        self.assertEqual(brand, "Bahçıvan")

    def test_match_dynamic_brand_multiword_wins_over_single(self):
        from web_scraper.runner import _match_dynamic_brand
        brand = _match_dynamic_brand(
            "La Vache Qui Rit Krempeynir 200 G", self._BRANDS
        )
        self.assertEqual(brand, "La Vache Qui Rit")

    def test_match_dynamic_brand_short_brand_skipped(self):
        """A brand whose normalized form is < 3 chars must never match."""
        from web_scraper.runner import _match_dynamic_brand
        # "AB" normalizes to "ab" (2 chars) — too short, should be skipped.
        brands = ["AB", "Lente"]
        brand = _match_dynamic_brand("AB Peyniri 200 G", brands)
        # Must not match "AB" (too short), may still match others or return None.
        self.assertNotEqual(brand, "AB")

    # ── assemble_candidate priority ────────────────────────────────────────────

    def test_dynamic_brand_used_when_api_and_page_missing(self):
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/muratbey-kasar-200-g-p-abc",
            jsonld={"name": "Muratbey Kaşar 200 G"},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={
                "api_brand": None,
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": self._BRANDS,
            },
        )
        self.assertEqual(candidate["brand"], "Muratbey")
        self.assertEqual(candidate["brand_source_method"], "dynamic_category_brand")

    def test_api_brand_takes_priority_over_dynamic(self):
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/lente-gouda-p-xyz",
            jsonld={"name": "Lente Gouda 200 G"},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={
                "api_brand": "Lente",
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": ["Muratbey", "Bahçıvan"],
            },
        )
        self.assertEqual(candidate["brand"], "Lente")
        self.assertEqual(candidate["brand_source_method"], "api_metadata")

    def test_detail_page_brand_takes_priority_over_dynamic(self):
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/bahcivan-peynir-p-abc",
            jsonld={"name": "Bahçıvan Peynir", "brand": "Bahçıvan"},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={
                "api_brand": None,
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": ["Muratbey", "Bahçıvan"],
            },
        )
        self.assertEqual(candidate["brand"], "Bahçıvan")
        self.assertEqual(candidate["brand_source_method"], "detail_page")

    def test_hardcoded_known_brand_fallback_when_not_in_dynamic(self):
        """When dynamic list doesn't match, falls through to KNOWN_BRANDS."""
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/pinar-sutlu-kakaolu-p-abc",
            jsonld={"name": "Pınar Sütlü Kakaolu"},
            meta={},
            sections={},
            image_candidates=[],
            category="süt",
            api_metadata={
                "api_brand": None,
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                # Dynamic list does not include Pınar
                "category_dynamic_brands": ["Muratbey", "Bahçıvan"],
            },
        )
        self.assertEqual(candidate["brand"], "Pınar")
        self.assertEqual(candidate["brand_source_method"], "hardcoded_known_brand")

    def test_dynamic_brand_removes_brand_from_missing_fields(self):
        """quality_score includes brand points when dynamic brand is found."""
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/muratbey-kashar-p-abc",
            jsonld={"name": "Muratbey Kaşar 400 G"},
            meta={},
            sections={},
            image_candidates=[],
            category="peynir",
            api_metadata={
                "api_brand": None,
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": self._BRANDS,
            },
        )
        self.assertNotIn("brand", candidate["missing_fields"])

    # ── adapter debug fields ───────────────────────────────────────────────────

    def test_dynamic_brands_in_adapter_debug(self):
        """After discover_product_urls, debug contains dynamic_brand_count and first_20."""
        endpoint = "https://www.migros.com.tr/rest/search/screens/peynir-c-6d"
        src = _migros_source(api_url_template=endpoint)
        data = {
            "data": {
                "searchInfo": {
                    "pageCount": 1,
                    "hitCount": 2,
                    "storeProductInfos": [
                        {
                            "name": "Muratbey Kaşar 400 G",
                            "prettyName": "muratbey-kasar-400-g-p-aaa",
                            "status": "IN_SALE",
                        }
                    ],
                    "aggregationGroups": [
                        {
                            "type": "BRAND",
                            "label": "Markalar",
                            "aggregationInfos": [
                                {"label": "Muratbey"},
                                {"label": "Bahçıvan"},
                                {"label": "Lente"},
                            ],
                        }
                    ],
                }
            }
        }
        fetcher = _JsonStubFetcher(json_map={endpoint: data})
        urls, debug = MigrosAdapter().discover_product_urls(
            fetcher, src, "https://www.migros.com.tr/peynir-c-6d", "peynir", 10
        )
        self.assertEqual(debug["dynamic_brand_count"], 3)
        self.assertIn("Muratbey", debug["first_20_dynamic_brands"])
        self.assertIn("Bahçıvan", debug["first_20_dynamic_brands"])
        self.assertIn("Lente", debug["first_20_dynamic_brands"])
        # Dynamic brands threaded into url_metadata
        url_meta = debug["url_metadata"]
        self.assertTrue(len(url_meta) > 0)
        for meta in url_meta.values():
            self.assertIn("category_dynamic_brands", meta)
            self.assertIn("Muratbey", meta["category_dynamic_brands"])


class RunnerAdapterFallbackTest(unittest.TestCase):
    def test_generic_zero_then_adapter_supplies_urls(self):
        category_url = "https://www.migros.com.tr/salam-c-112d6"
        product_url = "https://www.migros.com.tr/test-product-p-abc123"
        endpoint = "https://www.migros.com.tr/api/112d6?page=1"
        src = _migros_source(
            api_url_template="https://www.migros.com.tr/api/{category_id}?page={page}",
            category_id="112d6",
        )
        fetcher = _JsonStubFetcher(
            json_map={endpoint: {"products": [{"name": "X", "url": "/test-product-p-abc123"}]}},
            html_map={
                category_url: "<html><body>client rendered, no links</body></html>",
                product_url: (
                    "<html><head><title>Test Ürün - Migros</title></head>"
                    "<body><h1>Test Ürün</h1></body></html>"
                ),
            },
        )
        opts = {**src.discovery_options(), "source": src}
        work = [("category", category_url, "salam", "migros", opts)]
        run = runner.run_scrape(work, limit=5, delay=0, timeout=5, fetcher=fetcher)
        self.assertEqual(len(run.candidates), 1)
        self.assertEqual(run.candidates[0]["name"], "Test Ürün")
        self.assertIn(product_url, fetcher.html_calls)


class ParentBrandOverrideTest(unittest.TestCase):
    """Sub-brand/product-line → parent brand correction based on product title."""

    def _candidate(self, name, api_brand=None, dynamic_brands=None, page_brand=None):
        jsonld_dict = {"name": name}
        if page_brand:
            jsonld_dict["brand"] = page_brand
        return runner.assemble_candidate(
            source_id="migros",
            url=f"https://www.migros.com.tr/product-p-abc",
            jsonld=jsonld_dict,
            meta={},
            sections={},
            image_candidates=[],
            category="kahvaltiliklar",
            api_metadata={
                "api_brand": api_brand,
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": dynamic_brands or [],
            },
        )

    # ── detect_parent_brand_override helper ────────────────────────────────────

    def test_eti_lifalif_overridden_to_eti(self):
        result = runner.detect_parent_brand_override(
            "Eti Lifalif İnce Öğütülmüş Yulaf Ezmesi 350 G", "Lifalif"
        )
        self.assertEqual(result, "Eti")

    def test_lifalif_only_title_not_overridden(self):
        result = runner.detect_parent_brand_override("Lifalif Yulaf Ezmesi 350 G", "Lifalif")
        self.assertIsNone(result)

    def test_ulker_cokokrem_overridden(self):
        result = runner.detect_parent_brand_override("Ülker Çokokrem Cam 650 G", "Çokokrem")
        self.assertEqual(result, "Ülker")

    def test_torku_not_overridden(self):
        result = runner.detect_parent_brand_override("Torku Tahin 600 G", "Torku")
        self.assertIsNone(result)  # Torku not a sub-brand

    # ── assemble_candidate integration ────────────────────────────────────────

    def test_api_brand_lifalif_corrected_to_eti(self):
        c = self._candidate("Eti Lifalif İnce Öğütülmüş Yulaf Ezmesi 350 G", api_brand="Lifalif")
        self.assertEqual(c["brand"], "Eti")
        self.assertEqual(c["brand_source_method"], "parent_brand_override")
        self.assertEqual(c["brand_raw"], "Lifalif")

    def test_api_brand_lifalif_standalone_title_kept(self):
        c = self._candidate("Lifalif Yulaf Ezmesi 350 G", api_brand="Lifalif")
        self.assertEqual(c["brand"], "Lifalif")
        self.assertEqual(c["brand_source_method"], "api_metadata")
        self.assertIsNone(c["brand_raw"])

    def test_api_brand_cokokrem_corrected_to_ulker(self):
        c = self._candidate("Ülker Çokokrem Cam 650 G", api_brand="Çokokrem")
        self.assertEqual(c["brand"], "Ülker")
        self.assertEqual(c["brand_source_method"], "parent_brand_override")

    def test_api_brand_cokokrem_standalone_kept(self):
        c = self._candidate("Çokokrem Cam 650 G", api_brand="Çokokrem")
        self.assertEqual(c["brand"], "Çokokrem")
        self.assertIsNone(c["brand_raw"])

    def test_api_brand_nesquik_corrected_to_nestle(self):
        c = self._candidate("Nestle Nesquik Çoko Kare 310 G", api_brand="Nesquik")
        self.assertEqual(c["brand"], "Nestle")
        self.assertEqual(c["brand_source_method"], "parent_brand_override")

    def test_api_brand_kelloggs_is_parent_no_override(self):
        """Kellogg's is itself the parent brand — must not be overridden."""
        c = self._candidate(
            "Kellogg's Corn Flakes Mısır Gevreği 400 G", api_brand="Kellogg's"
        )
        self.assertEqual(c["brand"], "Kellogg's")
        self.assertNotEqual(c["brand_source_method"], "parent_brand_override")

    def test_torku_tahin_no_override(self):
        c = self._candidate("Torku Tahin 600 G", api_brand="Torku")
        self.assertEqual(c["brand"], "Torku")
        self.assertEqual(c["brand_source_method"], "api_metadata")
        self.assertIsNone(c["brand_raw"])

    def test_dynamic_brands_eti_wins_over_lifalif(self):
        """When dynamic list has both Eti and Lifalif, title-first token picks Eti."""
        c = self._candidate(
            "Eti Lifalif İnce Öğütülmüş Yulaf Ezmesi 350 G",
            api_brand=None,
            dynamic_brands=["Lifalif", "Eti"],
        )
        self.assertEqual(c["brand"], "Eti")

    def test_dynamic_brands_ulker_wins_over_cokokrem(self):
        """When dynamic list has both Ülker and Çokokrem, title-first token picks Ülker."""
        c = self._candidate(
            "Ülker Çokokrem Cam 650 G",
            api_brand=None,
            dynamic_brands=["Çokokrem", "Ülker"],
        )
        self.assertEqual(c["brand"], "Ülker")

    def test_brand_raw_stored_in_raw_source_payload_debug(self):
        """After parent_brand_override, brand_raw lands in raw_source_payload.debug."""
        from web_scraper.runner import _scored_insert_payload
        c = self._candidate("Eti Lifalif İnce Öğütülmüş Yulaf Ezmesi 350 G", api_brand="Lifalif")
        payload = _scored_insert_payload(c)
        debug = (payload.get("raw_source_payload") or {}).get("debug") or {}
        self.assertEqual(debug.get("brand_raw"), "Lifalif")
        self.assertEqual(debug.get("brand_source_method"), "parent_brand_override")


class StagingPayloadTest(unittest.TestCase):
    """_scored_insert_payload must not send unknown columns to PostgREST."""

    def _candidate_with_debug(self, **overrides) -> dict:
        base = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/test-product-p-abc",
            jsonld={"name": "Test Ürün 200 G"},
            meta={},
            sections={},
            image_candidates=[],
            category="kahvaltiliklar",
            ingredients_raw="şeker, kakao, fındık ezmesi, süt tozu",
            api_metadata={
                "api_brand": "Fropie",
                "api_name": "Test Ürün 200 G",
                "api_image_url": "https://img.migros.com.tr/img.jpg",
                "api_category": "kahvaltılıklar",
                "api_sku": "SKU123",
                "category_dynamic_brands": ["Fropie", "Nutella"],
            },
        )
        base.update(overrides)
        return base

    def test_payload_excludes_unknown_columns(self):
        """brand_source_method and ingredient_quality must not appear as top-level keys."""
        from web_scraper.runner import _scored_insert_payload, _STAGING_COLUMNS
        candidate = self._candidate_with_debug()
        payload = _scored_insert_payload(candidate)
        unknown = set(payload.keys()) - _STAGING_COLUMNS
        self.assertEqual(
            unknown, set(),
            f"Payload contains columns not in product_staging schema: {unknown}",
        )

    def test_debug_fields_stored_in_raw_source_payload(self):
        """brand_source_method and ingredient_quality land in raw_source_payload.debug."""
        from web_scraper.runner import _scored_insert_payload
        candidate = self._candidate_with_debug()
        payload = _scored_insert_payload(candidate)
        raw = payload.get("raw_source_payload") or {}
        debug = raw.get("debug") or {}
        self.assertIn("brand_source_method", debug)
        self.assertEqual(debug["brand_source_method"], "api_metadata")
        self.assertIn("ingredient_quality", debug)
        self.assertIn(debug["ingredient_quality"], (
            "ingredients_ok", "ingredients_suspicious",
            "ingredients_rejected_as_junk", "ingredients_missing",
        ))

    def test_staging_error_logs_response_body(self):
        """_log_staging_error writes status, response body, and payload keys to stderr."""
        import io
        from unittest.mock import MagicMock
        from web_scraper.runner import _log_staging_error

        mock_resp = MagicMock()
        mock_resp.status_code = 400
        mock_resp.text = '{"code":"PGRST204","message":"Could not find the brand_source_method column"}'
        payload = {"name": "Ürün", "brand_source_method": "api_metadata"}
        candidate = {"name": "Ürün", "source_url": "https://x/p-1"}

        captured = io.StringIO()
        import sys as _sys
        old_stderr = _sys.stderr
        _sys.stderr = captured
        try:
            _log_staging_error(mock_resp, payload, candidate, "POST")
        finally:
            _sys.stderr = old_stderr

        out = captured.getvalue()
        self.assertIn("400", out)
        self.assertIn("PGRST204", out)
        self.assertIn("brand_source_method", out)
        self.assertIn("Ürün", out)


class ImageSelectionTest(unittest.TestCase):
    """Front/main product image wins over back-label image."""

    def _make_candidate(self, front_url, back_url=None, api_url=None, only_back=False):
        """Build image pool and assemble candidate."""
        pool: list[image_scoring.ImageCandidate] = []
        if not only_back and front_url:
            pool.append(image_scoring.ImageCandidate(
                url=front_url, in_schema=True, gallery_index=0, source="detail_gallery"
            ))
        if back_url:
            pool.append(image_scoring.ImageCandidate(
                url=back_url, in_schema=True, gallery_index=1, source="detail_gallery"
            ))
        if only_back and front_url:
            pool.append(image_scoring.ImageCandidate(
                url=front_url, in_schema=True, gallery_index=0, source="detail_gallery"
            ))
        return runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/product-p-x",
            jsonld={"name": "Nestle Nesquik Kakaolu Buğday ve Mısır Gevreği 450 G"},
            meta={},
            sections={},
            image_candidates=pool,
            category="kahvaltiliklar",
            api_metadata={
                "api_brand": "Nestle",
                "api_name": None,
                "api_image_url": api_url,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": [],
            },
        )

    def test_front_image_wins_over_back(self):
        front = "https://img.migros.com.tr/front-product.jpg"
        back = "https://img.migros.com.tr/back-product.jpg"
        c = self._make_candidate(front, back)
        self.assertEqual(c["image_front_url"], front)

    def test_back_label_url_hint_penalizes_image(self):
        """A URL containing label hints loses to an unlabeled first-gallery image."""
        front = "https://img.migros.com.tr/product.jpg"
        label = "https://img.migros.com.tr/icindekiler-product.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=front, in_schema=True, gallery_index=0, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=label, in_schema=True, gallery_index=1, source="detail_gallery"
            ),
        ]
        _, scored = image_scoring.pick_best_image(pool, name="Test")
        front_score = next(c.score for c in scored if c.url == front)
        label_score = next(c.score for c in scored if c.url == label)
        self.assertGreater(front_score, label_score)

    def test_api_primary_image_wins_over_gallery_second(self):
        """API primary image (front packshot from category listing) wins over a
        second gallery image that might be the back."""
        api_url = "https://img.migros.com.tr/api-front.jpg"
        second = "https://img.migros.com.tr/gallery-second.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=second, in_schema=True, gallery_index=1, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=api_url,
                in_schema=True,
                is_api_primary=True,
                gallery_index=0,
                source="api_primary",
            ),
        ]
        best, _ = image_scoring.pick_best_image(pool, name="Test")
        self.assertIsNotNone(best)
        self.assertEqual(best.url, api_url)

    def test_gallery_first_beats_gallery_second(self):
        """First gallery image (index 0) scores higher than second (index 1)."""
        first = "https://img.migros.com.tr/img1.jpg"
        second = "https://img.migros.com.tr/img2.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=first, in_schema=True, gallery_index=0, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=second, in_schema=True, gallery_index=1, source="detail_gallery"
            ),
        ]
        best, scored = image_scoring.pick_best_image(pool, name="Test")
        self.assertEqual(best.url, first)
        first_score = next(c.score for c in scored if c.url == first)
        second_score = next(c.score for c in scored if c.url == second)
        self.assertGreater(first_score, second_score)

    def test_only_back_image_used_as_fallback_with_role(self):
        """When only a back/label image exists, it is kept only as a low-confidence fallback."""
        back = "https://img.migros.com.tr/icindekiler-label.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=back, in_schema=True, gallery_index=0, source="detail_gallery"
            ),
        ]
        c = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/product-p-x",
            jsonld={"name": "Ürün"},
            meta={},
            sections={},
            image_candidates=pool,
            category="kahvaltiliklar",
            api_metadata={
                "api_brand": None, "api_name": None, "api_image_url": None,
                "api_category": None, "api_sku": None, "category_dynamic_brands": [],
            },
        )
        self.assertEqual(c["image_front_url"], back)
        self.assertEqual(c["image_front_role"], "ingredients_label")
        self.assertEqual(c["image_quality"], "only_back_available")

    def test_label_image_stored_separately(self):
        """A back/label image is preserved in image_ingredients_url when a front exists."""
        front = "https://img.migros.com.tr/front.jpg"
        label = "https://img.migros.com.tr/icindekiler-label.jpg"
        c = self._make_candidate(front, label)
        self.assertEqual(c["image_front_url"], front)
        self.assertEqual(c["image_ingredients_url"], label)

    def test_nestle_nesquik_front_image_selected(self):
        """Nestle Nesquik gallery: front (index 0) wins over back label (index 1)."""
        front = "https://img.migros.com.tr/nesquik-front.jpg"
        back = "https://img.migros.com.tr/nesquik-back.jpg"
        c = self._make_candidate(front, back, api_url=front)
        self.assertEqual(c["image_front_url"], front)
        self.assertEqual(c["brand"], "Nestle")  # brand fix still works
        self.assertEqual(c["image_front_role"], "front")
        self.assertEqual(c["image_quality"], "front_selected")

    def test_nutrition_label_does_not_replace_front(self):
        front = "https://img.migros.com.tr/front-packshot.jpg"
        nutrition = "https://img.migros.com.tr/besin-degerleri.jpg"
        c = self._make_candidate(front, nutrition, api_url=front)
        self.assertEqual(c["image_front_url"], front)
        self.assertEqual(c["image_front_role"], "front")
        self.assertEqual(c["image_quality"], "front_selected")


class MigrosDetailImageSelectionTest(unittest.TestCase):
    """Tests for the gallery-first score guard and URL normalization fixes.

    Regression suite: a Migros detail page may render non-product UI icons as
    the first gallery image (gallery_index=0).  Those icons score negative
    (because their URL contains 'icon' → -40 bad-URL penalty) but previously
    bypassed the score guard in select_primary_image's detail_first branch.
    """

    # ── core regression: icon at gallery_index=0 must not win ──────────────

    def test_icon_at_gallery_first_does_not_beat_positive_scoring_cdn_image(self):
        """gallery_index=0 icon (score < 0) must not be selected over a CDN image."""
        icon = image_scoring.ImageCandidate(
            url="https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
            in_gallery=True,
            gallery_index=0,
            source="detail_gallery",
        )
        cdn = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg",
            in_gallery=True,
            gallery_index=1,
            source="detail_gallery",
        )
        selection = image_scoring.select_primary_image([icon, cdn])
        self.assertIsNotNone(selection.selected)
        self.assertEqual(selection.selected.url, cdn.url)

    def test_ne_pisirsem_icon_is_rejected_in_favor_of_migrosone_cdn_image(self):
        """Exact replica of the failing Mutlu Spagetti Makarna 500 G scenario."""
        icon_url = "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp"
        cdn_url = "https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=icon_url, in_gallery=True, gallery_index=0, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=cdn_url, in_gallery=True, gallery_index=1, source="detail_gallery"
            ),
        ]
        selection = image_scoring.select_primary_image(pool, name="Mutlu Spagetti Makarna 500 G")
        self.assertIsNotNone(selection.selected, "A usable image must be found")
        self.assertEqual(selection.selected.url, cdn_url)
        self.assertNotEqual(selection.selected.url, icon_url)

    def test_icon_scores_negative_cdn_scores_positive(self):
        """Score sanity: icon URL should score < 0, CDN image should score > 0."""
        icon = image_scoring.ImageCandidate(
            url="https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
            in_gallery=True, gallery_index=0, source="detail_gallery",
        )
        cdn = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg",
            in_gallery=True, gallery_index=1, source="detail_gallery",
        )
        _, scored = image_scoring.pick_best_image([icon, cdn])
        icon_scored = next(c for c in scored if "ne-pisirsem" in c.url)
        cdn_scored = next(c for c in scored if "migrosone.com" in c.url)
        self.assertLess(icon_scored.score, 0)
        self.assertGreater(cdn_scored.score, 0)

    def test_api_primary_still_wins_over_gallery_icon(self):
        """api_primary image must still be preferred over any gallery image."""
        api_url = "https://images.migrosone.com/sanalmarket/product/1234/1234-front.jpg"
        icon_url = "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp"
        pool = [
            image_scoring.ImageCandidate(
                url=icon_url, in_gallery=True, gallery_index=0, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=api_url, is_api_primary=True, in_schema=True,
                gallery_index=0, source="api_primary"
            ),
        ]
        selection = image_scoring.select_primary_image(pool)
        self.assertIsNotNone(selection.selected)
        self.assertEqual(selection.selected.url, api_url)

    # ── URL normalization ────────────────────────────────────────────────────

    def test_root_relative_url_normalized_to_absolute_https(self):
        """A root-relative image URL must become an absolute HTTPS URL."""
        from web_scraper.source_adapters.migros_adapter import _normalize_image_url
        result = _normalize_image_url("/sanalmarket/product/image.jpg")
        self.assertEqual(result, "https://www.migros.com.tr/sanalmarket/product/image.jpg")

    def test_protocol_relative_url_normalized_to_https(self):
        """A protocol-relative URL must become HTTPS."""
        from web_scraper.source_adapters.migros_adapter import _normalize_image_url
        result = _normalize_image_url("//images.migrosone.com/product/img.jpg")
        self.assertEqual(result, "https://images.migrosone.com/product/img.jpg")

    def test_absolute_https_url_unchanged(self):
        """An already-absolute HTTPS URL must pass through unchanged."""
        from web_scraper.source_adapters.migros_adapter import _normalize_image_url
        url = "https://images.migrosone.com/sanalmarket/product/5039483/img.jpg"
        self.assertEqual(_normalize_image_url(url), url)

    def test_whitespace_stripped_during_normalization(self):
        """Leading/trailing whitespace must be stripped."""
        from web_scraper.source_adapters.migros_adapter import _normalize_image_url
        result = _normalize_image_url("  //images.migrosone.com/img.jpg  ")
        self.assertEqual(result, "https://images.migrosone.com/img.jpg")

    # ── staging payload contains the correct image URL ───────────────────────

    def test_staging_payload_includes_cdn_image_not_icon(self):
        """After the fix, assemble_candidate must store the CDN image, not the icon."""
        icon_url = "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp"
        cdn_url = "https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=icon_url, in_gallery=True, gallery_index=0, source="detail_gallery"
            ),
            image_scoring.ImageCandidate(
                url=cdn_url, in_gallery=True, gallery_index=1, source="detail_gallery"
            ),
        ]
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/mutlu-spagetti-makarna-500-g-p-d12345",
            jsonld={"name": "Mutlu Spagetti Makarna 500 G"},
            meta={},
            sections={},
            image_candidates=pool,
            category="makarna",
            api_metadata={
                "api_brand": "Mutlu",
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": [],
            },
        )
        # Candidate dict uses image_front_url internally (the CDN URL, not the icon).
        self.assertEqual(candidate["image_front_url"], cdn_url)
        self.assertNotEqual(candidate.get("image_front_url"), icon_url)
        # DB payload writes image_front_url (primary) and image_url (alias).
        from web_scraper.runner import _scored_insert_payload
        payload = _scored_insert_payload(candidate)
        self.assertEqual(payload.get("image_front_url"), cdn_url)
        self.assertEqual(payload.get("image_url"), cdn_url)
        self.assertNotIn(icon_url, payload.values(),
                         "icon URL must not reach any staging DB column")

    def test_candidate_image_url_survives_serialization(self):
        """image_front_url in candidate dict and image_url in staging payload are consistent."""
        cdn_url = "https://images.migrosone.com/sanalmarket/product/5039483/5039483-26169b-1650x1650.jpg"
        pool = [
            image_scoring.ImageCandidate(
                url=cdn_url, in_gallery=True, gallery_index=0, source="detail_gallery"
            ),
        ]
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/mutlu-penne-makarna-500-g-p-d12346",
            jsonld={"name": "Mutlu Penne Makarna 500 G"},
            meta={},
            sections={},
            image_candidates=pool,
            category="makarna",
            api_metadata={
                "api_brand": "Mutlu",
                "api_name": None,
                "api_image_url": None,
                "api_category": None,
                "api_sku": None,
                "category_dynamic_brands": [],
            },
        )
        # Candidate internal key preserved.
        self.assertEqual(candidate["image_front_url"], cdn_url)
        # image_best_score must be positive for a valid CDN image
        raw = candidate.get("raw_source_payload") or {}
        self.assertGreater(raw.get("image_best_score", 0), 0)
        # Staging DB payload sets image_front_url (primary) and image_url (alias).
        from web_scraper.runner import _scored_insert_payload
        payload = _scored_insert_payload(candidate)
        self.assertEqual(payload.get("image_front_url"), cdn_url)
        self.assertEqual(payload.get("image_url"), cdn_url)

    # ── spec section 6, items 1-8 ────────────────────────────────────────────

    def test_image_front_url_writes_to_both_staging_columns(self):
        """Spec item 1: candidate image_front_url writes image_front_url (primary)
        and image_url (compatibility alias) in the staging payload."""
        from web_scraper.runner import _scored_insert_payload
        cdn_url = "https://images.migrosone.com/sanalmarket/product/9999/img.jpg"
        candidate = {"name": "Ürün", "source": "web_scraper:migros",
                     "image_front_url": cdn_url, "quality_score": 0, "missing_fields": [], "status": "pending"}
        payload = _scored_insert_payload(candidate)
        self.assertEqual(payload.get("image_front_url"), cdn_url)
        self.assertEqual(payload.get("image_url"), cdn_url)

    def test_image_front_url_wins_over_image_url_in_selection(self):
        """Spec item 3: image_front_url is preferred over image_url by _selected_front_image_url."""
        from web_scraper.runner import _selected_front_image_url
        primary = "https://images.migrosone.com/sanalmarket/product/9999/primary.jpg"
        alias = "https://images.migrosone.com/sanalmarket/product/9999/alias.jpg"
        candidate = {"image_front_url": primary, "image_url": alias}
        self.assertEqual(_selected_front_image_url(candidate), primary)

    def test_og_image_fallback_when_no_front_url(self):
        """Spec item 4: raw_source_payload.meta.og_image used as fallback."""
        from web_scraper.runner import _scored_insert_payload, _selected_front_image_url
        og_url = "https://images.migrosone.com/sanalmarket/product/1234/og.jpg"
        candidate = {
            "name": "Ürün", "source": "web_scraper:migros",
            "raw_source_payload": {"meta": {"og_image": og_url}},
            "quality_score": 0, "missing_fields": [], "status": "pending",
        }
        selected = _selected_front_image_url(candidate)
        self.assertEqual(selected, og_url)
        payload = _scored_insert_payload(candidate)
        self.assertEqual(payload.get("image_front_url"), og_url)
        self.assertEqual(payload.get("image_url"), og_url)

    def test_icon_and_logo_urls_rejected(self):
        """Spec item 6: junk/icon/logo URLs are rejected and not written to staging."""
        from web_scraper.runner import _scored_insert_payload, _selected_front_image_url
        for junk in [
            "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
            "https://www.migros.com.tr/assets/logos/migros.png",
            "https://www.migros.com.tr/assets/icons/migroskop.webp",
            "https://example.com/assets/logos/brand.svg",
            "https://example.com/blindlook-logo.jpg",
        ]:
            with self.subTest(junk=junk):
                candidate = {"name": "Ürün", "source": "web_scraper:migros",
                             "image_front_url": junk,
                             "quality_score": 0, "missing_fields": [], "status": "pending"}
                selected = _selected_front_image_url(candidate)
                self.assertIsNone(selected, f"junk URL must be rejected: {junk}")
                payload = _scored_insert_payload(candidate)
                self.assertIsNone(payload.get("image_front_url"),
                                  f"junk URL must not reach staging DB: {junk}")
                self.assertIsNone(payload.get("image_url"),
                                  f"junk URL alias must not reach staging DB: {junk}")

    def test_missing_barcode_does_not_drop_image_url(self):
        """Spec item 7: no barcode in candidate must not remove image_front_url from payload."""
        from web_scraper.runner import _scored_insert_payload
        cdn_url = "https://images.migrosone.com/sanalmarket/product/9999/img.jpg"
        candidate = {
            "name": "Ürün", "source": "web_scraper:migros",
            "image_front_url": cdn_url,
            # no barcode, no ingredients
            "quality_score": 0, "missing_fields": ["barcode", "ingredients"], "status": "pending",
        }
        payload = _scored_insert_payload(candidate)
        self.assertEqual(payload.get("image_front_url"), cdn_url)
        self.assertEqual(payload.get("image_url"), cdn_url)


class MigrosImageRepairTest(unittest.TestCase):
    class _FakeResponse:
        def __init__(self, payload=None):
            self.payload = payload or []

        def raise_for_status(self):
            return None

        def json(self):
            return self.payload

    def _image_report(self, *candidates):
        return runner.select_product_images(list(candidates), name="Lay's Klasik Mega Boy 193 G", brand="Lay's")

    def test_bulk_products_fetch_all_rows_without_db_suspicious_filter(self):
        """fetch_all_migros_rows_for_table for products: no or/ilike filter, selects image_url."""
        with patch.object(migros_image_fix.requests, "get") as get:
            get.return_value = self._FakeResponse([])
            migros_image_fix.fetch_all_migros_rows_for_table(
                "https://supabase.test", "service-key", "products",
                source="web_scraper:migros",
            )
        for call in get.call_args_list:
            params = call.kwargs.get("params", {})
            self.assertNotIn("or", params, "no or filter in bulk fetch")
            self.assertIn("image_url", params.get("select", ""),
                          "select must include image_url for products table")

    def test_bulk_staging_fetch_all_rows_selects_image_url(self):
        """fetch_all_migros_rows_for_table for product_staging: selects image_url (aligned with products)."""
        with patch.object(migros_image_fix.requests, "get") as get:
            get.return_value = self._FakeResponse([])
            migros_image_fix.fetch_all_migros_rows_for_table(
                "https://supabase.test", "service-key", "product_staging",
                source="web_scraper:migros",
            )
        for call in get.call_args_list:
            params = call.kwargs.get("params", {})
            self.assertIn("image_url", params.get("select", ""),
                          "product_staging select must include image_url")
        self.assertEqual(migros_image_fix.STAGING_SPEC.image_field, "image_url")

    def test_targeted_query_still_uses_only_source_url_without_bulk_filter(self):
        with patch.object(migros_image_fix.requests, "get") as get:
            get.return_value = self._FakeResponse([])

            migros_image_fix.fetch_target_rows(
                "https://supabase.test",
                "service-key",
                spec=migros_image_fix.PRODUCT_SPEC,
                source="web_scraper:migros",
                limit=100,
                only_source_url="https://www.migros.com.tr/lays-p-x",
                fix_suspicious_only=True,
            )

        params = get.call_args.kwargs["params"]
        self.assertEqual(
            params["source_url"],
            "eq.https://www.migros.com.tr/lays-p-x",
        )
        self.assertEqual(params["limit"], "1")
        self.assertNotIn("or", params)

    def test_dry_run_updates_even_when_current_image_looks_front(self):
        front = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_1.jpg",
            in_gallery=True,
            gallery_index=0,
            source="detail_gallery",
        )
        back = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_arka.jpg",
            in_gallery=True,
            gallery_index=1,
            source="detail_gallery",
        )
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": "https://cdn.example.com/front-lays-klasik-mega-boy-193-g-packshot-800x800.jpg",
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-x",
        }
        decision = migros_image_fix.plan_image_update(row, self._image_report(front, back))
        self.assertEqual(decision.current_image_role, "front")
        self.assertEqual(decision.status, "would_update")
        self.assertEqual(decision.new_image_url, front.url)

    def test_dry_run_reports_would_update_when_current_image_is_back(self):
        front = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_1.jpg",
            in_gallery=True,
            gallery_index=0,
            source="detail_gallery",
        )
        back = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_arka.jpg",
            in_gallery=True,
            gallery_index=1,
            source="detail_gallery",
        )
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": back.url,
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-x",
        }
        decision = migros_image_fix.plan_image_update(row, self._image_report(front, back))
        self.assertEqual(decision.status, "would_update")
        self.assertEqual(decision.new_image_url, front.url)
        self.assertEqual(decision.current_image_role, "back_label")
        self.assertEqual(decision.new_image_role, "front")

    def test_dry_run_prefers_category_card_when_shared_image_report_points_to_bad_gallery_first(self):
        image_report = {
            "image_front_url": "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
            "image_front_role": "front",
            "image_best_score": -8,
            "image_confidence": "high",
            "image_candidates": [
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05082036/05082036_yan-c40542-1650x1650.jpg",
                    "index": 2,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 32,
                },
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05082036/05082036-915572-1650x1650.jpg",
                    "index": None,
                    "source": "category_card",
                    "role": "unknown",
                    "score": 22,
                },
                {
                    "url": "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
                    "index": 0,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": -8,
                },
            ],
        }
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": "https://images.migrosone.com/sanalmarket/product/05082036/05082036_yan-c40542-1650x1650.jpg",
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-4d8bb4",
        }
        decision = migros_image_fix.plan_image_update(row, image_report)
        self.assertEqual(decision.status, "would_update")
        self.assertEqual(
            decision.new_image_url,
            "https://images.migrosone.com/sanalmarket/product/05082036/05082036-915572-1650x1650.jpg",
        )
        self.assertEqual(decision.selected_front_source, "category_card")

    def test_dry_run_skips_when_current_image_is_already_front(self):
        front = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_1.jpg",
            in_gallery=True,
            gallery_index=0,
            source="detail_gallery",
        )
        back = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_arka.jpg",
            in_gallery=True,
            gallery_index=1,
            source="detail_gallery",
        )
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": front.url,
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-x",
        }
        decision = migros_image_fix.plan_image_update(row, self._image_report(front, back))
        self.assertEqual(decision.status, "skipped_already_front")
        self.assertEqual(decision.reason, "current image_url equals selected front image")

    def test_only_back_available_does_not_replace_existing_image(self):
        back = image_scoring.ImageCandidate(
            url="https://images.migrosone.com/sanalmarket/product/05099267/05099267_arka.jpg",
            in_gallery=True,
            gallery_index=0,
            source="detail_gallery",
        )
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": "https://cdn.example.com/front-existing.jpg",
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-x",
        }
        decision = migros_image_fix.plan_image_update(row, self._image_report(back))
        self.assertEqual(decision.status, "skipped_low_confidence")

    def test_no_selected_front_returns_skipped_no_images_found(self):
        row = {
            "id": "p1",
            "name": "Lay's Klasik Mega Boy 193 G",
            "brand": "Lay's",
            "image_url": "https://cdn.example.com/back.jpg",
            "source_url": "https://www.migros.com.tr/lays-klasik-mega-boy-193-g-p-x",
        }
        decision = migros_image_fix.plan_image_update(row, None)
        self.assertEqual(decision.status, "skipped_no_images_found")

    def test_image_only_patch_updates_only_image_url_and_updated_at(self):
        patch = migros_image_fix.build_image_only_patch(
            "https://images.migrosone.com/sanalmarket/product/05099267/05099267_1.jpg"
        )
        self.assertEqual(set(patch.keys()), {"image_url", "updated_at"})

    def test_staging_image_only_patch_updates_only_front_image_source_and_updated_at(self):
        patch = migros_image_fix.build_image_only_patch(
            "https://images.migrosone.com/sanalmarket/product/05099267/05099267_1.jpg",
            image_field="image_front_url",
            image_source="web_scraper:migros",
        )
        self.assertEqual(
            set(patch.keys()),
            {"image_front_url", "image_source", "updated_at"},
        )
        self.assertNotIn("image_url", patch)

    def test_staging_repair_uses_image_url_column(self):
        image_report = {
            "image_candidates": [
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05080145/05080145-abc-1650x1650.jpg",
                    "index": 0,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 38,
                },
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05080145/05080145_2-abc-1650x1650.jpg",
                    "index": 1,
                    "source": "detail_gallery",
                    "role": "back_label",
                    "score": -5,
                },
            ]
        }
        row = {
            "id": "s1",
            "name": "Migros Ürünü",
            "brand": "Migros",
            "image_url": "https://images.migrosone.com/sanalmarket/product/05080145/05080145_2-abc-1650x1650.jpg",
            "source_url": "https://www.migros.com.tr/migros-urunu-p-x",
        }

        decision = migros_image_fix.plan_image_update(
            row,
            image_report,
            spec=migros_image_fix.STAGING_SPEC,
            require_current_suspicious=True,
        )

        self.assertEqual(decision.status, "would_update")
        self.assertEqual(
            decision.patch["image_url"],
            "https://images.migrosone.com/sanalmarket/product/05080145/05080145-abc-1650x1650.jpg",
        )
        self.assertEqual(decision.patch["image_source"], "web_scraper:migros")
        self.assertNotIn("image_front_url", decision.patch)

    def test_suspicious_yan_candidate_is_not_selected_when_clean_front_exists(self):
        image_report = {
            "image_candidates": [
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05089460/05089460_yan-abc-1650x1650.jpg",
                    "index": 0,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 45,
                },
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05089460/05089460-abc-1650x1650.jpg",
                    "index": 1,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 25,
                },
            ]
        }
        row = {
            "id": "p1",
            "name": "Migros Ürünü",
            "brand": "Migros",
            "image_url": "https://images.migrosone.com/sanalmarket/product/05089460/05089460_yan-abc-1650x1650.jpg",
            "source_url": "https://www.migros.com.tr/migros-urunu-p-x",
        }

        decision = migros_image_fix.plan_image_update(
            row,
            image_report,
            require_current_suspicious=True,
        )

        self.assertEqual(decision.status, "would_update")
        self.assertEqual(
            decision.new_image_url,
            "https://images.migrosone.com/sanalmarket/product/05089460/05089460-abc-1650x1650.jpg",
        )

    def test_fix_suspicious_only_skips_clean_current_image_before_fetch_decision(self):
        row = {
            "id": "p1",
            "name": "Migros Ürünü",
            "brand": "Migros",
            "image_url": "https://images.migrosone.com/sanalmarket/product/05089460/05089460-abc-1650x1650.jpg",
            "source_url": "https://www.migros.com.tr/migros-urunu-p-x",
        }

        decision = migros_image_fix.plan_image_update(
            row,
            None,
            require_current_suspicious=True,
        )

        self.assertEqual(decision.status, "skipped_not_suspicious")


class MigrosNameCleaningTest(unittest.TestCase):
    """og:title must be the authoritative name source; brand prefix must survive."""

    # ── clean_title preserves brand prefix ────────────────────────────────────

    def test_otto_dried_fruits_brand_prefix_preserved(self):
        """'Otto' brand prefix must survive; only ' | Migros' retailer suffix is stripped."""
        result = runner.clean_title("Otto Dried Fruits Kuru İncir Büyük 150G | Migros")
        self.assertEqual(result, "Otto Dried Fruits Kuru İncir Büyük 150G")

    def test_lays_klasik_brand_prefix_preserved(self):
        """'Lay's' brand prefix must survive; only ' - Migros' retailer suffix is stripped."""
        result = runner.clean_title("Lay's Klasik Mega Boy 193 G - Migros")
        self.assertEqual(result, "Lay's Klasik Mega Boy 193 G")

    def test_eti_lifalif_brand_prefix_preserved(self):
        """'Eti Lifalif' — no retailer suffix; full string returned unchanged."""
        result = runner.clean_title("Eti Lifalif Yulaf Ezmesi 500 G")
        self.assertEqual(result, "Eti Lifalif Yulaf Ezmesi 500 G")

    def test_ulker_cokokrem_brand_prefix_preserved(self):
        """'Ülker Çokokrem' brand prefix must survive; only ' | Migros' is stripped."""
        result = runner.clean_title("Ülker Çokokrem Kakaolu Fındık Kreması 400 G | Migros")
        self.assertEqual(result, "Ülker Çokokrem Kakaolu Fındık Kreması 400 G")

    def test_clean_title_collapses_spaces_without_removing_brand_tokens(self):
        """clean_title collapses repeated whitespace but never strips brand or product-line words."""
        result = runner.clean_title("  Lay's  Klasik  Süper  Boy  125G  ")
        self.assertIsNotNone(result)
        self.assertTrue(
            result.startswith("Lay's"),
            f"Brand prefix was stripped; got {result!r}",
        )
        self.assertNotIn("  ", result)  # no double-spaces in output

    # ── og:title priority recovers brand prefix lost in JSON-LD name ──────────

    def test_og_title_priority_recovers_brand_prefix_over_jsonld_name(self):
        """assemble_candidate: when og:title carries the brand and JSON-LD name omits it,
        the candidate name must come from og:title (with retailer suffix stripped)."""
        candidate = runner.assemble_candidate(
            source_id="migros",
            url="https://www.migros.com.tr/otto-kuru-incir-p-abc",
            jsonld={"name": "Dried Fruits Kuru İncir Büyük 150G"},
            meta={"og_title": "Otto Dried Fruits Kuru İncir Büyük 150G | Migros"},
            sections={},
            image_candidates=[],
            category="kuruyemis",
        )
        self.assertEqual(
            candidate["name"],
            "Otto Dried Fruits Kuru İncir Büyük 150G",
        )
        # Must not be the brand-stripped JSON-LD value.
        self.assertNotEqual(candidate["name"], "Dried Fruits Kuru İncir Büyük 150G")


_BASE_URL = "https://example.supabase.co"
_KEY = "test-service-key"
_SOURCE = "web_scraper:migros"


class BulkSuspiciousFilterTest(unittest.TestCase):
    """Tests for the Python-side suspicious-row filtering approach."""

    def _fake_resp(self, rows):
        resp = MagicMock()
        resp.raise_for_status.return_value = None
        resp.json.return_value = rows
        return resp

    def _row(self, row_id, image_url, *, table="products",
             updated_at="2024-01-01T00:00:00Z", source_url=None):
        image_field = "image_url" if table == "products" else "image_front_url"
        return {
            "id": row_id,
            "name": f"Product {row_id}",
            "brand": "TestBrand",
            image_field: image_url,
            "source": _SOURCE,
            "source_url": source_url or f"https://www.migros.com.tr/p-{row_id}",
            "category_tags": None,
            "updated_at": updated_at,
        }

    # ── is_suspicious_image_url ───────────────────────────────────────────────

    def test_is_suspicious_url_finds_underscore_2_dash(self):
        url = "https://images.migrosone.com/product/11018028_2-191052-1650x1650.jpg"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    def test_is_suspicious_url_finds_yan(self):
        url = "https://images.migrosone.com/product/pinar-salam_yan-1650x1650.jpg"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    def test_is_suspicious_url_ignores_underscore_1_dash(self):
        """The normal Migros front-image pattern must NOT be flagged suspicious."""
        url = "https://images.migrosone.com/sanalmarket/product/07030852/07030852-5645c5-1650x1650.jpg"
        self.assertFalse(migros_image_fix.is_suspicious_image_url(url))

    # ── fetch_suspicious_rows_python_filtered — correct image field ───────────

    def test_python_filtered_products_selects_image_url_not_image_front_url(self):
        """fetch_suspicious_rows_python_filtered for 'products' selects image_url."""
        with patch("requests.get", return_value=self._fake_resp([])) as mock_get:
            migros_image_fix.fetch_suspicious_rows_python_filtered(
                _BASE_URL, _KEY, "products", 10, source=_SOURCE
            )
        for call in mock_get.call_args_list:
            select = call.kwargs.get("params", {}).get("select", "")
            self.assertIn("image_url", select)
            self.assertNotIn("image_front_url", select)

    def test_python_filtered_staging_selects_image_url(self):
        """fetch_suspicious_rows_python_filtered for 'product_staging' selects image_url (aligned with products)."""
        with patch("requests.get", return_value=self._fake_resp([])) as mock_get:
            migros_image_fix.fetch_suspicious_rows_python_filtered(
                _BASE_URL, _KEY, "product_staging", 10, source=_SOURCE
            )
        for call in mock_get.call_args_list:
            select = call.kwargs.get("params", {}).get("select", "")
            self.assertIn("image_url", select)

    def test_staging_spec_select_fields_references_image_url(self):
        """STAGING_SPEC.select_fields contains image_url (not image_front_url)."""
        select = migros_image_fix.STAGING_SPEC.select_fields
        self.assertIn("image_url", select)
        self.assertNotIn("image_front_url", select)

    # ── limit is applied AFTER Python filtering ───────────────────────────────

    def test_limit_applied_after_python_suspicious_filtering(self):
        """limit is enforced on the suspicious subset, not on the raw DB page."""
        suspicious_rows = [
            self._row(f"uuid-s{i}",
                      f"https://images.migrosone.com/sanalmarket/product/11018028/11018028_2-{i}abc-1650x1650.jpg",
                      updated_at=f"2024-01-{i+1:02d}T00:00:00Z")
            for i in range(5)
        ]
        clean_row = self._row(
            "uuid-clean",
            "https://images.migrosone.com/sanalmarket/product/07030852/07030852-5645c5-1650x1650.jpg",
        )
        with patch("requests.get",
                   return_value=self._fake_resp(suspicious_rows + [clean_row])):
            result = migros_image_fix.fetch_suspicious_rows_python_filtered(
                _BASE_URL, _KEY, "products", 2, source=_SOURCE
            )
        self.assertEqual(len(result), 2)
        for row in result:
            self.assertTrue(
                migros_image_fix.is_suspicious_image_url(row.get("image_url")),
                f"Non-suspicious row in result: {row.get('image_url')}",
            )

    # ── targeted mode bypasses Python bulk filter ─────────────────────────────

    def test_targeted_mode_bypasses_python_bulk_filter(self):
        """With only_source_url, fetch_target_rows issues a single targeted query."""
        with patch("requests.get", return_value=self._fake_resp([])) as mock_get:
            migros_image_fix.fetch_target_rows(
                _BASE_URL, _KEY,
                spec=migros_image_fix.PRODUCT_SPEC,
                source=_SOURCE,
                limit=1,
                only_source_url="https://www.migros.com.tr/lays-p-x",
                fix_suspicious_only=True,
            )
        self.assertEqual(mock_get.call_count, 1)
        params = mock_get.call_args.kwargs.get("params", {})
        self.assertEqual(params["source_url"], "eq.https://www.migros.com.tr/lays-p-x")


class NonProductAssetFilterTest(unittest.TestCase):
    """Tests for Task-3: is_suspicious_image_url detects Migros non-product assets."""

    # ── Explicit-signal detection ─────────────────────────────────────────────

    def test_ne_pisirsem_url_is_suspicious(self):
        """ne-pisirsem icon URL must be flagged as suspicious."""
        url = "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    def test_assets_icons_path_is_suspicious(self):
        """/assets/icons/ path on migros.com.tr must be flagged as suspicious."""
        url = "https://www.migros.com.tr/assets/icons/some-icon.png"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    def test_assets_logos_path_is_suspicious(self):
        """/assets/logos/ path on migros.com.tr must be flagged as suspicious."""
        url = "https://www.migros.com.tr/assets/logos/migros-logo.svg"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    # ── Migros-domain CDN check ───────────────────────────────────────────────

    def test_sanalmarket_pweb_app_assets_is_suspicious(self):
        """assets.migrosone.com (not images.migrosone.com/sanalmarket/product/) is suspicious."""
        url = "https://assets.migrosone.com/sanalmarket-pweb-app/assets/icons/chef.png"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    def test_valid_migros_product_cdn_url_is_not_suspicious(self):
        """A clean images.migrosone.com/sanalmarket/product/ URL must NOT be suspicious."""
        url = "https://images.migrosone.com/sanalmarket/product/07030852/07030852-5645c5-1650x1650.jpg"
        self.assertFalse(migros_image_fix.is_suspicious_image_url(url))

    def test_valid_migros_cdn_with_back_pattern_is_still_suspicious(self):
        """Even a proper CDN URL is suspicious when it contains a back/side pattern."""
        url = "https://images.migrosone.com/sanalmarket/product/11018028/11018028_2-191052-1650x1650.jpg"
        self.assertTrue(migros_image_fix.is_suspicious_image_url(url))

    # ── STAGING_SPEC uses image_url (aligned with products table) ─────────────

    def test_staging_spec_image_field_is_image_url(self):
        """STAGING_SPEC.image_field must be image_url (same column name as products)."""
        self.assertEqual(migros_image_fix.STAGING_SPEC.image_field, "image_url")

    # ── _select_repair_front_candidate never picks asset URLs ────────────────

    def test_select_repair_never_picks_ne_pisirsem_candidate(self):
        """_select_repair_front_candidate must return None when the only candidate is ne-pisirsem.webp."""
        image_report = {
            "image_candidates": [
                {
                    "url": "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
                    "index": 0,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 30,
                }
            ]
        }
        result = migros_image_fix._select_repair_front_candidate(image_report)
        self.assertIsNone(result)

    def test_select_repair_never_picks_assets_logos_candidate(self):
        """_select_repair_front_candidate must return None for /assets/logos/ URL."""
        image_report = {
            "image_candidates": [
                {
                    "url": "https://www.migros.com.tr/assets/logos/migros-logo.svg",
                    "index": 0,
                    "source": "api_primary",
                    "role": "front",
                    "score": 40,
                }
            ]
        }
        result = migros_image_fix._select_repair_front_candidate(image_report)
        self.assertIsNone(result)

    # ── plan_image_update treats ne-pisirsem as suspicious ───────────────────

    def test_targeted_nazar_staging_row_repaired_when_front_image_exists(self):
        """Nazar staging row with ne-pisirsem.webp image is repaired when clean CDN image found."""
        image_report = {
            "image_candidates": [
                {
                    "url": "https://images.migrosone.com/sanalmarket/product/05082060/05082060-abc-1650x1650.jpg",
                    "index": 0,
                    "source": "detail_gallery",
                    "role": "front",
                    "score": 35,
                }
            ]
        }
        row = {
            "id": "nazar-uuid",
            "name": "Nazar Sakız",
            "brand": None,
            "image_url": "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
            "source_url": "https://www.migros.com.tr/nazar-sakiz-p-abc",
        }
        decision = migros_image_fix.plan_image_update(
            row,
            image_report,
            spec=migros_image_fix.STAGING_SPEC,
            require_current_suspicious=True,
        )
        self.assertEqual(decision.status, "would_update")
        self.assertEqual(
            decision.new_image_url,
            "https://images.migrosone.com/sanalmarket/product/05082060/05082060-abc-1650x1650.jpg",
        )

    def test_kinder_milka_toblerone_ne_pisirsem_treated_as_suspicious(self):
        """Kinder/Milka/Toblerone staging rows with ne-pisirsem.webp are NOT skipped as non-suspicious."""
        for product_name in [
            "Kinder Mini Schokolade 120G",
            "Milka Fındıklı Çikolata 300G",
            "Toblerone Sütlü Çikolata 200G",
        ]:
            row = {
                "id": f"test-{product_name.split()[0].lower()}",
                "name": product_name,
                "brand": None,
                "image_url": "https://www.migros.com.tr/assets/icons/ne-pisirsem.webp",
                "source_url": "https://www.migros.com.tr/product-p-abc",
            }
            decision = migros_image_fix.plan_image_update(
                row,
                None,
                spec=migros_image_fix.STAGING_SPEC,
                require_current_suspicious=True,
            )
            self.assertNotEqual(
                decision.status,
                "skipped_not_suspicious",
                f"{product_name}: ne-pisirsem.webp must be treated as suspicious",
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
