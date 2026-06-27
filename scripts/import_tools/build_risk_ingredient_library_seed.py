from __future__ import annotations

import json
import re
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
SOURCE_FILE = ROOT / "ingredient_intelligence_seed.json"
OUTPUT_FILE = ROOT / "risk_ingredient_library_seed.json"


@dataclass(frozen=True)
class SeedEntry:
    canonical_name: str
    aliases: list[str]
    e_codes: list[str]
    consumer_section: str
    ingredient_type: str
    short_purpose: str
    short_risk_summary: str
    caution_groups: list[str]
    risk_level: str
    risk_tags: list[str]
    category_tags: list[str]
    priority_score: int


def normalize_alias(value: str) -> str:
    value = value.strip().lower()
    value = value.replace("İ", "i").replace("I", "ı")
    value = re.sub(r"\s+", " ", value)
    return value


def dedupe_preserve_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        normalized = normalize_alias(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        out.append(value.strip())
    return out


def infer_consumer_section(risk_level: str, risk_tags: list[str], category_tags: list[str], name: str) -> str:
    lower = name.lower()
    if any(tag in {"caffeine_stimulant", "stimulant"} for tag in risk_tags):
        return "uyarici_icerikler"
    if any(tag in {"added_sugar", "sugar_syrup", "artificial_sweetener"} for tag in risk_tags) or any(
        key in lower for key in ["şeker", "glikoz", "fruktoz", "tatlandır", "sweetener", "sorbitol", "xylitol"]
    ):
        return "seker_tatlandirici_sinyalleri"
    if any(tag in {"low_quality_oil", "hydrogenated_oil", "ultra_processed_marker"} for tag in risk_tags) or any(
        key in lower for key in ["yağ", "oil", "fat", "margarin", "trans"]
    ):
        return "yag_islenmislik_sinyalleri"
    if any(tag in {"preservative", "colorant", "emulsifier", "acidity_regulator", "thickener", "stabilizer", "flavor_enhancer", "phosphate", "modified_starch"} for tag in risk_tags):
        return "katki_ve_koruyucular"
    if risk_level == "low" and any(tag in {"positive_signal", "whole_grain", "fiber", "protein", "probiotic"} for tag in risk_tags):
        return "olumlu_sinyaller"
    if any(key in lower for key in ["yulaf", "tam tahıl", "tam bugday", "whole grain", "fiber", "lif", "protein", "probiyotik", "kefir", "baklagil"]):
        return "olumlu_sinyaller"
    return "dikkat_edilecek_icerikler"


def make_entry(
    canonical_name: str,
    aliases: list[str] | None,
    e_codes: list[str] | None,
    ingredient_type: str,
    short_purpose: str,
    short_risk_summary: str,
    caution_groups: list[str] | None,
    risk_level: str,
    risk_tags: list[str],
    category_tags: list[str],
    priority_score: int,
    consumer_section: str | None = None,
) -> dict[str, Any]:
    aliases = dedupe_preserve_order(aliases or [])
    e_codes = dedupe_preserve_order([code.upper() for code in (e_codes or [])])
    consumer_section = consumer_section or infer_consumer_section(risk_level, risk_tags, category_tags, canonical_name)
    return {
        "canonical_name": canonical_name,
        "aliases": aliases,
        "e_codes": e_codes,
        "consumer_section": consumer_section,
        "ingredient_type": ingredient_type,
        "short_purpose": short_purpose,
        "short_risk_summary": short_risk_summary,
        "caution_groups": dedupe_preserve_order(caution_groups or []),
        "risk_level": risk_level,
        "risk_tags": dedupe_preserve_order(risk_tags),
        "category_tags": dedupe_preserve_order(category_tags),
        "priority_score": priority_score,
    }


def transform_existing_sources() -> list[dict[str, Any]]:
    source_items: list[dict[str, Any]] = []
    if SOURCE_FILE.exists():
        source_items = json.loads(SOURCE_FILE.read_text(encoding="utf-8"))

    transformed: list[dict[str, Any]] = []
    for item in source_items:
        name = item.get("canonical_name") or item.get("name_tr") or item.get("name") or ""
        if not name:
            continue
        aliases = item.get("aliases") or []
        if item.get("name_en"):
            aliases.append(item["name_en"])
        if item.get("e_number"):
            aliases.append(str(item["e_number"]))
            aliases.append(str(item["e_number"]).upper())
        if item.get("e_code"):
            aliases.append(str(item["e_code"]))
            aliases.append(str(item["e_code"]).upper())
        risk_level = item.get("risk_level", "unknown")
        category = (item.get("category") or "").lower()
        risk_tags: list[str] = []
        if risk_level == "high":
            risk_tags.append("high_risk")
        elif risk_level == "medium":
            risk_tags.append("medium_risk")
        elif risk_level == "low":
            risk_tags.append("positive_signal")
        if any(key in category for key in ["koruyucu", "preserv", "muhafaza"]):
            risk_tags.append("preservative")
        if any(key in category for key in ["renk", "color"]):
            risk_tags.append("colorant")
        if any(key in category for key in ["tatlandır", "sweet"]):
            risk_tags.append("artificial_sweetener")
        if any(key in category for key in ["emülgat", "emuls"]):
            risk_tags.append("emulsifier")
        if any(key in category for key in ["asit", "ph", "phosphate", "antioks"]):
            risk_tags.append("acidity_regulator")
        if any(key in category for key in ["yağ", "oil", "fat"]):
            risk_tags.append("low_quality_oil")
        if any(key in category for key in ["kabart", "leaven", "stabil", "kıvam", "gum", "nişasta"]):
            risk_tags.append("stabilizer")
        if any(key in category for key in ["lezzet", "flavor"]):
            risk_tags.append("flavor_enhancer")
        if any(key in category for key in ["gıda", "temel", "protein", "lif", "tahıl", "baklagil", "süt"]):
            risk_tags.append("positive_signal")

        category_tags = item.get("category_tags") or []
        if not category_tags:
            category_tags = ["packaged food"]
        transformed.append(
            make_entry(
                canonical_name=name,
                aliases=aliases,
                e_codes=item.get("e_codes") or ([item["e_code"]] if item.get("e_code") else []),
                ingredient_type=item.get("ingredient_type") or item.get("short_description") or "Gıda bileşeni",
                short_purpose=item.get("short_purpose") or item.get("short_description") or "Yaygın bir gıda bileşeni olarak kullanılır.",
                short_risk_summary=item.get("short_risk_summary") or "Genel olarak paketli gıdalarda kullanılır; içerik listesi ile birlikte değerlendirilir.",
                caution_groups=item.get("caution_groups") or [],
                risk_level=risk_level,
                risk_tags=risk_tags or ["positive_signal" if risk_level == "low" else "medium_risk"],
                category_tags=category_tags,
                priority_score=int(item.get("priority_score") or (95 if risk_level == "high" else 75 if risk_level == "medium" else 35)),
            )
        )
    return transformed


EXTRA_GROUPS: list[tuple[str, list[tuple[str, list[str], list[str]]], str, str, str, str, list[str], str, list[str], list[str], int]] = [
    (
        "katki_ve_koruyucular",
        [
            ("Sorbik Asit", ["sorbic acid"], ["E200"]),
            ("Sodyum Sorbat", ["sodium sorbate"], ["E201"]),
            ("Potasyum Sorbat", ["potassium sorbate"], ["E202"]),
            ("Kalsiyum Sorbat", ["calcium sorbate"], ["E203"]),
            ("Benzoik Asit", ["benzoic acid"], ["E210"]),
            ("Sodyum Benzoat", ["sodium benzoate"], ["E211"]),
            ("Potasyum Benzoat", ["potassium benzoate"], ["E212"]),
            ("Kalsiyum Benzoat", ["calcium benzoate"], ["E213"]),
            ("Methylparaben", ["metilparaben", "methyl p-hydroxybenzoate"], ["E218"]),
            ("Ethylparaben", ["etilparaben", "ethyl p-hydroxybenzoate"], ["E214"]),
            ("Propylparaben", ["propilparaben", "propyl p-hydroxybenzoate"], ["E216"]),
            ("Butylparaben", ["butilparaben", "butyl p-hydroxybenzoate"], ["E209"]),
            ("Sülfür Dioksit", ["sulfur dioxide", "so2"], ["E220"]),
            ("Sodyum Sülfit", ["sodium sulfite"], ["E221"]),
            ("Sodyum Bisülfit", ["sodium bisulfite"], ["E222"]),
            ("Sodyum Metabisülfit", ["sodium metabisulfite"], ["E223"]),
            ("Potasyum Metabisülfit", ["potassium metabisulfite"], ["E224"]),
            ("Kalsiyum Sülfit", ["calcium sulfite"], ["E226"]),
            ("Potasyum Sülfit", ["potassium sulfite"], ["E225"]),
            ("Sodyum Asetat", ["sodium acetate"], ["E262"]),
            ("Sodyum Diasetat", ["sodium diacetate"], ["E262"]),
            ("Asetik Asit", ["acetic acid"], ["E260"]),
            ("Laktik Asit", ["lactic acid"], ["E270"]),
            ("Sodyum Nitrit", ["sodium nitrite"], ["E250"]),
            ("Potasyum Nitrit", ["potassium nitrite"], ["E249"]),
            ("Sodyum Nitrat", ["sodium nitrate"], ["E251"]),
            ("Potasyum Nitrat", ["potassium nitrate"], ["E252"]),
            ("Nisin", ["E234"], ["E234"]),
            ("Natamisin", ["natamycin", "E235"], ["E235"]),
        ],
        "Koruyucu katkı",
        "Gıda güvenliğini ve raf ömrünü desteklemek için kullanılır.",
        "Yasal limitlerde kullanılan bir katkıdır; sık tüketimde dikkat edilebilir.",
        ["çocuklar", "işlenmiş ürünleri sık tüketenler"],
        "medium",
        ["preservative"],
        ["packaged food", "preservatives"],
        88,
    ),
    (
        "katki_ve_koruyucular",
        [
            ("Tartrazin", ["tartrazine", "E102"], ["E102"]),
            ("Kinolin Sarısı", ["quinoline yellow", "E104"], ["E104"]),
            ("Gün Batımı Sarısı FCF", ["sunset yellow", "E110"], ["E110"]),
            ("Azorubin", ["carmoisine", "E122"], ["E122"]),
            ("Ponceau 4R", ["cochineal red A", "E124"], ["E124"]),
            ("Allura Red AC", ["E129"], ["E129"]),
            ("Brilliant Blue FCF", ["E133"], ["E133"]),
            ("Patent Blue V", ["E131"], ["E131"]),
            ("İndigotin", ["indigotine", "E132"], ["E132"]),
            ("Karamel Rengi", ["caramel colour", "caramel color", "E150"], ["E150"]),
            ("Karamel Rengi I", ["E150a"], ["E150a"]),
            ("Karamel Rengi II", ["E150b"], ["E150b"]),
            ("Karamel Rengi III", ["E150c"], ["E150c"]),
            ("Karamel Rengi IV", ["E150d"], ["E150d"]),
            ("Beta Karoten", ["beta-carotene", "E160a"], ["E160a"]),
            ("Annatto", ["E160b"], ["E160b"]),
            ("Kurkumin", ["curcumin", "E100"], ["E100"]),
            ("Riboflavin", ["E101"], ["E101"]),
            ("Koşenil", ["carmine", "E120"], ["E120"]),
            ("Titanyum Dioksit", ["titanium dioxide", "E171"], ["E171"]),
        ],
        "Sentetik renklendirici",
        "Ürüne renk vermek için kullanılır.",
        "Bazı hassas kişilerde dikkat gerektirebilir; ürünün genel işlenmişlik düzeyi ile birlikte değerlendirilir.",
        ["hassas kişiler", "çocuklar"],
        "medium",
        ["colorant"],
        ["colors", "packaged food"],
        85,
    ),
    (
        "seker_tatlandirici_sinyalleri",
        [
            ("Acesulfame K", ["asesülfam k", "E950"], ["E950"]),
            ("Aspartam", ["aspartame", "E951"], ["E951"]),
            ("Sodyum Siklamat", ["cyclamate", "E952"], ["E952"]),
            ("Sakarin", ["saccharin", "E954"], ["E954"]),
            ("Sukraloz", ["sucralose", "E955"], ["E955"]),
            ("Neotam", ["neotame", "E961"], ["E961"]),
            ("Steviol Glikozitleri", ["steviol glycosides", "E960"], ["E960"]),
            ("Advantam", ["advantame", "E969"], ["E969"]),
            ("Sorbitol", ["E420"], ["E420"]),
            ("Ksilitol", ["xylitol", "E967"], ["E967"]),
            ("Maltitol", ["E965"], ["E965"]),
            ("Mannitol", ["E421"], ["E421"]),
            ("Eritritol", ["erythritol", "E968"], ["E968"]),
            ("Laktitol", ["E966"], ["E966"]),
            ("İzomalt", ["isomalt", "E953"], ["E953"]),
        ],
        "Tatlandırıcı",
        "Tatlılık sağlamak için kullanılır.",
        "Bazı hassas kişilerde sindirim veya tat algısı açısından dikkat gerektirebilir.",
        ["çocuklar", "tatlandırıcı hassasiyeti olanlar"],
        "medium",
        ["artificial_sweetener"],
        ["sweeteners", "packaged food"],
        86,
    ),
    (
        "seker_tatlandirici_sinyalleri",
        [
            ("Şeker", ["toz şeker", "beyaz şeker", "sakkaroz"], []),
            ("Glikoz Şurubu", ["glucose syrup", "corn syrup"], []),
            ("Fruktoz Şurubu", ["fructose syrup", "hfcs"], []),
            ("Glikoz-Fruktoz Şurubu", ["glucose-fructose syrup", "glucose fructose syrup"], []),
            ("Mısır Şurubu", ["corn syrup"], []),
            ("İnvert Şeker", ["invert sugar"], []),
            ("İnvert Şeker Şurubu", ["invert sugar syrup"], []),
            ("Dekstroz", ["dextrose", "E葡萄糖"], []),
            ("Maltoz", ["maltose"], []),
            ("Maltodekstrin", ["maltodextrin"], []),
            ("Karamel Şurubu", ["caramel syrup"], []),
            ("Arpa Malt Şurubu", ["barley malt syrup"], []),
            ("Agave Şurubu", ["agave syrup"], []),
            ("Pekmez", ["molasses"], []),
            ("Bal", ["honey"], []),
        ],
        "Rafine karbonhidrat",
        "Tatlandırma ve ürün dokusunu desteklemek için kullanılır.",
        "Sık tüketimde dikkat edilebilir; ürünün şeker yükünü artırabilir.",
        ["diyabet hastaları", "çocuklar"],
        "medium",
        ["added_sugar", "sugar_syrup"],
        ["sugars", "packaged food", "beverages"],
        90,
    ),
    (
        "yag_islenmislik_sinyalleri",
        [
            ("Palm Yağı", ["palmiye yağı", "palm oil", "palm fat"], []),
            ("Palmiye Yağı", ["palmyağı", "palmyağ"], []),
            ("Palm Olein", ["palm olein"], []),
            ("Palm Stearin", ["palm stearin"], []),
            ("Palm Kernel Oil", ["palm çekirdeği yağı"], []),
            ("Hidrojenize Yağ", ["hydrogenated oil"], []),
            ("Kısmen Hidrojenize Yağ", ["partially hydrogenated oil"], []),
            ("Trans Yağ", ["trans fat"], []),
            ("İnteresterifiye Yağ", ["interesterified fat"], []),
            ("Bitkisel Yağlar", ["vegetable oils"], []),
            ("Rafine Bitkisel Yağ", ["refined vegetable oil"], []),
            ("Rafine Ayçiçek Yağı", ["refined sunflower oil"], []),
            ("Rafine Kanola Yağı", ["refined canola oil"], []),
            ("Rafine Soya Yağı", ["refined soybean oil"], []),
            ("Rafine Pamuk Yağı", ["refined cottonseed oil"], []),
            ("Margarin", ["margarine"], []),
            ("Bitkisel Yağ Karışımı", ["vegetable oil blend"], []),
            ("Yağ Karışımı", ["fat blend"], []),
            ("Kısaltma Yağı", ["shortening"], []),
            ("Kakao Yağı İkamesi", ["cocoa butter substitute"], []),
        ],
        "Rafine bitkisel yağ",
        "Ürünün doku, raf ömrü ve hissini desteklemek için kullanılır.",
        "Ultra işlenmiş ürünlerde sık görülür; tüketim sıklığı ile birlikte değerlendirilir.",
        ["kolesterol hassasiyeti olanlar", "işlenmiş ürünleri sık tüketenler"],
        "medium",
        ["low_quality_oil", "hydrogenated_oil", "ultra_processed_marker"],
        ["oils", "snacks", "spreads", "bakery", "packaged food"],
        92,
    ),
    (
        "katki_ve_koruyucular",
        [
            ("Lesitin", ["lecithin", "soya lesitini", "sunflower lecithin"], ["E322"]),
            ("Mono ve Digliseritler", ["mono-diglycerides", "E471"], ["E471"]),
            ("Sodyum Stearoil Laktilat", ["sodium stearoyl lactylate", "E481"], ["E481"]),
            ("DATEM", ["diacetyl tartaric acid esters of mono- and diglycerides", "E472e"], ["E472e"]),
            ("Sorbitan Monostearat", ["E491"], ["E491"]),
            ("Sorbitan Tristearat", ["E492"], ["E492"]),
            ("Polisorbat 20", ["polysorbate 20", "E432"], ["E432"]),
            ("Polisorbat 60", ["polysorbate 60", "E435"], ["E435"]),
            ("Polisorbat 80", ["polysorbate 80", "E433"], ["E433"]),
            ("Karragenan", ["carrageenan", "E407"], ["E407"]),
            ("Ksantan Gam", ["xanthan gum", "E415"], ["E415"]),
            ("Guar Gam", ["guar gum", "E412"], ["E412"]),
            ("Keçiboynuzu Gamı", ["locust bean gum", "E410"], ["E410"]),
            ("Arap Zamkı", ["gum arabic", "E414"], ["E414"]),
            ("Jelatin", ["gelatin"], []),
            ("Pektin", ["E440"], ["E440"]),
            ("Agar", ["E406"], ["E406"]),
            ("Alginat", ["sodium alginate", "E401"], ["E401"]),
            ("Jellan Gam", ["gellan gum", "E418"], ["E418"]),
            ("Karboksimetil Selüloz", ["carboxymethyl cellulose", "E466"], ["E466"]),
            ("Mikrokristalin Selüloz", ["microcrystalline cellulose"], []),
            ("Hidroksipropil Metilselüloz", ["hpmc", "E464"], ["E464"]),
            ("Metilselüloz", ["methylcellulose", "E461"], ["E461"]),
            ("Modifiye Nişasta", ["modified starch"], []),
            ("Asit Muamelesi Görmüş Nişasta", ["acid-treated starch"], []),
            ("Oksitlenmiş Nişasta", ["oxidized starch"], []),
            ("Asetillenmiş Nişasta", ["acetylated starch"], []),
            ("Hidroksipropil Nişasta", ["hydroxypropyl starch"], []),
            ("Distarch Fosfat", ["distarch phosphate"], []),
            ("Maltodekstrin", ["maltodextrin"], []),
        ],
        "Kıvam verici / emülgatör",
        "Doku, karışım dengesi ve stabilite için kullanılır.",
        "Yasal limitlerde kullanılan katkılardır; ürünün işlenmişlik düzeyi ile birlikte değerlendirilir.",
        ["katkı içeren ürünleri sık tüketenler"],
        "medium",
        ["emulsifier", "stabilizer", "thickener", "modified_starch"],
        ["bakery", "snacks", "spreads", "dairy", "sauces", "packaged food"],
        80,
    ),
    (
        "katki_ve_koruyucular",
        [
            ("Monosodyum Glutamat", ["msg", "e621", "monosodium glutamate"], ["E621"]),
            ("Glutamik Asit", ["glutamic acid", "E620"], ["E620"]),
            ("Disodyum İnosinat", ["disodium inosinate", "E631"], ["E631"]),
            ("Disodyum Guanylat", ["disodium guanylate", "E627"], ["E627"]),
            ("Disodyum 5\'-Ribonükleotidler", ["e635", "disodium 5\'-ribonucleotides"], ["E635"]),
            ("Maya Ekstraktı", ["yeast extract"], []),
            ("Hidrolize Bitkisel Protein", ["hydrolyzed vegetable protein", "hvp"], []),
            ("Hidrolize Protein", ["hydrolyzed protein"], []),
            ("Hidrolize Soya Proteini", ["hydrolyzed soy protein"], []),
            ("Otoolize Maya", ["autolyzed yeast"], []),
            ("Et Ekstraktı", ["meat extract"], []),
            ("Balık Ekstraktı", ["fish extract"], []),
            ("Mantar Ekstraktı", ["mushroom extract"], []),
        ],
        "Lezzet arttırıcı",
        "Tat dengesini ve lezzet algısını desteklemek için kullanılır.",
        "Sık tüketimde dikkat edilebilir; ultra işlenmiş ürünlerde daha sık görülür.",
        ["işlenmiş ürünleri sık tüketenler"],
        "medium",
        ["flavor_enhancer"],
        ["sauces", "snacks", "instant foods", "packaged food"],
        84,
    ),
    (
        "katki_ve_koruyucular",
        [
            ("Sitrik Asit", ["citric acid", "E330"], ["E330"]),
            ("Sodyum Sitrat", ["sodium citrate", "E331"], ["E331"]),
            ("Potasyum Sitrat", ["potassium citrate", "E332"], ["E332"]),
            ("Kalsiyum Sitrat", ["calcium citrate", "E333"], ["E333"]),
            ("Tartarik Asit", ["tartaric acid", "E334"], ["E334"]),
            ("Sodyum Tartarat", ["sodium tartrate", "E335"], ["E335"]),
            ("Potasyum Tartarat", ["potassium tartrate", "E336"], ["E336"]),
            ("Fosforik Asit", ["phosphoric acid", "E338"], ["E338"]),
            ("Sodyum Fosfat", ["sodium phosphate", "E339"], ["E339"]),
            ("Potasyum Fosfat", ["potassium phosphate", "E340"], ["E340"]),
            ("Kalsiyum Fosfat", ["calcium phosphate", "E341"], ["E341"]),
            ("Dikalsiyum Fosfat", ["E450"], ["E450"]),
            ("Trisodyum Fosfat", ["E339"], ["E339"]),
            ("Difosfatlar", ["diphosphates", "E450"], ["E450"]),
            ("Trifosfatlar", ["triphosphates", "E451"], ["E451"]),
            ("Polifosfatlar", ["polyphosphates", "E452"], ["E452"]),
            ("Kalsiyum Karbonat", ["calcium carbonate", "E170"], ["E170"]),
            ("Sodyum Bikarbonat", ["sodium bicarbonate", "E500"], ["E500"]),
            ("Potasyum Bikarbonat", ["potassium bicarbonate", "E501"], ["E501"]),
            ("Askorbik Asit", ["ascorbic acid", "E300"], ["E300"]),
            ("Sodyum Askorbat", ["sodium ascorbate", "E301"], ["E301"]),
            ("Kalsiyum Askorbat", ["calcium ascorbate", "E302"], ["E302"]),
            ("Tokoferolce Zengin Ekstrakt", ["mixed tocopherols", "E306"], ["E306"]),
            ("Tokoferoller", ["tocopherols", "E307"], ["E307"]),
            ("BHA", ["butylated hydroxyanisole", "E320"], ["E320"]),
            ("BHT", ["butylated hydroxytoluene", "E321"], ["E321"]),
            ("Propil Gallat", ["propyl gallate", "E310"], ["E310"]),
            ("Sodyum Eritorbat", ["sodium erythorbate"], []),
        ],
        "Asitlik düzenleyici / antioksidan",
        "Asitlik dengesini ve ürün stabilitesini desteklemek için kullanılır.",
        "Genellikle düşük veya orta riskli katkılardır; ürünün genel içeriği ile birlikte değerlendirilir.",
        ["hassas kişiler"],
        "low",
        ["acidity_regulator", "antioxidant", "phosphate"],
        ["sauces", "dairy", "bakery", "processed foods", "packaged food"],
        60,
    ),
    (
        "uyarici_icerikler",
        [
            ("Kafein", ["caffeine"], []),
            ("Taurin", ["taurine"], []),
            ("Guarana", ["guarana extract"], []),
            ("Ginseng", ["ginseng extract"], []),
            ("L-Karnitin", ["l-carnitine"], []),
            ("İnositol", ["inositol"], []),
            ("Glukuronolakton", ["glucuronolactone"], []),
            ("Mate Ekstraktı", ["yerba mate", "maté extract"], []),
            ("Yeşil Çay Ekstraktı", ["green tea extract"], []),
            ("Kola Fındığı Ekstraktı", ["kola nut"], []),
            ("B12 Vitamini", ["cyanocobalamin"], []),
            ("B6 Vitamini", ["pyridoxine"], []),
        ],
        "Uyarıcı",
        "Uyanıklık hissini desteklemek veya enerji hissi vermek için kullanılır.",
        "Çocuklar, gebeler ve kafein hassasiyeti olan kişiler için dikkat gerektirebilir.",
        ["çocuklar", "gebeler", "kafein hassasiyeti olanlar"],
        "medium",
        ["caffeine_stimulant"],
        ["energy drinks", "beverages", "packaged food"],
        95,
    ),
    (
        "dikkat_edilecek_icerikler",
        [
            ("Sodyum Fosfat Karışımı", ["phosphate blend"], []),
            ("Pişmiş Et Suyu Tozu", ["meat broth powder"], []),
            ("Duman Aroması", ["smoke flavouring", "smoke flavoring"], []),
            ("Mekanik Ayrılmış Et", ["mechanically separated meat"], []),
            ("Tuz", ["salt", "sodium chloride"], []),
            ("Deniz Tuzu", ["sea salt"], []),
            ("Kürleme Tuzu", ["curing salt"], []),
            ("Nitritli Kürleme Tuzu", ["nitrite curing salt"], []),
            ("Sosislik Et Karışımı", ["processed meat mix"], []),
            ("Et Proteini Hidrolizatı", ["hydrolyzed meat protein"], []),
            ("Tavuk Proteini", ["chicken protein"], []),
            ("Et Aroması", ["meat flavor"], []),
            ("İşlenmiş Et Ürünü Karışımı", ["processed meat ingredient"], []),
            ("Füme Aroma", ["smoked aroma"], []),
            ("Baharat Karışımı", ["spice mix"], []),
        ],
        "İşlenmiş et bileşeni",
        "İşlenmiş et ürünlerinde veya benzer ürünlerde kullanılır.",
        "İşlenmiş ürünlerde sık tüketimde dikkat edilebilir.",
        ["işlenmiş et tüketenler"],
        "medium",
        ["processed_meat_additive", "preservative", "high_salt_signal"],
        ["processed meat", "packaged food", "sauces", "ready meals"],
        87,
    ),
    (
        "olumlu_sinyaller",
        [
            ("Yulaf", ["oats"], []),
            ("Yulaf Ezmesi", ["oat flakes"], []),
            ("Yulaf Kepeği", ["oat bran"], []),
            ("Tam Tahıl", ["whole grain"], []),
            ("Tam Buğday", ["whole wheat"], []),
            ("Buğday Kepeği", ["wheat bran"], []),
            ("Çavdar", ["rye"], []),
            ("Arpa", ["barley"], []),
            ("Keten Tohumu", ["flaxseed"], []),
            ("Chia Tohumu", ["chia seeds"], []),
            ("Kabak Çekirdeği", ["pumpkin seeds"], []),
            ("Ay Çekirdeği", ["sunflower seeds"], []),
            ("Badem", ["almond"], []),
            ("Fındık", ["hazelnut"], []),
            ("Ceviz", ["walnut"], []),
            ("Kakao", ["cocoa"], []),
            ("Yüksek Lif", ["fiber"], []),
            ("İnülin", ["inulin"], []),
            ("Psyllium", ["ispaghula husk"], []),
            ("Probiyotik Kültür", ["probiotic culture"], []),
            ("Lactobacillus Kulturü", ["lactobacillus"], []),
            ("Bifidobacterium Kulturü", ["bifidobacterium"], []),
            ("Kefir Kültürü", ["kefir culture"], []),
            ("Protein", ["protein"], []),
            ("Süt Proteini", ["milk protein"], []),
            ("Bezelye Proteini", ["pea protein"], []),
            ("Soya Proteini", ["soy protein"], []),
            ("Nohut", ["chickpea"], []),
            ("Mercimek", ["lentil"], []),
            ("Bezelye", ["pea"], []),
            ("Susam", ["sesame"], []),
            ("Bulgur", ["bulgur"], []),
            ("Kinoa", ["quinoa"], []),
            ("Karabuğday", ["buckwheat"], []),
            ("Amarant", ["amaranth"], []),
            ("Yulaf Lifi", ["oat fiber"], []),
            ("Nohut Unu", ["chickpea flour"], []),
            ("Mercimek Unu", ["lentil flour"], []),
            ("Bezelye Unu", ["pea flour"], []),
            ("Fermente Soya", ["fermented soy"], []),
        ],
        "Olumlu beslenme sinyali",
        "Beslenme çeşitliliğini ve lif/protein katkısını destekler.",
        "Genellikle olumlu sinyaldir; yine de ürünün toplam besin profili ile birlikte değerlendirilir.",
        ["lif alımını önemseyenler"],
        "low",
        ["positive_signal", "fiber", "protein", "whole_grain", "probiotic"],
        ["grains", "nuts", "seeds", "dairy", "legumes", "packaged food"],
        35,
    ),
]


def build_extra_entries() -> list[dict[str, Any]]:
    extras: list[dict[str, Any]] = []
    for section, items, ingredient_type, purpose, risk_summary, default_caution, risk_level, risk_tags, category_tags, base_priority in EXTRA_GROUPS:
        for idx, (name, aliases, e_codes) in enumerate(items):
            aliases = list(aliases)
            if not aliases:
                aliases = []
            priority = max(1, min(100, base_priority - (idx % 4) * 2))
            extras.append(
                make_entry(
                    canonical_name=name,
                    aliases=aliases,
                    e_codes=e_codes,
                    ingredient_type=ingredient_type,
                    short_purpose=purpose,
                    short_risk_summary=risk_summary,
                    caution_groups=default_caution,
                    risk_level=risk_level,
                    risk_tags=risk_tags,
                    category_tags=category_tags,
                    priority_score=priority,
                    consumer_section=section,
                )
            )
    return extras


def write_output() -> None:
    existing = transform_existing_sources()
    extras = build_extra_entries()

    merged: OrderedDict[str, dict[str, Any]] = OrderedDict()
    for entry in existing + extras:
        key = normalize_alias(entry["canonical_name"])
        if key in merged:
            continue
        merged[key] = entry

    output = list(merged.values())
    OUTPUT_FILE.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(output)} entries to {OUTPUT_FILE}")


if __name__ == "__main__":
    write_output()
