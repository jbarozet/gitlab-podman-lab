# Repository Guidelines

## Project Structure & Module Organization

`docker-compose.yml` defines the GitLab server, runner, network, ports, and persistent state. `register_runner.sh` registers the runner. `custom-image/` is a self-contained side project that builds the arm64 Linux image used for GitLab CI jobs; its `Containerfile`, `build.sh`, and `README.md` define that workflow. `smoke-test/` is the end-to-end validation project, and setup references are in `docs/`. Runtime state below `data/` is not source code.

## Build, Test, and Development Commands

- `podman compose config` validates and renders the Compose configuration.
- `podman compose up --detach` creates and starts GitLab and its runner.
- `podman compose ps` checks service health; `podman logs --follow gitlab` follows startup.
- `bash register_runner.sh` securely prompts for a runner token and registers the runner.
- `cd custom-image && ./build.sh` builds the runner's `nac-demo` Linux image locally.
- `podman compose stop` preserves containers and data; `podman compose down` removes containers and the Compose network.

## Coding Style & Naming Conventions

Use two-space indentation in YAML and Containerfile continuation blocks. Shell scripts should use an accurate shebang, quote variable expansions (for example, `"$REG_TOKEN"`), and use uppercase names for configuration. Name operational scripts with lowercase, action-oriented names, following `register_runner.sh` and `custom-image/build.sh`. Keep Markdown brief and update documentation when commands, ports, images, or paths change. No repository-wide formatter is configured.

## Testing Guidelines

There is no automated test framework or coverage target. Run `podman compose config` and syntax-check modified scripts with `bash -n path/to/script.sh` (or the declared shell). For runtime changes, verify `podman compose ps` and the runner socket with `podman exec gitlab-runner test -S /var/run/docker.sock`. Build image changes and check the installed tool versions.

## Commit & Pull Request Guidelines

Recent history uses short, imperative, lowercase subjects such as `update runner container build`. Follow that pattern and keep commits focused. Pull requests should explain the motivation, list validation, identify macOS/Podman assumptions, and link related issues. Include screenshots only for UI changes. Call out changes affecting `data/`, ports, image tags, or runner registration.

## Security & Configuration Tips

This lab is demonstration-only and optimized for Apple Silicon. Never commit runner tokens, passwords, generated GitLab configuration, or files below `data/`. Let `register_runner.sh` prompt for the token, or inject `REG_TOKEN` only through the local environment for unattended use. Treat the mounted Podman socket as privileged access: run only trusted CI jobs and runner images. Avoid `podman compose down --volumes` unless data deletion is intentional.
