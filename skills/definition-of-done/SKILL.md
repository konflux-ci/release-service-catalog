---
name: definition-of-done
description: Use when preparing a PR for review, checking if a change is complete, or an agent needs to verify its own work before submitting. Use when you need the PR checklist.
---

# Definition of Done

Before submitting a PR, ensure all items are checked:

## Code Quality

- [ ] Code follows existing patterns and conventions in this repository
- [ ] No commented-out code or debug statements left behind
- [ ] Functions and variables have clear, descriptive names

## Testing

- [ ] All existing tests pass
- [ ] New functionality has corresponding test coverage
- [ ] Edge cases and error paths are tested

## CI Checks

- [ ] All CI workflows pass:
  - Check README.md
  - Hot Fix PR
  - Linters
  - PR AI Labeler
  - Assign PR
  - Promote branch
  - Tekton Task Tests
  - Copilot code review

## Documentation

- [ ] Public APIs or user-facing changes are documented
- [ ] README updated if behavior changes
- [ ] Commit messages are clear and follow project conventions

## PR Hygiene

- [ ] PR is focused on a single concern
- [ ] PR description explains WHAT changed and WHY
- [ ] No unrelated changes bundled in
