# GitLab Smoke Test

This project verifies the complete local CI path:

1. GitLab accepts a repository push.
2. GitLab creates a pipeline.
3. The registered runner receives the job.
4. Podman starts a job container.
5. The custom job image provides Git, Python, and Terraform.

## Create the GitLab project

Open <http://localhost:8088>, sign in, and select **New project > Create blank project**.

- **Project name:** `smoke-test`
- **Project URL:** `http://localhost:8088/root/smoke-test`
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
git remote add origin http://localhost:8088/root/smoke-test.git
git push --set-upstream origin main
```

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

If `python` or `terraform` is missing, publish the image built in [custom-image](../custom-image/README.md) and register the runner with `CUSTOM_IMAGE="<published-image>" bash register_runner.sh`.
