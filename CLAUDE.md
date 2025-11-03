- run the relevant unit tests and ensure they pass, add any new required test and fix any broken
- after every feature commit and push the changes to a branch on each submodule and ask me if I want to merge, then ensure the main branch is commited and pushed create a PR and send me the link

## Commit Message Format

**IMPORTANT**: All commits MUST follow [Conventional Commits](https://www.conventionalcommits.org/) format for semantic versioning.

### Format

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

### Types (determines version bump)

- `feat:` - New feature (MINOR version bump: 1.0.0 → 1.1.0)
- `fix:` - Bug fix (PATCH version bump: 1.0.0 → 1.0.1)
- `docs:` - Documentation only (PATCH)
- `style:` - Code style/formatting (PATCH)
- `refactor:` - Code refactoring (PATCH)
- `perf:` - Performance improvements (PATCH)
- `test:` - Test changes (PATCH)
- `build:` - Build system changes (PATCH)
- `ci:` - CI/CD configuration (PATCH)
- `chore:` - Other changes (PATCH)

### Breaking Changes (MAJOR version bump: 1.0.0 → 2.0.0)

For breaking changes, use one of:
- Add `!` before colon: `feat!: breaking change`
- Include `BREAKING CHANGE:` in commit body

### Examples

```
feat: add user authentication
fix: resolve database connection timeout
feat(api)!: change response format to JSON:API spec
docs: update API documentation
chore: update dependencies
perf(scraper): optimize HTML parsing
ci: add commit message validation
```

### Validation

Commits are validated:
1. **Locally** via Git hook (install with `./scripts/setup-git-hooks.sh`)
2. **In CI** via GitHub Actions (blocks PRs with invalid commits)

To bypass local hook (not recommended):
```bash
git commit --no-verify
```