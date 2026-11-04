---
name: pr
description: Draft or create a GitHub pull request for the Infra repository using its PR template. Use for requests to write, refine, or publish an Infra PR.
---

# Infra pull request

Write the PR in Korean. Read `.github/PULL_REQUEST_TEMPLATE.md`, `AGENTS.md`, and the relevant component README. The repository's base branch is `main`; verify the remote default branch when creating a PR.

- Inspect the intended branch, committed diff, and worktree status. Do not describe unrelated uncommitted changes as part of the PR.
- Title: `[INFRA] type: 요약`, following the change's `feat`, `fix`, `docs`, or `chore` purpose.
- Explain the reason, changed behavior, affected hosts, actual validation, deployment steps, rollback, and linked issue when one exists. Leave unrun checks unchecked and state why they were not run.
- For a draft, return a title and paste-ready body matching the template. Do not invent test results, issue numbers, or screenshots.
- Create a GitHub PR only when requested and the intended branch is ready. Use a body file for multiline text, verify the base and head branches, then report its URL. Do not merge or expose credentials through the PR body or command output.
