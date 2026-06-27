# Ingredient Risk Explanation System

## Overview

The Ingredient Risk Explanation System extends each ingredient with structured, human-readable educational metadata. The system is **deterministic and non-AI-generated** — all explanations are pre-curated in the database and displayed to help users understand:

- What the ingredient is (type/category)
- Why it's used (purpose)
- Why it may be concerning (risk summary)
- Who should be careful (caution groups)
- Where it appears (processing role)

## Goals

✅ Make ingredient cards informative and educational
✅ Help users understand detected ingredients
✅ Provide calm, factual explanations (no fear-based language)
✅ Keep explanations short and readable (1–3 sentences)
✅ Not diagnose, prescribe, or make medical claims
✅ Support deterministic analysis (no AI health claims)

## Database Schema Addition

In the `ingredients` table, add these columns:

```sql
-- Type/category of ingredient
ingredient_type TEXT NULL;
-- e.g., "Rafine bitkisel yağ", "Koruyucu katkı maddesi", "Sentetik renklendirici"

-- Why it's used (1-2 sentences)
short_purpose TEXT NULL;
-- e.g., "Kıvam ve raf ömrü için kullanılır"

-- Why it may be concerning (1-2 sentences)
short_risk_summary TEXT NULL;
-- e.g., "Yoğun işlenmiş ürünlerde sık görülür"

-- Groups of people who should be careful
caution_groups TEXT[] NULL;
-- e.g., ["çocuklar", "işlenmiş ürünleri sık tüketenler", "alerji hastaları"]

-- Where/how it's used (processing context)
processing_role TEXT NULL;
-- e.g., "Ultra işlenmiş ürünlerde yaygın olarak kullanılır"
```

## Example Ingredients

### Palm Yağı (Palm Oil)

```json
{
  "id": "palm-oil-1",
  "name": "Palm Yağı",
  "normalized_name": "palm yağı",
  "e_code": null,
  "category": "Oil and Fat",
  "risk_level": "medium",
  "short_description": "Rafine bitkisel yağ",
  "long_description": "Zeytin yağı, ayçiçek yağı ve diğer bazı bitkilere alternatif olarak kullanılan bir kuş yağıdır. Tarihsel olarak margarinlerde ve hazır ürünlerde raf ömrünü uzatmak için tercih edilmiştir.",
  "ingredient_type": "Rafine bitkisel yağ",
  "short_purpose": "Kıvam ve raf ömrü için kullanılır. Ürünlerin daha uzun süre taze kalmasını sağlar.",
  "short_risk_summary": "Yoğun işlenmiş ürünlerde sık görülür. Aşırı tüketim kötü kolesteri artırabilir.",
  "caution_groups": ["yüksek işlenmiş ürün tüketenler"],
  "processing_role": "Ultra işlenmiş ürünlerde yaygın olarak kullanılır"
}
```

### Sodyum Nitrit (Sodium Nitrite)

```json
{
  "id": "sodium-nitrite-1",
  "name": "Sodyum Nitrit",
  "normalized_name": "sodyum nitrit",
  "e_code": "E250",
  "category": "Preservative",
  "risk_level": "high",
  "short_description": "Koruyucu katkı maddesi",
  "long_description": "Et ve ürünlerinde bozulmayı önlemek ve pembe rengini korunak için kullanılan bir koruma maddesidir. Uzun süredir kullanılmakta ve sınırlı miktarda güvenilir kabul edilmektedir.",
  "ingredient_type": "Koruyucu katkı maddesi",
  "short_purpose": "Et ve et ürünlerinde kalite ve renk koruması sağlar.",
  "short_risk_summary": "Yüksek miktarlarda nitrozamin oluşturacak reaksiyonlara katılabilir. Sık tüketim endişe uyandırabilir.",
  "caution_groups": ["çocuklar", "işlenmiş et ürünlerini sık tüketenler"],
  "processing_role": "İşlenmiş et ve iç organ ürünlerinde standart olarak bulunur"
}
```

### Tartrazin (Tartrazine Yellow)

```json
{
  "id": "tartrazine-1",
  "name": "Tartrazin",
  "normalized_name": "tartrazin",
  "e_code": "E110",
  "category": "Colorant",
  "risk_level": "medium",
  "short_description": "Sentetik renklendirici",
  "long_description": "Gıda ürünlerine sarı renk vermesi için kullanılan sentetik bir azo boyadır. Sulu çözeltiler ve tatlılar gibi ürünlerde sık kullanılır.",
  "ingredient_type": "Sentetik renklendirici",
  "short_purpose": "Ürüne sarı renk verir. Ürünlerin daha çekici görünmesini sağlar.",
  "short_risk_summary": "Bazı kişilerde hassasiyet uyandırabilir. Hiperativite ile ilişkilendirilen birkaç renk katkısından biridir.",
  "caution_groups": ["astım hastaları", "hassas kişiler"],
  "processing_role": "Tatlılar, meşrubatlar ve şeker ürünlerinde yaygın"
}
```

### Sodyum Karbonat (Sodium Carbonate)

