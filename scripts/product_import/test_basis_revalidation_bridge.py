#!/usr/bin/env python3
"""Tests for basis_revalidation_bridge.py — mocks the HTTP fetch entirely;
never performs a live network call."""
from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from web_scraper.base import FetchResult  # noqa: E402

import basis_revalidation_bridge as bridge  # noqa: E402


def _html(basis_header: str = "100 g", barcode: str = "8690000000123") -> str:
    return f"""
    <html><head>
    <script type="application/ld+json">
    {{"@type": "Product", "name": "Test Ürün", "gtin13": "{barcode}"}}
    </script>
    </head><body>
    <table>
      <tr><th>Besin Değeri</th><td class="value">{basis_header}</td></tr>
      <tr><td>Enerji (kcal)</td><td>200.0</td></tr>
      <tr><td>Yağ (g)</td><td>3.0</td></tr>
      <tr><td>Şeker (g)</td><td>5.0</td></tr>
      <tr><td>Tuz (g)</td><td>0.5</td></tr>
    </table>
    <div id="content">İçindekiler: su, şeker, tuz</div>
    </body></html>
    """


class BasisRevalidationBridgeTest(unittest.TestCase):
    def _run(self, html: str, url: str = "https://www.migros.com.tr/test-urun-p-abc123"):
        fetch_result = FetchResult(
            url=url, status=200, html=html, ok=True, final_url=url
        )
        with patch.object(bridge.Fetcher, "get", return_value=fetch_result):
            return bridge.revalidate_one(url)

    def test_exact_gram_basis_extracted(self):
        result = self._run(_html(basis_header="100 g"))
        self.assertTrue(result["ok"])
        self.assertEqual(result["normalized_basis"], "per_100g")
        self.assertEqual(result["adapter_version"], bridge.ADAPTER_VERSION)

    def test_exact_ml_basis_extracted(self):
        result = self._run(_html(basis_header="100 ml"))
        self.assertTrue(result["ok"])
        self.assertEqual(result["normalized_basis"], "per_100ml")

    def test_combined_basis_is_generic(self):
        result = self._run(_html(basis_header="100 g / ml"))
        self.assertTrue(result["ok"])
        self.assertEqual(result["normalized_basis"], "per_100_generic")

    def test_canonical_url_identifier_extracted_from_final_url(self):
        result = self._run(
            _html(),
            url="https://www.migros.com.tr/lente-parmesan-peyniri-200-g-p-9ebe02",
        )
        self.assertEqual(result["canonical_url_identifier"], "9ebe02")

    def test_barcode_extracted_from_jsonld(self):
        result = self._run(_html(barcode="8690000009999"))
        self.assertEqual(result["barcode"], "8690000009999")

    def test_nutrition_values_present(self):
        result = self._run(_html())
        self.assertEqual(result["nutrition"].get("energy_kcal"), 200.0)
        self.assertEqual(result["nutrition"].get("sugars"), 5.0)

    def test_fetch_failure_reported_as_not_ok_never_raises(self):
        fetch_result = FetchResult(
            url="https://example.test/x", ok=False, error="http 404"
        )
        with patch.object(bridge.Fetcher, "get", return_value=fetch_result):
            result = bridge.revalidate_one("https://example.test/x")
        self.assertFalse(result["ok"])
        self.assertIn("error", result)

    def test_raw_basis_text_retained(self):
        result = self._run(_html(basis_header="100 g"))
        self.assertIn("100 g", result["raw_basis_text"])


if __name__ == "__main__":
    unittest.main()
