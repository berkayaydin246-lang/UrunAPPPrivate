-- Additive persistence for versioned source evidence used by future scoring.
-- These nullable objects contain no calculated points, grade, or score.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS scoring_evidence JSONB;

ALTER TABLE product_staging
  ADD COLUMN IF NOT EXISTS scoring_evidence JSONB;

ALTER TABLE product_submissions
  ADD COLUMN IF NOT EXISTS scoring_evidence JSONB;

COMMENT ON COLUMN products.scoring_evidence IS
  'Versioned source-evidence snapshot; never a calculated score.';
COMMENT ON COLUMN product_staging.scoring_evidence IS
  'Versioned source-evidence snapshot preserved during staging approval.';
COMMENT ON COLUMN product_submissions.scoring_evidence IS
  'Versioned source-evidence snapshot preserved during submission approval.';
