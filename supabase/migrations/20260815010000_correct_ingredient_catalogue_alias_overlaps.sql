-- Correct production ingredient catalogue alias overlaps discovered while
-- finishing the Etiketly Score v2 additive scoring hardening pass.
--
-- Every change below is alias-array-only: no canonical row is deleted, no
-- risk_level is changed, no historical migration is edited, no audit
-- snapshot is touched. Each block verifies the target row's current
-- name/e_code before mutating and aborts the whole transaction (fails
-- safely) if the row does not match the identity this migration was
-- written against.
--
-- 1. Peynir Altı Suyu Tozu (whey powder, id abdc4ecd-...) currently lists
--    'whey protein' and 'milk powder' as aliases. Both are real, different
--    production concepts with their own canonical rows (523393de Protein
--    (Peynir Altı Suyu Proteini); 35cb460e Süt Tozunu). 'milk powder' is
--    also the exact containsAny/alias text of the static reviewed
--    catalogue's generic "süt tozu" entry (riskLevel: medium) in
--    lib/features/product/data/ingredient_explanation_catalog.dart, which is
--    why this row was raising a catalogueRiskMismatch conflict against its
--    own risk_level=low even though no genuine disagreement exists. Keep
--    'whey powder' only.
-- 2. The duplicate E471 row (Mono- ve Digliseritler, id de11207d-...) lists
--    the generic functional-class word 'emülgatör' as an alias. A
--    standalone "emülgatör" token is already blocked upstream in code
--    (IngredientMatcherService._unspecifiedFunctionalLabels), so this alias
--    cannot currently cause a false match, but it is still incorrect
--    catalogue data and is removed for hygiene / defense in depth.
-- 3. Soya Lesitin (id aafbf812-...) lists bare 'lecithin', 'E322', and
--    'E-322' as aliases. E322 is the official *generic* lecithin E-number
--    (any source), and bare "lecithin" likewise states no source —
--    attributing either to the soy-specific row fabricates allergen/source
--    information a label that only says "lecithin"/"E322" never declared.
--    Move 'E322'/'E-322' to the generic Lesitin row (which already carries
--    'lecithin' via alternative_names) and drop bare 'lecithin' here,
--    keeping only the genuinely soy-specific 'soy lecithin'.
-- 4. The generic Lesitin row (id 650e8400-...-440008) gains 'E322'/'E-322'
--    as the counterpart of #3.
-- 5. Difosfat / E450 (id 0b77c066-...) has no alias for the common
--    "sodium acid pyrophosphate" declaration. Official nomenclature
--    identifies sodium acid pyrophosphate / sodyum asit pirofosfat as
--    disodium diphosphate, i.e. E450(i) — add both as aliases. No new risk
--    value is introduced; the row's existing, already-trusted risk_level is
--    used as-is. E338/E339/E451/E452 are untouched (chemically distinct
--    phosphate E-codes are not merged).

BEGIN;

DO $$
DECLARE
  current_name TEXT;
  current_aliases TEXT[];
BEGIN
  SELECT name, aliases INTO current_name, current_aliases
  FROM public.ingredients
  WHERE id = 'abdc4ecd-e7f7-4761-812c-35559941886c'
  FOR UPDATE;

  IF current_name IS NULL THEN
    RAISE EXCEPTION 'expected_row_missing: abdc4ecd-e7f7-4761-812c-35559941886c';
  END IF;
  IF current_name <> 'Peynir Altı Suyu Tozu' THEN
    RAISE EXCEPTION 'unexpected_row_identity: abdc4ecd-e7f7-4761-812c-35559941886c name=%', current_name;
  END IF;

  UPDATE public.ingredients
  SET aliases = array_remove(
        array_remove(COALESCE(current_aliases, ARRAY[]::text[]), 'whey protein'),
        'milk powder'
      ),
      updated_at = now()
  WHERE id = 'abdc4ecd-e7f7-4761-812c-35559941886c';
END;
$$;

DO $$
DECLARE
  current_name TEXT;
  current_aliases TEXT[];
