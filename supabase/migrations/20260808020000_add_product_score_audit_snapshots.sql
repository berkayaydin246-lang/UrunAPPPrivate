-- Immutable, append-only evidence for every publicly displayable Etiketly score.
-- This migration is additive and intentionally does not backfill existing rows.

CREATE TABLE public.product_score_audit_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  input_fingerprint TEXT NOT NULL
    CHECK (input_fingerprint ~ '^[a-f0-9]{64}$'),
  snapshot_schema_version INTEGER NOT NULL
    CHECK (snapshot_schema_version > 0),
  score_version TEXT NOT NULL CHECK (btrim(score_version) <> ''),
  nutrition_methodology_version TEXT NOT NULL
    CHECK (btrim(nutrition_methodology_version) <> ''),
  nutrition_transform_version TEXT NOT NULL
    CHECK (btrim(nutrition_transform_version) <> ''),
  additive_transform_version TEXT NOT NULL
    CHECK (btrim(additive_transform_version) <> ''),
  trigger_source TEXT NOT NULL CHECK (
    trigger_source IN (
      'submission_approval',
      'staging_approval',
      'verified_correction',
      'catalogue_change',
      'controlled_backfill'
    )
  ),
  snapshot JSONB NOT NULL CHECK (jsonb_typeof(snapshot) = 'object'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT product_score_audit_snapshots_current_input_key UNIQUE (
    product_id,
    input_fingerprint,
    score_version,
    nutrition_methodology_version,
    nutrition_transform_version,
    additive_transform_version
  )
);

COMMENT ON TABLE public.product_score_audit_snapshots IS
  'Append-only product/scoring evidence. Retention and deletion exceptions require legal/KVKK review.';
COMMENT ON COLUMN public.product_score_audit_snapshots.snapshot IS
  'Self-contained score input, canonical risk-at-time facts, components, and result. Never rewritten from live catalogues.';

CREATE INDEX product_score_audit_snapshots_product_created_idx
  ON public.product_score_audit_snapshots (product_id, created_at DESC, id DESC);

ALTER TABLE public.product_score_audit_snapshots ENABLE ROW LEVEL SECURITY;

-- There are deliberately no table policies. Mobile roles can use only the
-- narrowly scoped RPCs below; they cannot select history or forge rows.
REVOKE ALL ON TABLE public.product_score_audit_snapshots FROM PUBLIC;
REVOKE ALL ON TABLE public.product_score_audit_snapshots FROM anon;
REVOKE ALL ON TABLE public.product_score_audit_snapshots FROM authenticated;
REVOKE ALL ON TABLE public.product_score_audit_snapshots FROM service_role;
GRANT ALL ON TABLE public.product_score_audit_snapshots TO postgres;

CREATE OR REPLACE FUNCTION public.prevent_score_audit_snapshot_mutation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'score_audit_snapshot_immutable' USING ERRCODE = '55000';
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_score_audit_snapshot_mutation()
  FROM PUBLIC;

CREATE TRIGGER product_score_audit_snapshots_immutable
  BEFORE UPDATE OR DELETE ON public.product_score_audit_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.prevent_score_audit_snapshot_mutation();

