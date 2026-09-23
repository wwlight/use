---
description: Commit current changes with the git-workspace conventions
agent: build
---

Load the `git-workspace` skill and follow it. The user invoked this command, so creating the commit is requested.

- Subject only, one line, no body.
- Format: `type(scope): summary` — state why in the subject. Match recent `git log` for type and scope.
- Do not push, amend, or use `--no-verify`.
- If a pre-commit hook modifies files, create a new commit instead of amending.

Inspect `git status` and `git diff`, then commit.
