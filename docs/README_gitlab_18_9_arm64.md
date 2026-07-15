# Maintaining a GitLab 18.9.x arm64 Instance

This runbook applies to an existing Podman lab running GitLab CE 18.9.x on an
arm64 host, including Apple Silicon macOS and arm64 Ubuntu Server. It documents
the safe path for inspecting, pinning, backing up, and eventually migrating the
instance to an amd64 Ubuntu Server. It does not apply to a fresh deployment.

The examples use the repository default, GitLab CE and Runner 18.9.0. If an
instance reports another 18.9 patch release, use its exact version everywhere a
backup is restored and confirm that the required source and target image tags
exist before making changes.

> [!WARNING]
> Do not upgrade an instance directly from GitLab 18.9 to GitLab 19.x. GitLab
> 18.11 is a required upgrade stop, but the community arm64 server image does
> not provide that release.

## Identify the current state

Inspect the running instance before making changes:

```console
podman compose ps
podman exec gitlab gitlab-rake gitlab:env:info
podman exec gitlab-runner gitlab-runner --version
podman inspect --format '{{.Name}} {{.ImageName}} {{.State.Status}}' \
  gitlab gitlab-runner
du -sh data/gitlab/config data/gitlab/data data/gitlab/logs
find data/gitlab/data/backups -maxdepth 1 -type f -print
```

An instance covered by this runbook should have:

| Component | Expected value |
| --- | --- |
| GitLab CE | `18.9.x`, `linux/arm64` |
| GitLab Runner | Preferably the same `18.9.x` release line |
| GitLab server image | `docker.io/yrzr/gitlab-ce-arm64v8` community image |
| Persistent state | Bind-mounted below `data/` |

An older deployment might show floating `latest` image names even though the
running binaries report 18.9.x. Recreating those containers could select
different content, so identify the binary versions rather than trusting the
image-name string.

Run the pre-change health checks:

```console
podman exec gitlab gitlab-rake gitlab:check SANITIZE=true
podman exec gitlab gitlab-rake gitlab:background_migrations:list
podman exec gitlab gitlab-rake gitlab:doctor:secrets
```

Do not continue unless:

- The GitLab health check succeeds.
- No batched background migration is active, paused, or failed.
- The secrets check reports zero affected rows.
- GitLab Server and Runner major and minor versions match.

The **Update ASAP** badge in the GitLab UI only reports that a newer GitLab
release exists. It does not validate required upgrade stops, arm64 image
availability, database migration state, or the deployment's restore plan.

## Immediate action

The safe immediate action is to:

1. Pause the Runner so no CI jobs start during backup.
2. Create both a GitLab application backup and a cold copy of `data/`.
3. Recreate the containers with explicit version tags.
4. Validate the pinned installation before removing any old images.

Do not run an uncontrolled `podman compose pull` while the old Compose file
still refers to `latest`.

## Backup procedure

### 1. Stop the Runner

```console
podman compose stop gitlab-runner
```

### 2. Create the GitLab application backup

Keep the GitLab container running for this step:

```console
podman exec -t gitlab gitlab-backup create
ls -lh data/gitlab/data/backups/
```

The archive is written below `data/gitlab/data/backups/`. A GitLab backup does
not contain every configuration file or secret required for a complete restore.

### 3. Copy configuration and secrets

Set `GITLAB_BACKUP_VERSION` to the exact version reported by
`gitlab:env:info`. Store backups outside the Git repository:

```console
export GITLAB_BACKUP_VERSION=18.9.0
export GITLAB_BACKUP_DIR="../gitlab-backups/${GITLAB_BACKUP_VERSION}"
mkdir -p "${GITLAB_BACKUP_DIR}"
cp -R data/gitlab/config "${GITLAB_BACKUP_DIR}/"
cp -R data/gitlab/data/backups "${GITLAB_BACKUP_DIR}/"
cp -R data/gitlab-runner/config \
  "${GITLAB_BACKUP_DIR}/runner-config"
```

The copy of `data/gitlab/config` must include `gitlab-secrets.json`. Without
that file, encrypted CI variables, tokens, and other protected values might not
be recoverable.

### 4. Create a cold copy

Stop both containers before copying all persistent state:

```console
podman compose stop
tar -czf "${GITLAB_BACKUP_DIR}/gitlab-lab-data.tar.gz" data
tar -tzf "${GITLAB_BACKUP_DIR}/gitlab-lab-data.tar.gz" >/dev/null
```

Copy the resulting archive to another disk if the lab data matters. A backup on
the source host does not protect against disk or Podman Machine loss.

## Pin the current versions

The current repository defaults pin the supported community arm64 pair to:

```text
docker.io/yrzr/gitlab-ce-arm64v8:18.9.0-ce.0
docker.io/gitlab/gitlab-runner:v18.9.0
```

