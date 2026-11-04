---
name: issue
description: Draft or create a GitHub issue for the Infra repository using its infrastructure change or incident template. Use for requests to write, refine, or publish an Infra issue.
---

# Infra issue

Write the issue in Korean. Read the matching file in `.github/ISSUE_TEMPLATE/` and the relevant component README. If a host or service placement changes, check the root `README.md`.

- Choose `feature-issue.md` for planned configuration, service, or operational work; choose `bug-issue.md` for an observed failure or regression.
- Use `[INFRA] feat: ...` or `[INFRA] fix: ...` for the title, adjusting the type when the change is only documentation or maintenance.
- State the affected component and host, observable outcome, actionable tasks, and validation criteria. Distinguish observed facts from suspected causes. Leave unknown details explicit instead of inventing them.
- For a draft, return a title and paste-ready issue body without the template's YAML frontmatter.
- Create or edit a GitHub issue only when the user asks for that action. Check the repository target before posting, use a body file for multiline text, and report the resulting URL. Do not attach secrets, credentials, or raw sensitive logs.
