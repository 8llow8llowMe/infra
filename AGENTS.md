# Repository Guidelines

## Project Structure & Module Organization

This repository manages home server infrastructure. Each top-level directory owns one component: `ollama/`, `jenkins/`, `kafka/`, `vault/`, `nginx/`, `redis/`, and `monitoring/` contain Compose files, installation scripts, configuration, and component documentation. The root `README.md` is the source of truth for host inventory and service placement; update it when a service moves. Keep component-specific instructions in that component's `README.md`. Grafana dashboard JSON and templates live under `monitoring/grafana/`; Nginx site files live under `nginx/conf.d/`.

## Build, Test, and Development Commands

There is no repository-wide build. Validate the component you changed before deploying it:

```bash
bash -n jenkins/install-jenkins.sh
docker compose --env-file ollama/.env -f ollama/docker-compose-ollama.yml config -q
python3 ollama/benchmark-api.py --help
git diff --check
```

`bash -n` checks shell syntax, Compose `config -q` checks configuration with the local environment file, and `git diff --check` catches whitespace errors. Run a component's `install-*.sh` only on its intended host after reviewing its README and environment values; those scripts can change running services.

## Coding Style & Naming Conventions

Follow the style of nearby files: two-space indentation in Compose YAML, four spaces in Python, and `#!/usr/bin/env bash` or the existing shell shebang for scripts. Name Compose files `docker-compose-<component>.yml`, installers `install-<component>.sh`, and nonsecret configuration templates `.env.example`. Keep hostnames, ports, and service names consistent across Compose files, monitoring targets, and documentation.

## Testing Guidelines

There is no central test suite or coverage target. For each change, run syntax or configuration checks for the affected file type, then verify the relevant service on a suitable host. For resource or API changes, compare before and after metrics such as `docker stats`, `ollama ps`, and the Ollama benchmark. Include the exact checks and any unavailable host validation in the pull request.

## Commit & Pull Request Guidelines

Recent commits use `[INFRA] type: description`, with types such as `feat`, `fix`, and `docs`; follow that pattern. Keep commits focused by component or operational change. Pull requests should explain the affected hosts, configuration changes, validation results, deployment and rollback steps, and related issue when applicable. Add screenshots for visible Grafana or web UI changes.

## Security & Configuration

Never commit `.env` files, Vault tokens, agent secrets, or generated data. Use the component's `.env.example` as a template and keep real credentials in the intended secret store. Review `docker compose config` output before sharing it because resolved environment values can contain secrets.
