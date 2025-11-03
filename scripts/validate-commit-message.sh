#!/bin/bash
set -e

# Validates commit messages follow Conventional Commits format
# https://www.conventionalcommits.org/

COMMIT_MSG="$1"

# Allow merge commits and revert commits
if echo "$COMMIT_MSG" | grep -qE "^Merge |^Revert "; then
  echo "✓ Merge/Revert commit - skipping validation"
  exit 0
fi

# Conventional Commits pattern:
# <type>[optional scope][optional !]: <description>
#
# Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore
# Breaking changes: include ! before : or have BREAKING CHANGE: in body
PATTERN="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore)(\(.+\))?(!)?: .{1,}"

if ! echo "$COMMIT_MSG" | head -1 | grep -qE "$PATTERN"; then
  echo "❌ Invalid commit message format"
  echo ""
  echo "Commit message must follow Conventional Commits format:"
  echo ""
  echo "  <type>[optional scope][optional !]: <description>"
  echo ""
  echo "Valid types:"
  echo "  feat:     New feature (triggers MINOR version bump)"
  echo "  fix:      Bug fix (triggers PATCH version bump)"
  echo "  docs:     Documentation only changes (PATCH)"
  echo "  style:    Code style changes (formatting, etc.) (PATCH)"
  echo "  refactor: Code refactoring without behavior change (PATCH)"
  echo "  perf:     Performance improvements (PATCH)"
  echo "  test:     Adding or updating tests (PATCH)"
  echo "  build:    Build system or dependency changes (PATCH)"
  echo "  ci:       CI/CD configuration changes (PATCH)"
  echo "  chore:    Other changes that don't modify src/test (PATCH)"
  echo ""
  echo "Breaking changes:"
  echo "  - Add ! before colon: feat!: breaking change"
  echo "  - Or include 'BREAKING CHANGE:' in commit body"
  echo "  (triggers MAJOR version bump)"
  echo ""
  echo "Examples:"
  echo "  feat: add user authentication"
  echo "  fix: resolve database connection timeout"
  echo "  feat(api)!: change response format"
  echo "  docs: update API documentation"
  echo "  chore: update dependencies"
  echo ""
  echo "Your commit message:"
  echo "  $(echo "$COMMIT_MSG" | head -1)"
  echo ""
  exit 1
fi

# Check for BREAKING CHANGE in body
if echo "$COMMIT_MSG" | grep -qE "BREAKING CHANGE:|BREAKING-CHANGE:"; then
  echo "✓ Valid conventional commit (BREAKING CHANGE - MAJOR version bump)"
elif echo "$COMMIT_MSG" | head -1 | grep -q "!:"; then
  echo "✓ Valid conventional commit (BREAKING CHANGE - MAJOR version bump)"
else
  TYPE=$(echo "$COMMIT_MSG" | head -1 | grep -oE "^[a-z]+")
  case "$TYPE" in
    feat)
      echo "✓ Valid conventional commit (feature - MINOR version bump)"
      ;;
    fix)
      echo "✓ Valid conventional commit (bug fix - PATCH version bump)"
      ;;
    *)
      echo "✓ Valid conventional commit ($TYPE - PATCH version bump)"
      ;;
  esac
fi

exit 0
