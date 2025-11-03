#!/bin/bash
set -e

# Setup script to enable custom Git hooks
# This configures Git to use hooks from .githooks/ directory

echo "Setting up Git hooks..."

# Configure Git to use .githooks directory
git config core.hooksPath .githooks

echo "✓ Git hooks configured successfully"
echo ""
echo "Enabled hooks:"
echo "  - commit-msg: Validates Conventional Commits format"
echo ""
echo "To disable hooks for a single commit:"
echo "  git commit --no-verify"
echo ""
echo "To disable hooks permanently:"
echo "  git config --unset core.hooksPath"
