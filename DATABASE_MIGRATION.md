# Database Migration Guide: Table Prefixing

This guide covers the migration from unprefixed to prefixed database table names.

## What Changed

All services now use prefixed table names to avoid conflicts when sharing the PostgreSQL database:

### Controller
- `requests` → `controller_requests`
- `tags` → `controller_tags`
- `scrape_jobs` → `controller_scrape_jobs`

### Scraper
- `scraped_data` → `scraper_scraped_data`
- `images` → `scraper_images`
- `schema_version` → `scraper_schema_version`

### TextAnalyzer
- `analyses` → `textanalyzer_analyses`
- `tags` → `textanalyzer_tags`
- `text_references` → `textanalyzer_text_references`
- `schema_version` → `textanalyzer_schema_version`

### Scheduler
- `tasks` → `scheduler_tasks`
- `schema_version` → `scheduler_schema_version`

## Migration Methods

### Method 1: Helm Upgrade with Automatic Cleanup (Recommended)

The Helm chart includes a pre-upgrade hook that automatically drops old tables.

**Enable the cleanup:**

```bash
helm upgrade docutag ./chart \
  --set postgresql.cleanupOldTables=true \
  --namespace docutag
```

**How it works:**
1. Helm runs a pre-upgrade Job that connects to PostgreSQL
2. The Job executes the cleanup SQL script
3. Old unprefixed tables are dropped
4. Helm proceeds with the upgrade
5. Services start and create new prefixed tables via migrations

**Advantages:**
- ✅ Fully automated
- ✅ Runs before upgrade
- ✅ Helm manages the cleanup job
- ✅ Job is automatically deleted after success

### Method 2: Manual SQL Script

If you prefer manual control or need to run outside of Helm:

```bash
# Option A: Interactive (will prompt for password)
psql -h <host> -U <user> -d <database> -f cleanup-old-tables.sql

# Option B: Using PGPASSWORD environment variable
PGPASSWORD=<password> psql -h <host> -U <user> -d <database> -f cleanup-old-tables.sql

# Option C: For Kubernetes (with port-forward)
kubectl port-forward svc/postgres 5432:5432
PGPASSWORD=your_password psql -h localhost -U docutag -d docutag -f cleanup-old-tables.sql
```

## Important Notes

⚠️ **DATA LOSS WARNING**: Both methods will delete all data in the old tables. Only proceed if:
- You have no production data to preserve, OR
- You have backed up any data you need, OR
- You are working in a development/staging environment

⚠️ **One-Time Operation**: After the first upgrade with `cleanupOldTables: true`, set it back to `false` for subsequent upgrades.

## Verification

After the upgrade, verify that only prefixed tables exist:

```bash
kubectl exec -it <postgresql-pod> -- psql -U docutag -d docutag -c "
  SELECT tablename FROM pg_tables
  WHERE schemaname = 'public'
    AND tablename NOT LIKE 'controller_%'
    AND tablename NOT LIKE 'scraper_%'
    AND tablename NOT LIKE 'textanalyzer_%'
    AND tablename NOT LIKE 'scheduler_%';"
```

This query should return no rows if cleanup was successful.

## Rollback

If you need to rollback to the previous version with unprefixed tables:

1. Rollback the Helm release:
   ```bash
   helm rollback docutag
   ```

2. The old code expects unprefixed tables, which were dropped. You'll need to either:
   - Restore from backup, or
   - Let the old migrations recreate empty tables

## Troubleshooting

### Cleanup job fails
Check the job logs:
```bash
kubectl logs -l app=db-cleanup -n docutag
```

### Services fail to start after upgrade
Check if migrations ran successfully:
```bash
kubectl logs <pod-name> | grep -i migration
```

### Need to manually re-run cleanup
Delete the failed job and run Helm upgrade again:
```bash
kubectl delete job -l app=db-cleanup -n docutag
helm upgrade docutag ./chart --set postgresql.cleanupOldTables=true
```
