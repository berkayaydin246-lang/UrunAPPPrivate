-- Add source tracking fields to scan_logs for OFF import analytics
ALTER TABLE scan_logs
  ADD COLUMN IF NOT EXISTS source_used TEXT,
  ADD COLUMN IF NOT EXISTS imported_from_off BOOLEAN NOT NULL DEFAULT false;