```json
{
  "id": "sodium-carbonate-1",
  "name": "Sodyum Karbonat",
  "normalized_name": "sodyum karbonat",
  "e_code": "E500",
  "category": "Leavening Agent, pH Regulator",
  "risk_level": "low",
  "short_description": "pH düzenleyici ve kabartıcı katkı maddesi",
  "long_description": "Ekmek, çörek ve diğer pişmiş ürünlerde kabartma ve pH dengelemesi için kullanılan doğal bir tuz.",
  "ingredient_type": "Kabartıcı katkı maddesi",
  "short_purpose": "Pişmiş ürünlerin şismesini sağlar ve asitliğini dengeler.",
  "short_risk_summary": "Yüksek miktarlarda tuz içerir. Normal kullanımda güvenlidir.",
  "caution_groups": [],
  "processing_role": "Özellikle pişmiş ve kabartırılmış ürünlerde bulunur"
}
```

## UI Display

### Ingredient Match Card

When an ingredient is detected:
- Shows ingredient name and initial risk level badge
- Below risk badge: displays IngredientExplanationCard widget
- Shows: type, purpose, risk summary, caution groups (each in colored box)
- Preserves original "E-code" and confidence score

### Ingredient Detail Page

When user taps an ingredient for more info:
- Shows ingredient name and long description
- Displays structured explanation sections:
  - Type/Category (blue box)
  - Purpose/Usage (teal box)
  - Processing Role (cyan box)
  - Risk Summary (amber box)
  - Caution Groups (orange tags)
- Shows additive group, aliases, and sources (existing sections)

## Color Scheme

| Section | Background | Border | Text |
|---------|-----------|--------|------|
| Type | `Colors.blue[50]` | `Colors.blue[200]` | `Colors.blue[800]` |
| Purpose | `Colors.teal[50]` | `Colors.teal[200]` | `Colors.teal[900]` |
| Role | `Colors.cyan[50]` | `Colors.cyan[200]` | `Colors.cyan[900]` |
| Risk (Low) | `Colors.green[50]` | `Colors.green[200]` | `Colors.green[900]` |
| Risk (Medium) | `Colors.amber[50]` | `Colors.amber[200]` | `Colors.amber[900]` |
| Risk (High) | `Colors.red[50]` | `Colors.red[200]` | `Colors.red[900]` |
| Caution Groups | `Colors.orange[100]` | `Colors.orange[300]` | `Colors.orange[900]` |

## Implementation Details

### Model Updates

**`lib/features/product/models/ingredient.dart`**
- Added fields: `ingredientType`, `shortPurpose`, `shortRiskSummary`, `cautionGroups`, `processingRole`
- Updated `fromJson()` and `toJson()` methods

**`lib/features/product/models/ingredient_detail.dart`**
- Added getters to expose explanation fields
- Added `hasExplanationMetadata` property

**`lib/features/analysis/models/ingredient_match.dart`**
- Added convenience getters: `getIngredientType()`, `getShortPurpose()`, etc.
- Added `hasExplanationMetadata()` to check if metadata exists

### UI Components

**`lib/shared/widgets/ingredient_explanation_card.dart`** (NEW)
- Displays ingredient explanation metadata in organized sections
- Automatically applies risk-based colors to risk summary
- Hides empty sections
- Reusable across analysis and detail screens

**`lib/features/analysis/widgets/ingredient_match_result.dart`**
- Integrated IngredientExplanationCard after risk level badge
- No changes to existing match detection logic

**`lib/features/analysis/pages/ingredient_detail_page.dart`**
- Displays explanation sections on detail page
- Added caution groups tags
- Maintains existing long descriptions and sources

## Important Design Rules

✅ **Deterministic**: All explanations are database-stored, never AI-generated
✅ **Educational**: Focus on food knowledge, not medical diagnosis
✅ **Calm**: Avoid urgent warning language like "WARNING!" or "DANGEROUS!"
✅ **Concise**: Keep explanations to 1–3 sentences maximum
✅ **Inclusive**: Show caution groups as informational, not restrictive
✅ **Progressive**: Show confidence scores separately from risk assessment

## Example Data Loading

To populate ingredient explanations in Supabase:

```sql
-- Example: Update existing palm oil ingredient
UPDATE ingredients
SET 
  ingredient_type = 'Rafine bitkisel yağ',
  short_purpose = 'Kıvam ve raf ömrü için kullanılır. Ürünlerin daha uzun süre taze kalmasını sağlar.',
  short_risk_summary = 'Yoğun işlenmiş ürünlerde sık görülür. Aşırı tüketim kötü kolesteri artırabilir.',
  caution_groups = ARRAY['yüksek işlenmiş ürün tüketenler'],
  processing_role = 'Ultra işlenmiş ürünlerde yaygın olarak kullanılır'
WHERE normalized_name = 'palm yağı';
```

## Testing

✅ flutter analyze passes with zero issues
✅ IngredientExplanationCard displays correctly when metadata exists
✅ Safe defaults when metadata is missing (SizedBox.shrink)
✅ Risk-based coloring in risk summary section
✅ Caution groups render as readable tags
✅ Ingredient detail page shows all sections clearly

## Future Enhancements

- Admin UI to edit ingredient explanations
- Source links for each explanation
- Expandable "Daha Fazla Bilgi" sections
- User feedback: "Is this helpful?" on detail pages
- Translation support for explanation text
