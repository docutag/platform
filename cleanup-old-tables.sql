-- Cleanup script for dropping old unprefixed database tables
-- Run this BEFORE deploying the new version with prefixed table names
--
-- WARNING: This will delete all data in these tables!
-- Only run this in staging/development or if you're certain you want to lose all data.
--
-- Usage:
-- Interactive (will prompt for password):
--   psql -h <host> -U <user> -d <database> -f cleanup-old-tables.sql
--
-- With password from environment:
--   PGPASSWORD=<password> psql -h <host> -U <user> -d <database> -f cleanup-old-tables.sql
--
-- Example for Kubernetes port-forward:
--   kubectl port-forward svc/postgres 5432:5432
--   PGPASSWORD=your_password psql -h localhost -U docutag -d docutag -f cleanup-old-tables.sql

-- Drop indexes first to avoid dependency issues
DROP INDEX IF EXISTS idx_tasks_enabled;
DROP INDEX IF EXISTS idx_tasks_next_run_at;
DROP INDEX IF EXISTS idx_images_scrape_id;
DROP INDEX IF EXISTS idx_images_created_at;
DROP INDEX IF EXISTS idx_images_url;
DROP INDEX IF EXISTS idx_images_slug;
DROP INDEX IF EXISTS idx_scraper_scraped_data_url;
DROP INDEX IF EXISTS idx_scraper_scraped_data_created_at;
DROP INDEX IF EXISTS idx_scraper_scraped_data_slug;
DROP INDEX IF EXISTS idx_textanalyzer_analyses_created_at;
DROP INDEX IF EXISTS idx_textanalyzer_analyses_processing_stage;
DROP INDEX IF EXISTS idx_textanalyzer_analyses_enqueued_at;
DROP INDEX IF EXISTS idx_textanalyzer_tags_analysis_id;
DROP INDEX IF EXISTS idx_textanalyzer_tags_tag;
DROP INDEX IF EXISTS idx_textanalyzer_text_references_analysis_id;
DROP INDEX IF EXISTS idx_textanalyzer_text_references_text;
DROP INDEX IF EXISTS idx_textanalyzer_text_references_type;
DROP INDEX IF EXISTS idx_requests_created_at;
DROP INDEX IF EXISTS idx_requests_source_url;
DROP INDEX IF EXISTS idx_requests_scraper_uuid;
DROP INDEX IF EXISTS idx_requests_textanalyzer_uuid;
DROP INDEX IF EXISTS idx_tags_request_id;
DROP INDEX IF EXISTS idx_tags_tag;
DROP INDEX IF EXISTS idx_scrape_jobs_created_at;
DROP INDEX IF EXISTS idx_scrape_jobs_status;
DROP INDEX IF EXISTS idx_scrape_jobs_parent_job_id;
DROP INDEX IF EXISTS idx_scrape_jobs_result_request_id;

-- Drop Scheduler tables
DROP TABLE IF EXISTS tasks CASCADE;

-- Drop Scraper tables (images must be dropped before scraped_data due to foreign key)
DROP TABLE IF EXISTS images CASCADE;
DROP TABLE IF EXISTS scraped_data CASCADE;

-- Drop TextAnalyzer tables (tags and text_references must be dropped before analyses due to foreign keys)
DROP TABLE IF EXISTS text_references CASCADE;
DROP TABLE IF EXISTS tags CASCADE;
DROP TABLE IF EXISTS analyses CASCADE;

-- Drop Controller tables (tags and scrape_jobs must be dropped before requests due to foreign keys)
DROP TABLE IF EXISTS scrape_jobs CASCADE;
-- Note: Can't drop 'tags' again if it was already dropped above for textanalyzer
-- Since both used the same name, it would already be gone
DROP TABLE IF EXISTS requests CASCADE;

-- Drop all old schema version tables
DROP TABLE IF EXISTS schema_version CASCADE;
DROP TABLE IF EXISTS schema_migrations CASCADE;
DROP TABLE IF EXISTS controller_schema_version CASCADE;

-- Verify cleanup
-- After running this script, run this query to confirm all old tables are gone:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public'
--   AND tablename NOT LIKE 'controller_%'
--   AND tablename NOT LIKE 'scraper_%'
--   AND tablename NOT LIKE 'textanalyzer_%'
--   AND tablename NOT LIKE 'scheduler_%';
