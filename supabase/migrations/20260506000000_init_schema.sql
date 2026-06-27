-- Initial database schema for Food Analyzer App
-- Tables: categories, products, ingredients, product_ingredients, product_reviews, user_submissions, scan_logs

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- CATEGORIES TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  parent_id UUID REFERENCES categories(id) ON DELETE SET NULL,
  default_processing_level TEXT,
  default_warning TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_categories_name ON categories(name);
CREATE INDEX idx_categories_parent_id ON categories(parent_id);

-- ============================================================================
-- PRODUCTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode TEXT UNIQUE,
  name TEXT NOT NULL,
  normalized_name TEXT,
  brand TEXT,
  category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
  image_url TEXT,
  ingredients_text TEXT,
  nutrition_text TEXT,
  source TEXT,
  source_url TEXT,
  verification_status TEXT DEFAULT 'pending' CHECK (verification_status IN ('verified', 'pending', 'imported', 'user_submitted', 'rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_products_normalized_name ON products(normalized_name);
CREATE INDEX idx_products_category_id ON products(category_id);
CREATE INDEX idx_products_verification_status ON products(verification_status);
CREATE INDEX idx_products_created_at ON products(created_at);

-- ============================================================================
-- INGREDIENTS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  alternative_names TEXT[],
  e_code TEXT,
  category TEXT,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'unknown')),
  short_description TEXT,
  long_description TEXT,
  source_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ingredients_name ON ingredients(name);
CREATE INDEX idx_ingredients_normalized_name ON ingredients(normalized_name);
CREATE INDEX idx_ingredients_e_code ON ingredients(e_code);
CREATE INDEX idx_ingredients_risk_level ON ingredients(risk_level);

-- ============================================================================
-- PRODUCT_INGREDIENTS TABLE (junction table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  ingredient_id UUID NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  raw_text TEXT,
  detected_from TEXT,
  confidence_score NUMERIC(3, 2),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_product_ingredient UNIQUE (product_id, ingredient_id)
);

CREATE INDEX idx_product_ingredients_product_id ON product_ingredients(product_id);
CREATE INDEX idx_product_ingredients_ingredient_id ON product_ingredients(ingredient_id);

-- ============================================================================
-- PRODUCT_REVIEWS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  score_label TEXT NOT NULL CHECK (score_label IN ('iyi_secim', 'orta', 'dikkatli_tuket', 'sik_tuketme')),
  summary TEXT,
  warning_text TEXT,
  positive_points TEXT[],
  negative_points TEXT[],
  consumption_advice TEXT,
  suitable_for_children BOOLEAN,
  review_status TEXT DEFAULT 'draft' CHECK (review_status IN ('draft', 'published', 'archived')),
  reviewed_by UUID,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_product_reviews_product_id ON product_reviews(product_id);
CREATE INDEX idx_product_reviews_score_label ON product_reviews(score_label);
CREATE INDEX idx_product_reviews_review_status ON product_reviews(review_status);

-- ============================================================================
-- USER_SUBMISSIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_submissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  barcode TEXT,
  product_name TEXT,
  front_image_url TEXT,
  ingredients_image_url TEXT,
  nutrition_image_url TEXT,
  ocr_text TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'needs_more_info')),
  admin_note TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_submissions_user_id ON user_submissions(user_id);
CREATE INDEX idx_user_submissions_barcode ON user_submissions(barcode);
CREATE INDEX idx_user_submissions_status ON user_submissions(status);
CREATE INDEX idx_user_submissions_created_at ON user_submissions(created_at);

-- ============================================================================
-- SCAN_LOGS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS scan_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  input_type TEXT NOT NULL CHECK (input_type IN ('search', 'barcode', 'ocr')),
  query_text TEXT,
  barcode TEXT,
  product_id UUID REFERENCES products(id) ON DELETE SET NULL,
  result_status TEXT NOT NULL CHECK (result_status IN ('found', 'not_found', 'error')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_scan_logs_user_id ON scan_logs(user_id);
CREATE INDEX idx_scan_logs_input_type ON scan_logs(input_type);
CREATE INDEX idx_scan_logs_product_id ON scan_logs(product_id);
CREATE INDEX idx_scan_logs_created_at ON scan_logs(created_at);

-- ============================================================================
-- TRIGGER: Auto-update updated_at timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to tables with timestamp
CREATE TRIGGER categories_update_timestamp BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER products_update_timestamp BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER ingredients_update_timestamp BEFORE UPDATE ON ingredients FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER product_ingredients_update_timestamp BEFORE UPDATE ON product_ingredients FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER product_reviews_update_timestamp BEFORE UPDATE ON product_reviews FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER user_submissions_update_timestamp BEFORE UPDATE ON user_submissions FOR EACH ROW EXECUTE FUNCTION update_timestamp();
