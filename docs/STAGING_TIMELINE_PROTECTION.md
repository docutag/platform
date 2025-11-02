# Staging Timeline Test Protection

## Overview

Timeline regression tests now **automatically block** staging deployments if tests fail. This prevents Timeline bugs from reaching the staging environment.

## Protected Makefile Targets

The following targets now run Timeline regression tests before executing:

### 1. `make docker-staging-build`
Builds staging Docker images.

**Test flow:**
```
make test (all services)
  ↓
Timeline stability tests (9 tests)
  ↓
Timeline regression suite (26 tests)
  ↓
Build staging images
```

**If any test fails:** Build is aborted

### 2. `make docker-staging-push`
Builds and pushes staging images to registry.

**Test flow:**
```
make test (all services)
  ↓
Timeline stability tests (9 tests)
  ↓
Timeline regression suite (26 tests)
  ↓
Build and push images to ghcr.io/zombar
```

**If any test fails:** Push is aborted

### 3. `make docker-staging-deploy`
Full local staging deployment.

**Test flow:**
```
make test (all services)
  ↓
Timeline stability tests (9 tests)
  ↓
Timeline regression suite (26 tests)
  ↓
Build images
  ↓
Start services with docker-compose
```

**If any test fails:** Deployment is aborted

### 4. `make docker-rebuild`
Rebuilds all services from scratch.

**Test flow:**
```
make test (all services)
  ↓
Timeline stability tests (9 tests)
  ↓
Timeline regression suite (26 tests)
  ↓
Stop services
  ↓
Rebuild images (no cache)
  ↓
Start services
```

**If any test fails:** Rebuild is aborted

## Usage Examples

### Safe Staging Push
```bash
$ make docker-staging-push

Running full test suite before staging push...
Running tests for all services...
✓ Controller tests passed
✓ Scraper tests passed
✓ TextAnalyzer tests passed
✓ Scheduler tests passed
✓ Web tests passed
All tests completed!

Running Timeline regression tests...
✓ Timeline.selectionStability.test.jsx (9 tests) - 287ms
✓ Timeline.regressionSuite.test.jsx (26 tests) - 981ms

✅ All tests passed! Proceeding with staging push...
Building staging images...
Pushing to ghcr.io/zombar...
✅ Complete!
```

### Blocked Staging Push (Test Failure)
```bash
$ make docker-staging-push

Running full test suite before staging push...
Running tests for all services...
✓ All service tests passed

Running Timeline regression tests...
✓ Timeline.selectionStability.test.jsx (9 tests)
✗ Timeline.regressionSuite.test.jsx (26 tests)
   FAIL: should maintain selection when documents update

❌ Tests failed! Aborting staging push.
make: *** [docker-staging-push] Error 1
```

## Benefits

### 1. Automatic Protection
- No manual test runs required
- Tests always run before staging builds
- Impossible to accidentally push broken Timeline code to staging

### 2. Fast Feedback
- Timeline tests complete in ~1.3 seconds
- Total overhead is minimal
- Fail fast if there are issues

### 3. Clear Visibility
- Explicit "Running Timeline regression tests..." message
- Clear pass/fail status
- Detailed error messages on failure

### 4. Consistent Quality
- Same tests run in CI, locally, and before staging
- Catches regressions before they reach staging
- Prevents manual testing gaps

## Integration with CI

Timeline tests also run in GitHub Actions:
- ✅ On every push to main/master/develop
- ✅ On every pull request
- ✅ Before merging is allowed

**Multi-layered protection:**
```
Local development
  ├─ make test-timeline (manual)
  └─ pre-commit hooks (optional)
       ↓
Pull Request
  ├─ GitHub Actions CI
  └─ Timeline tests in test-web job
       ↓
Staging Build
  ├─ make docker-staging-build
  ├─ make docker-staging-push
  └─ Timeline tests before build/push
       ↓
Staging Environment
```

## Bypassing Protection (Not Recommended)

If you absolutely need to skip tests (emergency only):

```bash
# DON'T DO THIS unless it's an emergency
./build-staging.sh push  # Skips tests

# Better approach: Fix the failing tests first
cd apps/web
npm test -- Timeline --ui  # Debug failing tests
```

**Warning:** Bypassing tests can introduce bugs to staging. Always fix failing tests instead.

## Debugging Test Failures

If staging build is blocked by failing Timeline tests:

```bash
# 1. Run tests locally to see the failure
cd apps/web
npm test -- Timeline --run

# 2. Run with UI for interactive debugging
npm test -- Timeline --ui

# 3. Run specific failing test
npm test -- Timeline.regressionSuite.test.jsx --run

# 4. Check what changed
git diff HEAD~1 src/components/features/Timeline.jsx

# 5. Fix the issue and re-run
make test-timeline
```

## Configuration

### Location of Timeline Tests
- `apps/web/src/components/features/Timeline.selectionStability.test.jsx`
- `apps/web/src/components/features/Timeline.regressionSuite.test.jsx`

### Location of Protection Code
- Root `Makefile` lines 213-225, 236-244, 246-254, 256-271

### Disabling Protection (Not Recommended)
To remove Timeline test protection, edit the root `Makefile` and remove these lines:
```makefile
@echo "Running Timeline regression tests..."
@cd $(WEB_DIR) && npm test -- Timeline.selectionStability.test.jsx --run
@cd $(WEB_DIR) && npm test -- Timeline.regressionSuite.test.jsx --run
```

**Warning:** Disabling protection removes a critical safety net.

## Monitoring

### Check Timeline Test Status
```bash
# Check if tests are passing
cd apps/web
make test-timeline

# Check test coverage
npm run test:coverage -- Timeline

# Check for flaky tests (run multiple times)
for i in {1..10}; do npm test -- Timeline --run || break; done
```

### Track Test Performance
```bash
# Time the tests
time make test-timeline

# Should complete in ~2 seconds or less
# If slower, investigate performance issues
```

## Maintenance

### Adding New Timeline Tests
1. Add tests to existing test files
2. No Makefile changes needed - automatically included
3. Verify tests pass: `make test-timeline`
4. Tests will automatically run in staging builds

### Updating Timeline Component
1. Make changes to `Timeline.jsx`
2. Run `make test-timeline` locally
3. Fix any failing tests
4. Commit changes
5. CI and staging protection will verify tests still pass

### Emergency Hotfix Process
If you need to hotfix staging urgently:

1. **Option A (Recommended):** Fix the tests
   ```bash
   # Fix tests first
   cd apps/web
   npm test -- Timeline --ui
   # Fix issues
   make test-timeline
   # Now push
   make docker-staging-push
   ```

2. **Option B (Emergency only):** Temporary bypass
   ```bash
   # Skip tests (DANGEROUS)
   ./build-staging.sh push
   # Create follow-up ticket to fix tests
   ```

## Related Documentation

- **Test Details:** See [apps/web/TIMELINE_REGRESSION_TESTS.md](apps/web/TIMELINE_REGRESSION_TESTS.md)
- **CI Integration:** See [apps/web/CI_INTEGRATION.md](apps/web/CI_INTEGRATION.md)
- **Bug Fix:** See [apps/web/TIMELINE_SELECTION_FIX.md](apps/web/TIMELINE_SELECTION_FIX.md)
- **Quick Summary:** See [apps/web/TIMELINE_TESTS_SUMMARY.md](apps/web/TIMELINE_TESTS_SUMMARY.md)

## Questions?

- Check failing test output for specific error messages
- Review Timeline component changes in recent commits
- Run tests with `--ui` flag for interactive debugging
- Check if similar tests are passing/failing
