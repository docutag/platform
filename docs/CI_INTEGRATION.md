# Timeline Regression Tests - CI/CD Integration

## Overview

The Timeline regression test suite has been integrated into the CI/CD pipeline and Makefile to ensure tests run automatically on every commit and can be easily run locally during development.

## CI Integration

### GitHub Actions Workflows

#### 1. `.github/workflows/test-web.yml`
Runs on pushes and PRs that affect the web app.

**Timeline Test Step (line 52-58):**
```yaml
- name: Run Timeline regression tests
  run: |
    echo "Running Timeline selection stability tests..."
    npm test -- Timeline.selectionStability.test.jsx --run
    echo "Running Timeline regression suite..."
    npm test -- Timeline.regressionSuite.test.jsx --run
    echo "✅ All Timeline regression tests passed!"
```

**When it runs:**
- On push to `main`, `master`, or `develop` branches (when web app changes)
- On pull requests targeting those branches (when web app changes)
- On manual workflow dispatch

**What it does:**
1. Runs all unit tests (`npm test`)
2. **Explicitly runs Timeline stability tests** (9 tests)
3. **Explicitly runs Timeline regression suite** (26 tests)
4. Runs coverage tests (if configured)
5. Builds the application
6. Runs Playwright E2E tests

**Test Matrix:**
- Node.js 20
- Node.js 24

#### 2. `.github/workflows/ci.yml`
Runs on all pushes and PRs, with change detection to only test affected apps.

**Timeline Test Step (line 180-186):**
```yaml
- name: Run Timeline regression tests
  run: |
    echo "Running Timeline selection stability tests..."
    npm test -- Timeline.selectionStability.test.jsx --run
    echo "Running Timeline regression suite..."
    npm test -- Timeline.regressionSuite.test.jsx --run
    echo "✅ All Timeline regression tests passed!"
```

**When it runs:**
- On all pushes to `main`, `master`, or `develop` branches
- On all pull requests targeting those branches
- Only runs if web app files changed (path filter: `apps/web/**`)

**What it does:**
1. Detects which apps changed
2. If web app changed:
   - Runs all unit tests
   - **Explicitly runs Timeline regression tests**
3. Summary job aggregates results from all services

### Why Explicit Timeline Test Steps?

Even though Timeline tests are included in `npm test`, we added explicit steps because:

1. **Visibility** - Timeline tests are clearly shown in CI logs
2. **Traceability** - Easy to see if Timeline regressions failed specifically
3. **Documentation** - Makes it obvious these tests are important
4. **Debugging** - Separate step makes logs easier to search
5. **Future-proofing** - Can add Timeline-specific failure handling if needed

### CI Test Flow

```
┌─────────────────────────────────────────┐
│  Push to main/master/develop OR PR      │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  Detect Changes (ci.yml)                │
│  - Check if apps/web/** changed         │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  test-web Job                           │
│  ├─ Setup Node.js (v20 & v24)          │
│  ├─ Install dependencies                │
│  ├─ Lint (if configured)                │
│  ├─ Type check (if configured)          │
│  ├─ Run all unit tests ✓                │
│  ├─ Run Timeline stability tests ✓      │  ← NEW
│  ├─ Run Timeline regression suite ✓     │  ← NEW
│  ├─ Run coverage (if configured)        │
│  ├─ Build application                   │
│  └─ Run E2E tests (Playwright)          │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  ci-success Job                         │
│  - Verify all tests passed              │
│  - Block merge if any test failed       │
└─────────────────────────────────────────┘
```

## Makefile Integration

### Root Makefile - Staging Build Protection

The root `Makefile` now runs Timeline regression tests before building or pushing staging images:

**Targets with Timeline tests:**
- `make docker-staging-build` - Build staging images (lines 236-244)
- `make docker-staging-push` - Build and push staging images (lines 246-254)
- `make docker-staging-deploy` - Full staging deployment (lines 256-271)
- `make docker-rebuild` - Rebuild all services (lines 213-225)

**Example flow for `make docker-staging-push`:**
```bash
$ make docker-staging-push

Running full test suite before staging push...
✓ All service tests pass

Running Timeline regression tests...
✓ Timeline.selectionStability.test.jsx (9 tests)
✓ Timeline.regressionSuite.test.jsx (26 tests)

✅ All tests passed! Proceeding with staging push...
Building and pushing images...
```

**Impact:** Timeline regressions are now **blocked from reaching staging** automatically.

### Web Makefile - Developer Convenience

The Makefile in `apps/web/Makefile` now includes three new targets for Timeline tests:

#### `make test-timeline`
Runs both Timeline test suites with formatted output.

```bash
make test-timeline
```

**Output:**
```
Running Timeline tests...
=== Timeline Selection Stability Tests ===
✓ 9 tests passed

=== Timeline Regression Suite ===
✓ 26 tests passed

✅ All Timeline regression tests passed!
```

