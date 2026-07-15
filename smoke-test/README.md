# GitLab Smoke Test

This project verifies the complete local CI path:

1. GitLab accepts a repository push.
2. GitLab creates a pipeline.
3. The registered runner receives the job.
4. Podman starts a job container.
5. The custom job image provides Git, Python, and Terraform.

## Create the GitLab project

Open the configured GitLab URL (`GITLAB_EXTERNAL_URL` in `.env`, or <http://localhost:8088> by default), sign in, and select **New project > Create blank project**.

- **Project name:** `smoke-test`
- **Project URL:** `http://gitlab.example.test:8088/root/smoke-test` (replace the host with the configured server)
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
git remote add origin http://gitlab.example.test:8088/root/smoke-test.git
git push --set-upstream origin main
```

Replace `gitlab.example.test` with the host configured in `.env`. On macOS, use `localhost`.

The copy includes `.gitlab-ci.yml`, which is hidden by default in directory listings.

## Verify the pipeline

Open **Build > Pipelines** in the new project. The `smoke-test` job should succeed and print:

- A runner confirmation message
- Linux kernel and container hostname information
- Git, Python, and Terraform versions

The pipeline does not declare an `image`, so it intentionally uses the default image configured by `register_runner.sh`.

## Troubleshooting

If the job remains pending, confirm that the runner is online and **Run untagged jobs** is enabled. Then inspect:

```console
podman logs gitlab-runner
podman exec gitlab-runner test -S /var/run/docker.sock
```

If `python` or `terraform` is missing, build the [custom image](../custom-image/README.md) on the GitLab host and register the runner again with `CUSTOM_IMAGE=nac-demo:latest bash register_runner.sh`. A registry-hosted image is preferable if the runner is not restricted to this trusted lab.
