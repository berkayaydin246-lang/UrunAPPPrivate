-- Product information reports foundation.
--
-- Secure-by-default design:
--   - direct public table access is blocked by RLS
--   - submissions go through a security definer RPC
--   - server-side snapshots are read from products during insertion

CREATE TABLE IF NOT EXISTS public.product_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  product_id UUID
    REFERENCES public.products(id)
    ON DELETE SET NULL,

  product_name_snapshot TEXT NOT NULL,
  product_brand_snapshot TEXT,
  product_image_snapshot TEXT,

  report_type TEXT NOT NULL,
  details TEXT,

  evidence_image_urls TEXT[] NOT NULL DEFAULT '{}',

  client_install_id UUID NOT NULL,
  client_submission_id UUID NOT NULL UNIQUE,

  status TEXT NOT NULL DEFAULT 'pending',

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  admin_note TEXT,

  CONSTRAINT product_reports_type_check
    CHECK (
      report_type IN (
        'wrong_image',
        'outdated_ingredients',
        'wrong_nutrition',
        'wrong_name_or_brand',
        'wrong_category',
        'wrong_barcode',
        'other'
      )
    ),

  CONSTRAINT product_reports_status_check
    CHECK (
      status IN (
        'pending',
        'reviewing',
        'resolved',
        'rejected'
      )
    ),

  CONSTRAINT product_reports_details_length_check
    CHECK (
      details IS NULL OR char_length(details) <= 1000
    ),

  CONSTRAINT product_reports_evidence_count_check
    CHECK (
      cardinality(evidence_image_urls) <= 3
    )
);

CREATE INDEX IF NOT EXISTS product_reports_status_created_idx
  ON public.product_reports(status, created_at DESC);

CREATE INDEX IF NOT EXISTS product_reports_product_idx
  ON public.product_reports(product_id);

CREATE INDEX IF NOT EXISTS product_reports_install_created_idx
  ON public.product_reports(client_install_id, created_at DESC);

ALTER TABLE public.product_reports
  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role can manage product reports" ON public.product_reports;
CREATE POLICY "service_role can manage product reports"
  ON public.product_reports
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.submit_product_report(
  p_product_id UUID,
  p_report_type TEXT,
  p_details TEXT,
  p_client_install_id UUID,
  p_client_submission_id UUID,
  p_evidence_image_urls TEXT[] DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_report public.product_reports%ROWTYPE;
  v_product public.products%ROWTYPE;
  v_trimmed_details TEXT;
  v_evidence_image_urls TEXT[];
  v_report public.product_reports%ROWTYPE;
  v_recent_count INTEGER;
BEGIN
  IF p_product_id IS NULL THEN
    RAISE EXCEPTION 'invalid_product_id' USING ERRCODE = '22023';
  END IF;

  IF p_client_install_id IS NULL THEN
    RAISE EXCEPTION 'invalid_client_install_id' USING ERRCODE = '22023';
  END IF;

  IF p_client_submission_id IS NULL THEN
    RAISE EXCEPTION 'invalid_client_submission_id' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_existing_report
  FROM public.product_reports
  WHERE client_submission_id = p_client_submission_id;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'report_id', v_existing_report.id,
      'submitted_at', v_existing_report.created_at
    );
  END IF;

  IF p_report_type IS NULL OR p_report_type NOT IN (
    'wrong_image',
    'outdated_ingredients',
    'wrong_nutrition',
    'wrong_name_or_brand',
    'wrong_category',
    'wrong_barcode',
    'other'
  ) THEN
    RAISE EXCEPTION 'invalid_report_type' USING ERRCODE = '22023';
  END IF;

  v_trimmed_details := NULLIF(btrim(COALESCE(p_details, '')), '');
  IF v_trimmed_details IS NOT NULL AND char_length(v_trimmed_details) > 1000 THEN
    RAISE EXCEPTION 'details_too_long' USING ERRCODE = '22023';
  END IF;

  v_evidence_image_urls := COALESCE(
    ARRAY(
      SELECT trimmed_url
      FROM (
        SELECT NULLIF(btrim(url), '') AS trimmed_url
        FROM unnest(COALESCE(p_evidence_image_urls, ARRAY[]::TEXT[])) AS url
      ) normalized_urls
      WHERE trimmed_url IS NOT NULL
    ),
    ARRAY[]::TEXT[]
  );

  IF COALESCE(cardinality(v_evidence_image_urls), 0) > 3 THEN
    RAISE EXCEPTION 'too_many_evidence_images' USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_product
  FROM public.products
  WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.product_reports
    WHERE client_install_id = p_client_install_id
      AND product_id = p_product_id
      AND report_type = p_report_type
      AND created_at >= now() - INTERVAL '24 hours'
  ) THEN
    RAISE EXCEPTION 'duplicate_recent_report' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)
  INTO v_recent_count
  FROM public.product_reports
  WHERE client_install_id = p_client_install_id
    AND created_at >= now() - INTERVAL '24 hours';

  IF v_recent_count >= 10 THEN
    RAISE EXCEPTION 'report_rate_limited' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.product_reports (
    product_id,
    product_name_snapshot,
    product_brand_snapshot,
    product_image_snapshot,
    report_type,
    details,
    evidence_image_urls,
    client_install_id,
    client_submission_id,
    status
  )
  VALUES (
    v_product.id,
    v_product.name,
    v_product.brand,
    v_product.image_url,
    p_report_type,
    v_trimmed_details,
    v_evidence_image_urls,
    p_client_install_id,
    p_client_submission_id,
    'pending'
  )
  RETURNING *
  INTO v_report;

  RETURN jsonb_build_object(
    'report_id', v_report.id,
    'submitted_at', v_report.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO anon;
GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_product_report(UUID, TEXT, TEXT, UUID, UUID, TEXT[]) TO service_role;
