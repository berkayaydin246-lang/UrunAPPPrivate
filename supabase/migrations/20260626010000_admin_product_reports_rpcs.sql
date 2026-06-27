-- =============================================================================
-- Admin RPCs for the product_reports review workflow.
--
-- Security model
-- ──────────────
--   • is_freshscan_admin() is the single source of truth for admin access.
--     It reads auth.jwt() -> 'app_metadata' ->> 'role', a server-managed
--     server-managed claim that end-users cannot self-edit.
--   • All three admin RPCs call is_freshscan_admin() as the very first
--     statement and raise 'not_authorized' (SQLSTATE 42501) on failure.
--   • All admin RPCs are SECURITY DEFINER with a fixed, safe search_path.
--   • REVOKE ALL ... FROM PUBLIC is applied to every function before any
--     targeted GRANTs; admin RPCs are never granted to anon or PUBLIC.
--   • product_reports has no direct authenticated RLS policy — the sole
--     policy from the prior migration grants only service_role.
--
-- Provisioning admin accounts (safe steps — no service-role key in client)
-- ──────────────────────────────────────────────────────────────────────────
--   Option A — Supabase Dashboard:
--     Auth → Users → select user → Edit → App Metadata section →
--     set  { "role": "admin" }  under App Metadata (the trusted server field).
--
--   Option B — Supabase Management API (from a trusted backend only):
--     PATCH /v1/projects/{ref}/auth/users/{user_id}
--     Authorization: Bearer <service-role-key>
--     Content-Type: application/json
--     Body: { "app_metadata": { "role": "admin" } }
--
--   Never commit the service-role key in any client code or repository.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Admin authorization helper
--
--   SECURITY INVOKER — runs with the caller's privilege context so that
--   auth.uid() and auth.jwt() resolve to the actual request's session.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_freshscan_admin()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND COALESCE(
      (auth.jwt() -> 'app_metadata' ->> 'role'),
      ''
    ) = 'admin';
$$;

REVOKE ALL ON FUNCTION public.is_freshscan_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_freshscan_admin()
  TO authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- admin_list_product_reports
--
-- Returns a JSONB array of report summaries.  Uses keyset pagination on
-- (created_at DESC, id DESC) to guarantee no duplicate or missing rows even
-- when multiple reports share the same timestamp.
--
-- Parameters
--   p_status            — filter to one status; NULL returns all statuses
--   p_limit             — page size; clamped to [1, 100]; default 30
--   p_before_created_at — cursor: created_at of the last row on prev page
--   p_before_id         — cursor: id of the last row on prev page
--
-- Fields NOT returned: client_install_id, client_submission_id (anti-spam).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_list_product_reports(
  p_status            TEXT         DEFAULT NULL,
  p_limit             INTEGER      DEFAULT 30,
  p_before_created_at TIMESTAMPTZ  DEFAULT NULL,
  p_before_id         UUID         DEFAULT NULL
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit INTEGER;
  v_rows  JSONB;
BEGIN
  -- ① Admin-only gate (must be first)
  IF NOT public.is_freshscan_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- ② Validate status value
  IF p_status IS NOT NULL
     AND p_status NOT IN ('pending', 'reviewing', 'resolved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;

  -- ③ Clamp limit to [1, 100]
  v_limit := GREATEST(1, LEAST(100, COALESCE(p_limit, 30)));

  -- ④ Keyset-paginated fetch then aggregate into JSON array
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id',                        r.id,
        'product_id',                r.product_id,
        'product_name_snapshot',     r.product_name_snapshot,
        'product_brand_snapshot',    r.product_brand_snapshot,
        'product_image_snapshot',    r.product_image_snapshot,
        'report_type',               r.report_type,
        'details',                   r.details,
        'evidence_image_count',      cardinality(r.evidence_image_urls),
        'status',                    r.status,
        'created_at',                r.created_at,
        'reviewed_at',               r.reviewed_at,
        'current_product_name',      p.name,
        'current_product_brand',     p.brand,
        'current_product_image_url', p.image_url
      )
      ORDER BY r.created_at DESC, r.id DESC
    ),
    '[]'::JSONB
  )
  INTO v_rows
  FROM (
    SELECT
      pr.id,
      pr.product_id,
      pr.product_name_snapshot,
      pr.product_brand_snapshot,
      pr.product_image_snapshot,
      pr.report_type,
      pr.details,
      pr.evidence_image_urls,
      pr.status,
      pr.created_at,
      pr.reviewed_at
    FROM public.product_reports pr
    WHERE
      (p_status IS NULL OR pr.status = p_status)
      AND (
        -- No cursor → first page
        p_before_created_at IS NULL
        OR p_before_id IS NULL
        -- Keyset: strictly older timestamp, or same timestamp with smaller UUID
        OR pr.created_at < p_before_created_at
        OR (pr.created_at = p_before_created_at AND pr.id < p_before_id)
      )
    ORDER BY pr.created_at DESC, pr.id DESC
    LIMIT v_limit
  ) r
  LEFT JOIN public.products p ON p.id = r.product_id;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_product_reports(TEXT, INTEGER, TIMESTAMPTZ, UUID)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_product_reports(TEXT, INTEGER, TIMESTAMPTZ, UUID)
  TO authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- admin_get_product_report
