import sys
import types
# Provide a minimal dotenv stub for test-time import if python-dotenv is not installed.
if 'dotenv' not in sys.modules:
    sys.modules['dotenv'] = types.SimpleNamespace(load_dotenv=lambda: None)

from main import parse_ingredient_text_to_items


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


if __name__ == '__main__':
    test_complex_label()
    print('OK')
