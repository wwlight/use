---
name: git-workspace
description: Git commit safety conventions — commit only when asked, one-line subject format, no push/amend/force-push without explicit request.
---

# Git commit conventions

- **Commit only when the user explicitly asks** (e.g. "commit", "create a commit").
- **Subject only** — one line, no body, no blank-line continuation.
- **Format:** `type(scope): summary` — state why in the subject. If unsure of `type` or `scope`, read recent `git log` in the repo and match it.
- **Do not** push, amend, or force-push unless the user explicitly requests it.
- **Do not** use `--no-verify` unless the user explicitly requests it.
- If a pre-commit hook modifies files, **create a new commit**; do not amend unless all amend conditions are met and the user asked for amend.