Confirm the rendered configuration before recreating anything:

```console
podman compose config --images
```

The output must contain exactly the two images above. Then pull and recreate the
containers while preserving the bind-mounted `data/` directories:

```console
podman compose pull
podman compose up --detach --force-recreate
```

This changes the container image references from floating tags to explicit
tags. It does not change the GitLab application version or intentionally modify
the persistent data format when the existing instance is also 18.9.0. If the
running instance reports another patch version, do not recreate it with 18.9.0
until the version-specific backup and restore implications have been reviewed.

## Validation

Wait for GitLab to finish starting:

```console
podman compose ps
podman logs --follow gitlab
```

When GitLab is ready, run:

```console
podman exec gitlab gitlab-rake gitlab:env:info
podman exec gitlab gitlab-rake gitlab:check SANITIZE=true
podman exec gitlab gitlab-rake gitlab:background_migrations:list
podman exec gitlab gitlab-rake gitlab:doctor:secrets
podman exec gitlab-runner gitlab-runner --version
podman exec gitlab-runner test -S /var/run/docker.sock
```

Also confirm in the UI that users can sign in, projects are visible, repositories
can be cloned and pushed, the Runner is online, and a smoke-test pipeline passes.
Do not delete the backup or old images until these checks succeed.

## Upgrade limitation on arm64

GitLab requires the latest patch release in the 18.11 minor series as the next
stop when moving from 18.9 toward GitLab 19. Background migrations must finish
at every stop before the next upgrade begins.

The community `docker.io/yrzr/gitlab-ce-arm64v8` server image currently stops
in the 18.9 release line. It cannot provide the required 18.11 stop. Keep the
arm64 lab on its matched, pinned 18.9.x Server and Runner pair. Do not upgrade
only the Runner to 19.x.

Because this release no longer receives current GitLab fixes, keep the lab off
untrusted networks and do not expose it directly to the Internet.

## Migration and upgrade path

Use a real amd64 Ubuntu Server as the route to current official GitLab images:

```text
arm64 community GitLab CE 18.9.x
                  ↓ backup and restore
Ubuntu amd64 official GitLab CE at the same exact 18.9.x patch
                  ↓ validate and upgrade
Ubuntu amd64 official GitLab CE 18.11.7
                  ↓ finish all background migrations
Ubuntu amd64 official GitLab CE 19.1.2
```

### 1. Restore onto the same version

The initial Ubuntu target must use the same edition and exact patch version as
the backup. For the repository default, use:

```dotenv
GITLAB_IMAGE=docker.io/gitlab/gitlab-ce:18.9.0-ce.0
GITLAB_RUNNER_IMAGE=docker.io/gitlab/gitlab-runner:v18.9.0
```

If the source runs a different 18.9 patch, replace both tags with that exact
version. Transfer the GitLab backup and `gitlab-secrets.json` securely. Restore
into a fresh official amd64 GitLab CE installation at the matching version,
then repeat every validation check above. Re-register the Runner if necessary.

### 2. Upgrade one stop at a time

After the restored 18.9.x instance passes validation:

1. Back up the Ubuntu instance.
2. Change the GitLab and Runner image pair to the documented 18.11 versions.
3. Pull and recreate the containers.
4. Allow the PostgreSQL upgrade and GitLab migrations to finish without interruption.
5. Run all health, secrets, migration, UI, repository, registry, and CI checks.
6. Create another backup.
7. Change to the documented 19.1 image pair and repeat the process.

Never move to the next stop while any background migration is active, paused,
or failed. Review the GitLab upgrade notes again immediately before performing
the migration because available patch releases and known issues can change.

## Rollback guidance

Do not attempt to roll back by pointing upgraded data at an older image. GitLab
database changes are not generally reversible that way.

If pinning the arm64 containers fails before any version change, stop the stack,
restore the cold `data/` archive, and recreate containers at the exact original
18.9.x version. If a later GitLab upgrade fails, restore its pre-upgrade backup
into a clean GitLab installation running the exact same GitLab version and
edition that created the backup.

Avoid `podman compose down --volumes`; the lab uses bind mounts, but destructive
volume commands are inappropriate during backup, migration, or recovery.

## References

- [Plan a GitLab upgrade path](https://docs.gitlab.com/update/upgrade_paths/)
- [Plan and validate an upgrade](https://docs.gitlab.com/update/plan_your_upgrade/)
- [Upgrade a Docker-based instance](https://docs.gitlab.com/update/docker/)
- [Back up GitLab in a container](https://docs.gitlab.com/install/docker/backup/)
- [Restore GitLab](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/)
- [Check background migrations](https://docs.gitlab.com/update/background_migrations/)
- [GitLab 18 upgrade notes](https://docs.gitlab.com/update/versions/gitlab_18_changes/)