**Use case:** Pre-commit checks, local validation before pushing

#### `make test-timeline-stability`
Runs only the Timeline selection stability tests (9 tests).

```bash
make test-timeline-stability
```

**Output:**
```
Running Timeline selection stability tests...
✓ 9 tests passed
```

**Use case:** Quick check after Timeline changes, debugging specific issues

#### `make test-timeline-regression`
Runs only the comprehensive Timeline regression suite (26 tests).

```bash
make test-timeline-regression
```

**Output:**
```
Running Timeline regression suite...
✓ 26 tests passed
```

**Use case:** Full regression check before releases, comprehensive validation

### Updated Help Menu

The `make help` command now includes Timeline test targets:

```bash
$ make help
Available targets:
  install                  - Install dependencies
  dev                      - Start development server
  build                    - Build for production
  test                     - Run unit tests
  test-ui                  - Run unit tests with UI
  test-coverage            - Run unit tests with coverage
  test-timeline            - Run all Timeline tests (stability + regression)    ← NEW
  test-timeline-stability  - Run Timeline selection stability tests             ← NEW
  test-timeline-regression - Run Timeline regression suite                      ← NEW
  test-e2e                 - Run E2E tests (Playwright)
  test-e2e-ui              - Run E2E tests with UI
  test-e2e-headed          - Run E2E tests in headed mode
  test-e2e-debug           - Run E2E tests in debug mode
  test-e2e-report          - Show Playwright report
  test-all                 - Run all tests (unit + e2e)
  lint                     - Lint code
  clean                    - Clean build artifacts and cache
```

## Local Development Workflow

### Pre-commit Workflow

Before committing Timeline-related changes:

```bash
cd apps/web

# Quick check - runs stability tests only (9 tests, ~1 second)
make test-timeline-stability

# Full check - runs all Timeline tests (35 tests, ~2 seconds)
make test-timeline
```

### Pre-push Workflow

Before pushing to remote:

```bash
# From project root
make test  # Run all unit tests including Timeline tests

# Or run full suite including E2E
make test-all
```

### Pre-staging Workflow

Before building/pushing staging images:

```bash
# From project root

# Build staging images (runs ALL tests including Timeline)
make docker-staging-build

# Build and push staging images (runs ALL tests including Timeline)
make docker-staging-push

# Full staging deployment (runs ALL tests including Timeline)
make docker-staging-deploy
```

**Note:** These targets automatically run Timeline tests - you don't need to run them separately!

### Debugging Workflow

When investigating Timeline issues:

```bash
# Run specific test suite with UI
npm test -- Timeline.selectionStability.test.jsx --ui

# Run with watch mode
npm test -- Timeline --watch

# Run with verbose output
npm test -- Timeline.regressionSuite.test.jsx --run --reporter=verbose
```

## Files Modified

### 1. Root `Makefile`
**Lines 236-244:** Added Timeline tests to `docker-staging-build`
**Lines 246-254:** Added Timeline tests to `docker-staging-push`
**Lines 256-271:** Added Timeline tests to `docker-staging-deploy`
**Lines 213-225:** Added Timeline tests to `docker-rebuild`

```makefile
docker-staging-push:
	@$(MAKE) test
	@echo "Running Timeline regression tests..."
	@cd $(WEB_DIR) && npm test -- Timeline.selectionStability.test.jsx --run
	@cd $(WEB_DIR) && npm test -- Timeline.regressionSuite.test.jsx --run
	@echo "✅ All tests passed! Proceeding with staging push..."
	@./build-staging.sh push
```

### 2. `.github/workflows/test-web.yml`
**Lines 52-58:** Added explicit Timeline regression test step

```yaml
- name: Run Timeline regression tests
  run: |
    echo "Running Timeline selection stability tests..."
    npm test -- Timeline.selectionStability.test.jsx --run
    echo "Running Timeline regression suite..."
    npm test -- Timeline.regressionSuite.test.jsx --run
    echo "✅ All Timeline regression tests passed!"
```

### 2. `.github/workflows/ci.yml`
**Lines 180-186:** Added explicit Timeline regression test step

```yaml
- name: Run Timeline regression tests
  run: |
    echo "Running Timeline selection stability tests..."
    npm test -- Timeline.selectionStability.test.jsx --run
    echo "Running Timeline regression suite..."
    npm test -- Timeline.regressionSuite.test.jsx --run
    echo "✅ All Timeline regression tests passed!"
```

### 4. `apps/web/Makefile`
**Lines 3:** Added `.PHONY` declarations for new targets
**Lines 14-16:** Added help text for new targets
**Lines 60-78:** Added three new test targets:
- `test-timeline`
- `test-timeline-stability`
- `test-timeline-regression`

## Test Coverage in CI

### Current Coverage

✅ **All 35 Timeline regression tests run on:**
- Every push to main/master/develop (if web app changed)
- Every pull request (if web app changed)
- Manual workflow dispatch
- Two Node.js versions (20 & 24)