BEGIN
  SELECT name, aliases INTO current_name, current_aliases
  FROM public.ingredients
  WHERE id = 'de11207d-c26f-4411-853d-92c13f106608'
  FOR UPDATE;

  IF current_name IS NULL THEN
    RAISE EXCEPTION 'expected_row_missing: de11207d-c26f-4411-853d-92c13f106608';
  END IF;
  IF current_name <> 'Mono- ve Digliseritler' THEN
    RAISE EXCEPTION 'unexpected_row_identity: de11207d-c26f-4411-853d-92c13f106608 name=%', current_name;
  END IF;

  UPDATE public.ingredients
  SET aliases = array_remove(COALESCE(current_aliases, ARRAY[]::text[]), 'emülgatör'),
      updated_at = now()
  WHERE id = 'de11207d-c26f-4411-853d-92c13f106608';
END;
$$;

DO $$
DECLARE
  current_name TEXT;
  current_aliases TEXT[];
BEGIN
  SELECT name, aliases INTO current_name, current_aliases
  FROM public.ingredients
  WHERE id = 'aafbf812-e57a-40a2-9567-4b890c425457'
  FOR UPDATE;

  IF current_name IS NULL THEN
    RAISE EXCEPTION 'expected_row_missing: aafbf812-e57a-40a2-9567-4b890c425457';
  END IF;
  IF current_name <> 'Soya Lesitin' THEN
    RAISE EXCEPTION 'unexpected_row_identity: aafbf812-e57a-40a2-9567-4b890c425457 name=%', current_name;
  END IF;

  UPDATE public.ingredients
  SET aliases = array_remove(
        array_remove(
          array_remove(COALESCE(current_aliases, ARRAY[]::text[]), 'lecithin'),
          'E322'
        ),
        'E-322'
      ),
      updated_at = now()
  WHERE id = 'aafbf812-e57a-40a2-9567-4b890c425457';
END;
$$;

DO $$
DECLARE
  current_name TEXT;
  current_aliases TEXT[];
BEGIN
  SELECT name, aliases INTO current_name, current_aliases
  FROM public.ingredients
  WHERE id = '650e8400-e29b-41d4-a716-446655440008'
  FOR UPDATE;

  IF current_name IS NULL THEN
    RAISE EXCEPTION 'expected_row_missing: 650e8400-e29b-41d4-a716-446655440008';
  END IF;
  IF current_name <> 'Lesitin' THEN
    RAISE EXCEPTION 'unexpected_row_identity: 650e8400-e29b-41d4-a716-446655440008 name=%', current_name;
  END IF;

  UPDATE public.ingredients
  SET aliases = (
        SELECT array_agg(DISTINCT alias)
        FROM unnest(
          COALESCE(current_aliases, ARRAY[]::text[]) || ARRAY['E322', 'E-322']
        ) AS alias
      ),
      updated_at = now()
  WHERE id = '650e8400-e29b-41d4-a716-446655440008';
END;
$$;

DO $$
DECLARE
  current_name TEXT;
  current_e_code TEXT;
  current_aliases TEXT[];
BEGIN
  SELECT name, e_code, aliases INTO current_name, current_e_code, current_aliases
  FROM public.ingredients
  WHERE id = '0b77c066-6c85-4063-a241-e337aea1144e'
  FOR UPDATE;

  IF current_name IS NULL THEN
    RAISE EXCEPTION 'expected_row_missing: 0b77c066-6c85-4063-a241-e337aea1144e';
  END IF;
  IF current_name <> 'Difosfat' OR current_e_code <> 'E450' THEN
    RAISE EXCEPTION 'unexpected_row_identity: 0b77c066-6c85-4063-a241-e337aea1144e name=% e_code=%', current_name, current_e_code;
  END IF;

  UPDATE public.ingredients
  SET aliases = (
        SELECT array_agg(DISTINCT alias)
        FROM unnest(
          COALESCE(current_aliases, ARRAY[]::text[]) ||
          ARRAY['sodyum asit pirofosfat', 'sodium acid pyrophosphate']
        ) AS alias
      ),
      updated_at = now()
  WHERE id = '0b77c066-6c85-4063-a241-e337aea1144e';
END;
$$;

COMMIT;