CREATE OR REPLACE FUNCTION public.record_product_score_audit_snapshot(
  p_product_id UUID,
  p_input_fingerprint TEXT,
  p_snapshot_schema_version INTEGER,
  p_score_version TEXT,
  p_nutrition_methodology_version TEXT,
  p_nutrition_transform_version TEXT,
  p_additive_transform_version TEXT,
  p_trigger_source TEXT,
  p_snapshot JSONB
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_snapshot_id UUID;
  v_inserted BOOLEAN := FALSE;
  v_created_at TIMESTAMPTZ := clock_timestamp();
  v_nutrition_quality NUMERIC;
  v_additive_quality NUMERIC;
  v_nutrition_contribution NUMERIC;
  v_additive_contribution NUMERIC;
  v_final_score NUMERIC;
  v_snapshot JSONB;
  v_product_updated_at TIMESTAMPTZ;
  v_snapshot_product_updated_at TIMESTAMPTZ;
BEGIN
  -- Trusted write gate. End users cannot edit app_metadata and cannot pass it.
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT public.is_freshscan_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  SELECT updated_at
  INTO v_product_updated_at
  FROM public.products
  WHERE id = p_product_id
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found' USING ERRCODE = 'P0002';
  END IF;
  IF p_input_fingerprint IS NULL
     OR p_input_fingerprint !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'invalid_input_fingerprint' USING ERRCODE = '22023';
  END IF;
  IF p_snapshot_schema_version IS DISTINCT FROM 1
     OR p_score_version IS DISTINCT FROM 'etiketly_score_v1'
     OR p_nutrition_methodology_version IS DISTINCT FROM
        'updated_nutrition_profile_2023_v1'
     OR p_nutrition_transform_version IS DISTINCT FROM
        'nutrition_quality_transform_v1'
     OR p_additive_transform_version IS DISTINCT FROM
        'additive_quality_transform_v1' THEN
    RAISE EXCEPTION 'unsupported_score_audit_version'
      USING ERRCODE = '22023';
  END IF;
  IF p_trigger_source IS NULL OR p_trigger_source NOT IN (
    'submission_approval',
    'staging_approval',
    'verified_correction',
    'catalogue_change',
    'controlled_backfill'
  ) THEN
    RAISE EXCEPTION 'invalid_trigger_source' USING ERRCODE = '22023';
  END IF;
  IF p_snapshot IS NULL
     OR jsonb_typeof(p_snapshot) <> 'object'
     OR p_snapshot ? 'captured_at' THEN
    RAISE EXCEPTION 'invalid_snapshot_payload' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_snapshot -> 'product_updated_at') IS DISTINCT FROM
     'string' THEN
    RAISE EXCEPTION 'snapshot_product_version_missing'
      USING ERRCODE = '22023';
  END IF;
  BEGIN
    v_snapshot_product_updated_at :=
      (p_snapshot ->> 'product_updated_at')::TIMESTAMPTZ;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'snapshot_product_version_invalid'
      USING ERRCODE = '22023';
  END;
  IF v_snapshot_product_updated_at IS DISTINCT FROM v_product_updated_at THEN
    RAISE EXCEPTION 'snapshot_product_version_stale'
      USING ERRCODE = '40001';
  END IF;
  IF (p_snapshot ->> 'product_id') IS DISTINCT FROM p_product_id::TEXT
     OR (p_snapshot ->> 'input_fingerprint') IS DISTINCT FROM
        p_input_fingerprint
     OR (p_snapshot ->> 'score_version') IS DISTINCT FROM p_score_version
     OR (p_snapshot ->> 'nutrition_methodology_version') IS DISTINCT FROM
        p_nutrition_methodology_version
     OR (p_snapshot ->> 'nutrition_transform_version') IS DISTINCT FROM
        p_nutrition_transform_version
     OR (p_snapshot ->> 'additive_transform_version') IS DISTINCT FROM
        p_additive_transform_version
     OR COALESCE(p_snapshot ->> 'schema_version', '') !~ '^[0-9]+$'
     OR (p_snapshot ->> 'schema_version')::INTEGER <>
        p_snapshot_schema_version THEN
    RAISE EXCEPTION 'snapshot_metadata_mismatch' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_snapshot -> 'final_score') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_snapshot -> 'nutrition_contribution') IS DISTINCT FROM
        'number'
     OR jsonb_typeof(p_snapshot -> 'additive_contribution') IS DISTINCT FROM
        'number'
     OR jsonb_typeof(
       p_snapshot #> '{nutrition_result,nutrition_quality}'
     ) IS DISTINCT FROM 'number'
     OR jsonb_typeof(
       p_snapshot #> '{additive_result,additive_quality}'
     ) IS DISTINCT FROM 'number' THEN
    RAISE EXCEPTION 'snapshot_score_components_missing'
      USING ERRCODE = '22023';
  END IF;

  v_nutrition_quality :=
    (p_snapshot #>> '{nutrition_result,nutrition_quality}')::NUMERIC;
  v_additive_quality :=
    (p_snapshot #>> '{additive_result,additive_quality}')::NUMERIC;
  v_nutrition_contribution :=
    (p_snapshot ->> 'nutrition_contribution')::NUMERIC;
  v_additive_contribution :=
    (p_snapshot ->> 'additive_contribution')::NUMERIC;
  v_final_score := (p_snapshot ->> 'final_score')::NUMERIC;

  IF v_nutrition_quality < 0 OR v_nutrition_quality > 100
     OR v_additive_quality < 0 OR v_additive_quality > 100
     OR v_final_score < 0 OR v_final_score > 100
     OR abs(v_nutrition_contribution - (0.80 * v_nutrition_quality)) > 0.000000001
     OR abs(v_additive_contribution - (0.20 * v_additive_quality)) > 0.000000001
     OR abs(
       v_final_score -
       ((0.80 * v_nutrition_quality) + (0.20 * v_additive_quality))
     ) > 0.000000001 THEN
    RAISE EXCEPTION 'snapshot_score_reconciliation_failed'
      USING ERRCODE = '22023';
  END IF;

  v_snapshot := p_snapshot || jsonb_build_object('captured_at', v_created_at);

  INSERT INTO public.product_score_audit_snapshots (
    product_id,
    input_fingerprint,
    snapshot_schema_version,
    score_version,
    nutrition_methodology_version,
    nutrition_transform_version,
    additive_transform_version,
    trigger_source,
    snapshot,
    created_at
  ) VALUES (
    p_product_id,
    p_input_fingerprint,
    p_snapshot_schema_version,
    p_score_version,
    p_nutrition_methodology_version,
    p_nutrition_transform_version,
    p_additive_transform_version,
    p_trigger_source,
    v_snapshot,
    v_created_at
  )
  ON CONFLICT ON CONSTRAINT product_score_audit_snapshots_current_input_key
  DO NOTHING
  RETURNING id INTO v_snapshot_id;

  IF v_snapshot_id IS NOT NULL THEN
    v_inserted := TRUE;
  ELSE
    SELECT id
    INTO v_snapshot_id
    FROM public.product_score_audit_snapshots
    WHERE product_id = p_product_id
      AND input_fingerprint = p_input_fingerprint
      AND score_version = p_score_version
      AND nutrition_methodology_version = p_nutrition_methodology_version
      AND nutrition_transform_version = p_nutrition_transform_version
      AND additive_transform_version = p_additive_transform_version;
  END IF;

  RETURN jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'inserted', v_inserted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_score_audit_snapshot(
  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_score_audit_snapshot(
  UUID, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB
) TO authenticated, service_role, postgres;

CREATE OR REPLACE FUNCTION public.get_current_product_score_audit_snapshot(
  p_product_id UUID,
  p_input_fingerprint TEXT,
  p_score_version TEXT,
  p_nutrition_methodology_version TEXT,
  p_nutrition_transform_version TEXT,
  p_additive_transform_version TEXT
)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT snapshot
  FROM public.product_score_audit_snapshots
  WHERE product_id = p_product_id
    AND input_fingerprint = p_input_fingerprint
    AND score_version = p_score_version
    AND nutrition_methodology_version = p_nutrition_methodology_version
    AND nutrition_transform_version = p_nutrition_transform_version
    AND additive_transform_version = p_additive_transform_version
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_current_product_score_audit_snapshot(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_current_product_score_audit_snapshot(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT
) TO anon, authenticated, service_role, postgres;