### Test Timing

- **Timeline stability tests:** ~300ms (9 tests)
- **Timeline regression suite:** ~1000ms (26 tests)
- **Total Timeline tests:** ~1.3 seconds (35 tests)
- **Total CI time impact:** ~2.6 seconds (runs in both workflows)

### Failure Handling

If Timeline tests fail:
1. CI job fails immediately
2. Pull request cannot be merged
3. Detailed logs show which specific test failed
4. Developer is notified via GitHub

## Monitoring & Maintenance

### Viewing Test Results

**In GitHub Actions:**
1. Go to repository → Actions tab
2. Click on workflow run
3. Expand "Run Timeline regression tests" step
4. View detailed output for each test suite

**In Pull Requests:**
1. CI checks appear at bottom of PR
2. Click "Details" next to "test-web" or "CI / test-web"
3. View Timeline test output in logs

### Performance Monitoring

If Timeline tests become slow:
- Check test duration in CI logs
- Investigate specific slow tests
- Consider splitting or optimizing tests
- Update timeout values if needed

### Adding New Tests

When adding new Timeline tests:
1. Add tests to existing test files
2. No CI changes needed - tests run automatically
3. Update test count in documentation
4. Consider if new test categories warrant new Makefile targets

### Removing/Skipping Tests

To temporarily skip tests (not recommended):
```javascript
describe.skip('Test category', () => {
  // Tests skipped
});

it.skip('specific test', () => {
  // Test skipped
});
```

**Warning:** Skipped tests still count as passing in CI. Only skip temporarily during debugging.

## Troubleshooting

### CI Failing But Local Tests Pass

1. Check Node.js version mismatch
2. Run tests with CI environment variable:
   ```bash
   CI=true npm test -- Timeline --run
   ```
3. Clear npm cache and reinstall:
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```

### Makefile Target Not Found

```bash
make: *** No rule to make target 'test-timeline'
```

**Solution:** Ensure you're in `apps/web` directory:
```bash
cd apps/web
make test-timeline
```

### Tests Timing Out in CI

If tests timeout (rare):
1. Check for infinite loops in test code
2. Verify `disableLiveUpdate={true}` is set in tests
3. Increase timeout in vitest config if needed

### Duplicate Key Warnings

Tests show React warnings about duplicate keys. This is expected in tests and intentional - we're testing how the component handles document updates with overlapping IDs.

**Not an error** - tests still pass correctly.

## Best Practices

### For Contributors

1. **Always run Timeline tests locally** before pushing Timeline changes
   ```bash
   make test-timeline
   ```

2. **Add tests for new features** - Add to appropriate test file
   ```javascript
   it('should handle new feature', async () => {
     // Test implementation
   });
   ```

3. **Update documentation** when adding new test categories

4. **Check CI logs** if tests fail - detailed output shows exact failure

### For Reviewers

1. **Verify Timeline tests pass** in CI before approving PRs
2. **Check test coverage** for new Timeline features
3. **Ensure new tests follow patterns** in existing test files
4. **Validate test descriptions** are clear and specific

### For Maintainers

1. **Monitor test performance** - Keep tests under 2 seconds total
2. **Update Node.js versions** in CI when upgrading
3. **Review test failures** - Don't ignore flaky tests
4. **Document breaking changes** that affect Timeline tests

## Summary

### What Was Added

✅ **CI Integration:**
- Explicit Timeline test steps in `test-web.yml` and `ci.yml`
- Clear logging and failure messages
- Runs on all web app changes

✅ **Root Makefile Integration (Staging Protection):**
- Timeline tests added to `docker-staging-build`
- Timeline tests added to `docker-staging-push`
- Timeline tests added to `docker-staging-deploy`
- Timeline tests added to `docker-rebuild`
- **Prevents Timeline regressions from reaching staging**

✅ **Web Makefile Integration (Developer Convenience):**
- 3 new targets: `test-timeline`, `test-timeline-stability`, `test-timeline-regression`
- Updated help menu
- Formatted output for better readability

✅ **Documentation:**
- This CI integration guide
- Workflow diagrams
- Troubleshooting section
- Best practices

### Impact

- ✅ **35 regression tests** run automatically on every commit
- ✅ **35 regression tests** run before every staging build/push
- ✅ **Zero manual intervention** required
- ✅ **Clear visibility** into test results
- ✅ **Prevents regressions** from reaching staging or production
- ✅ **Fast feedback** - tests complete in ~2 seconds
- ✅ **Easy local testing** with simple `make` commands
- ✅ **Staging builds blocked** if Timeline tests fail

### Next Steps

Consider adding:
- [ ] Timeline test results badge in README
- [ ] Slack/email notifications for Timeline test failures
- [ ] Performance tracking for Timeline tests over time
- [ ] Automated test report generation