--
-- Returns the full detail for one report, including evidence image URLs,
-- admin note, reviewer identity, and current product data from the catalog.
-- Raises 'report_not_found' if the ID is unknown.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_get_product_report(
  p_report_id UUID
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_report JSONB;
BEGIN
  -- ① Admin-only gate
  IF NOT public.is_freshscan_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- ② Fetch report + current product snapshot
  SELECT jsonb_build_object(
    'id',                        pr.id,
    'product_id',                pr.product_id,
    'product_name_snapshot',     pr.product_name_snapshot,
    'product_brand_snapshot',    pr.product_brand_snapshot,
    'product_image_snapshot',    pr.product_image_snapshot,
    'report_type',               pr.report_type,
    'details',                   pr.details,
    'evidence_image_urls',       pr.evidence_image_urls,
    'evidence_image_count',      cardinality(pr.evidence_image_urls),
    'status',                    pr.status,
    'admin_note',                pr.admin_note,
    'created_at',                pr.created_at,
    'reviewed_at',               pr.reviewed_at,
    'reviewed_by',               pr.reviewed_by,
    'current_product_name',      p.name,
    'current_product_brand',     p.brand,
    'current_product_image_url', p.image_url,
    'current_product_barcode',   p.barcode
  )
  INTO v_report
  FROM public.product_reports pr
  LEFT JOIN public.products p ON p.id = pr.product_id
  WHERE pr.id = p_report_id;

  IF v_report IS NULL THEN
    RAISE EXCEPTION 'report_not_found' USING ERRCODE = '22023';
  END IF;

  RETURN v_report;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_product_report(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_product_report(UUID)
  TO authenticated, service_role, postgres;

-- ---------------------------------------------------------------------------
-- admin_update_product_report
--
-- Updates status and/or admin note on one report, then returns the full
-- detail (identical to admin_get_product_report output).
--
-- Allowed transitions
--   pending   → reviewing | resolved | rejected
--   reviewing → pending   | resolved | rejected
--   resolved  → reviewing
--   rejected  → reviewing
--   any       → same      (self-transition, useful for note-only updates)
--
-- Review metadata (reviewed_by, reviewed_at)
--   Set to auth.uid() / now() when transitioning TO reviewing, resolved,
--   or rejected.  Preserved without change when returning to pending or
--   on a self-transition.
--
-- Admin note
--   Updated to p_admin_note (trimmed) when non-empty.
--   Existing note is preserved when p_admin_note is null or blank.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_update_product_report(
  p_report_id  UUID,
  p_status     TEXT,
  p_admin_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_current_status TEXT;
  v_trimmed_note   TEXT;
BEGIN
  -- ① Admin-only gate (must be first)
  IF NOT public.is_freshscan_admin() THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  -- ② Validate target status
  IF p_status NOT IN ('pending', 'reviewing', 'resolved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;

  -- ③ Trim and validate admin note length (max 2000 chars)
  v_trimmed_note := NULLIF(TRIM(COALESCE(p_admin_note, '')), '');
  IF v_trimmed_note IS NOT NULL AND char_length(v_trimmed_note) > 2000 THEN
    RAISE EXCEPTION 'admin_note_too_long' USING ERRCODE = '22023';
  END IF;

  -- ④ Lock and fetch current status
  SELECT status
  INTO   v_current_status
  FROM   public.product_reports
  WHERE  id = p_report_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'report_not_found' USING ERRCODE = '22023';
  END IF;

  -- ⑤ Validate transition
  IF NOT (
    v_current_status = p_status                                                      -- self-transition
    OR (v_current_status = 'pending'   AND p_status IN ('reviewing', 'resolved', 'rejected'))
    OR (v_current_status = 'reviewing' AND p_status IN ('pending',   'resolved', 'rejected'))
    OR (v_current_status = 'resolved'  AND p_status = 'reviewing')
    OR (v_current_status = 'rejected'  AND p_status = 'reviewing')
  ) THEN
    RAISE EXCEPTION 'invalid_status_transition' USING ERRCODE = '22023';
  END IF;

  -- ⑥ Apply update
  UPDATE public.product_reports
  SET
    status      = p_status,
    -- Preserve existing note if no new note is supplied
    admin_note  = COALESCE(v_trimmed_note, admin_note),
    -- Record reviewer on forward progress; preserve on return-to-pending
    reviewed_by = CASE
                    WHEN p_status IN ('reviewing', 'resolved', 'rejected') THEN auth.uid()
                    ELSE reviewed_by
                  END,
    reviewed_at = CASE
                    WHEN p_status IN ('reviewing', 'resolved', 'rejected') THEN now()
                    ELSE reviewed_at
                  END
  WHERE id = p_report_id;

  -- ⑦ Return full detail
  RETURN public.admin_get_product_report(p_report_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_product_report(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_product_report(UUID, TEXT, TEXT)
  TO authenticated, service_role, postgres;
