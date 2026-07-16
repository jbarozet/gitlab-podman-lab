# GitLab Smoke Test

This project verifies the complete local CI path:

1. GitLab accepts a repository push.
2. GitLab creates a pipeline.
3. The registered runner receives the job.
4. Podman starts a job container.
5. The custom job image provides Git, Python, and Terraform.

## Create the GitLab project

Open the configured GitLab URL, sign in, and select
**New project > Create blank project**. On macOS this is
`GITLAB_EXTERNAL_URL` from `.env`, or <http://localhost:8088> by default. On
Ubuntu it is the native server URL selected during installation.

- **Project name:** `smoke-test`
- **Project URL:** `http://gitlab.example.test/root/smoke-test` on Ubuntu, or `http://localhost:8088/root/smoke-test` on macOS
- **Visibility:** Public, for this isolated lab only
- **Initialize repository with a README:** Disabled

## Copy and push the test

Copy this directory outside the current repository so it can become an independent Git repository. From the repository root, run:

```console
cp -R smoke-test ../gitlab-smoke-test
cd ../gitlab-smoke-test
git init
git branch -M main
git add .
git commit -m "Add GitLab smoke test"
git remote add origin http://gitlab.example.test/root/smoke-test.git
git push --set-upstream origin main
```

Replace `gitlab.example.test` with the Ubuntu server address. On macOS, use
`localhost:8088`.

The copy includes `.gitlab-ci.yml`, which is hidden by default in directory listings.

## Verify the pipeline

Open **Build > Pipelines** in the new project. The `smoke-test` job should succeed and print:

- A runner confirmation message
- Linux kernel and container hostname information
- Git, Python, and Terraform versions

The pipeline does not declare an `image`, so it intentionally uses the default
image configured by the platform registration script.

## Troubleshooting

If the job remains pending, confirm that the runner is online and
**Run untagged jobs** is enabled.

On macOS, inspect:

```console
podman logs gitlab-runner
podman exec gitlab-runner test -S /var/run/docker.sock
```

On native Ubuntu, inspect:

```console
sudo systemctl status gitlab-runner
sudo gitlab-runner verify
sudo grep -nE '^[[:space:]]*(host|volumes)[[:space:]]*=' \
  /etc/gitlab-runner/config.toml
```

The Ubuntu Runner host must point to its rootless Podman socket and its job
volumes must be exactly `["/cache"]` for this lab.

If `python` or `terraform` is missing, follow the
[custom-image guide](../custom-image/README.md) and register the runner again
with `CUSTOM_IMAGE` set to the required tag. A registry-hosted image is
preferable for Ubuntu and for any runner not restricted to this trusted lab.
