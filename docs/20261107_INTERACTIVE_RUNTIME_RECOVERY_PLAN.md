# Reviewed dev interactive-runtime recovery plan — 2026-11-07

**Planning only. No runtime/package/socket/container changes have been applied by this task.**

## Verified current state

- Galaxy: `biomate-galaxy-dev`, image `biomate-galaxy-dev:routing-20261105_051617`, original image ID `sha256:ad891c5b78e1f611c64557b56e2604101cb716ee34f428497dbce442ca6d4703`.
- Effective Galaxy user UID/GID 1000, supplemental group 1000. No Docker CLI, no Docker socket mount.
- Host Docker CLI: official installed `docker-ce-cli` package, Docker 28.5.1, `/usr/bin/docker`; SHA256 `2c0c7085014dab521228f90fc5fc714184cbba3ab1dd8d526840dd000ed478b5`.
- Host socket: mode **0660**, root:GID **999**. Preserve those permissions exactly; **no chmod 666**.
- Host CLI requires glibc through 2.34; Galaxy has glibc 2.36. This supports copying the trusted CLI rather than installing a daemon or downloading an unverified binary. Verify actual `ldd`, digest and CLI execution again before acceptance.
- `/tmp/nextflow_runs` is ephemeral: **22 files, 99,930 bytes, UID/GID 1000:1000**, no symlinks at inspection.
- Active Galaxy jobs: none. All 21 Java processes are **Zs zombies**, not active Nextflow heads. Fresh preflight checks remain mandatory immediately before downtime; any non-zombie Nextflow head or active job blocks recovery. Do not kill or cancel it.

## Exact proposed action, subject to parent review

1. **Capture before-state privately.** Save complete `docker inspect` JSON and immutable container/image IDs in a mode-0700 recovery journal; files mode 0600. Save all mount, environment, user/group, restart, networking/aliases/IPAM, ports, resource and security settings. No environment or session tokens printed.
2. **Pin current writable filesystem, not only the old image.** Recent backend syncs used `docker cp`; recreating from the November 5 image would lose them. Retain the original container and produce a private local filesystem snapshot image after the container has stopped. Do not push this image: its container configuration may contain runtime credentials. Record its immutable image ID.
3. **Append-only run-state migration before replacement.** Use a private host directory such as `/opt/biomate/dev-state/nextflow-runs`. Stage a preserved-owner copy of `/tmp/nextflow_runs`, with a manifest of every relative path, file type, SHA256, mode, UID/GID and size. Reject absolute/traversal paths and unsupported links/types. For existing destination paths, accept only identical content/type/owner/mode; differing paths abort rather than overwrite. Copy only missing entries, retain UID/GID, and verify the complete manifest. Never delete source or destination entries. Parent directories stay private; target directory owner/mode must let UID 1000 use the bound directory without making it public.
4. **Quiescence and final copy.** Recheck active jobs and non-zombie Nextflow heads. Stop only after none remain. Recopy/verify any final delta from the stopped original before creating a replacement. A job that appears at the last check aborts this operation; no job is killed. Keep the stopped source container intact.
5. **Prepare replacement using full Engine create payload.** `scripts/interactive_recreate_plan.py` is planning-only and preserves inspect Config/HostConfig rather than reconstructing a lossy `docker run` string. Use the private snapshot image ID. Add only:
   - `/var/run/docker.sock:/var/run/docker.sock:rw`;
   - verified persistent run-state directory → `/tmp/nextflow_runs:rw`;
   - supplemental group **999**, preserving group 1000 and any existing configured groups.
   Preserve all existing bind mounts and HostConfig tmpfs settings, readonly flags, environment (including PATH), command/entrypoint/workdir/user, ports, restart policy, resources/security settings and all networks. Non-bind Mounts (including named or anonymous volumes) are refused for explicit preservation review before any approval SHA is issued. Do not change privileged/capability/security options. The planner refuses conflicting pre-existing mount destinations.
6. **Install only the trusted CLI in the replacement.** Copy verified host `/usr/bin/docker` into `/usr/bin/docker` of the stopped replacement as root. Do not overwrite another existing binary unexpectedly. Recheck its digest; after startup check `ldd`, `docker --version` and `docker info` as the normal Galaxy user. Preserve socket 0660; no host/group/user permission edits beyond the reviewed supplemental group in the replacement configuration.
7. **Health and feature gates.** Verify backend JSON health, assistant generation, preserved backend source hashes and run-state manifest. Verify socket mount, unchanged socket mode/GID, CLI digest/identity and normal-user daemon access. Only after these pass, launch one owned synthetic notebook, wait for real running job and HTTP readiness, then inspect in the browser. A token row or HTTP 200 launch response alone is not success.
8. **Rollback if any gate fails.** Stop and remove only the newly created replacement, restore the retained original container's name and original network state, and start it with its original inspect configuration. Preserve both private snapshot image and copied run-state directory for investigation. Do not prune images, volumes, run files or existing containers. Old container filesystem retains the original ephemeral run data. If replacement did not yet start, simply restore/start the original. Report the failed gate; do not claim interactive readiness.

## Durable sync changes required before execution

The existing `enable_interactive_tools` function must stop reconstructing containers from a subset of inspect fields, stop swallowing CLI failures as warnings, and remove its world-writable-socket chmod. Its recreation branch should call a reviewed opt-in recovery path with before-state journal, migration manifest and rollback. Ordinary sync must not silently report the interactive capability healthy when Docker CLI/socket access is absent. Do not run the current `--it-only` implementation unchanged.

The combined suite has 15 passing tests for configuration preservation, conflicting/non-bind mount refusal, actual port preservation, append-only migration, source and quiescence guards, approval fingerprints and actual apply success/failure rollback paths. Independent source review remains required before use.

## Material risks and predicted outcome

The new socket access grants Galaxy intended dev-only control of the host Docker daemon (host-equivalent authority); this is an explicit capability addition, not a cosmetic package fix. Adding GID 999 limits socket access to the intended container user; it does not remove that underlying Docker authority. There is a short Galaxy service interruption. A local snapshot contains potentially sensitive runtime environment metadata and must remain private. Docker-created dynamic network addresses may change; preserve declared static IPAM and aliases and verify clients resolve the service by name.

With the reviewed CLI, socket bind and supplemental group present, the previous exit-127 `docker: command not found` should disappear. This does **not** yet prove notebook image availability, startup, dependency resolution, kernel access or file binding; those require the post-recovery owned synthetic notebook check. If any later step fails, retain and diagnose that actual error.

## Local recovery implementation — awaiting approval, not executed

The guarded implementation is `scripts/interactive_runtime_recovery.py`, called through `BIOMATE_ENABLE_IT=1 bash scripts/sync_to_dev.sh`. Default mode writes a private plan and prints its SHA; it does not stop/recreate containers. Apply additionally requires `BIOMATE_IT_APPLY=1`, `BIOMATE_IT_SOCKET_APPROVED=1`, and `BIOMATE_IT_APPROVED_PLAN_SHA=<exact reviewed SHA>`. Normal sync and this path share an atomic remote deployment lease; stale leases require human investigation rather than automatic deletion.

The replacement preserves Config/HostConfig and declared network endpoints through Docker Engine create inputs. It stops only after two quiescence checks, snapshots the stopped filesystem, copies run state append-only, releases original network endpoints to avoid static-IP/alias collisions, and retains the original container and snapshot. Any subsequent failure removes only the exact replacement ID, reconnects original endpoints and starts/verifies the original. CLI bytes must match the reviewed official host package SHA, root ownership and mode0755 at `/usr/bin/docker`; libraries and normal-user daemon access are checked. Socket remains root:999 mode0660. No runtime action has been executed.

Local validation: 15 focused planner/migration/quiescence/rollback/digest tests pass; Python compilation and shell syntax pass. These tests do not establish that a newly created notebook container is usable. Before apply approval, independently review Docker host `/app` bind-path availability for child-container mounts and proxy/network compatibility; current recovery deliberately does not rewrite the proxy or existing application mounts. A real synthetic notebook launch and browser page load are still required after a successful approved recovery.

## Read-only host prerequisite follow-up

Existing dev inspection (no uploads or runtime changes) confirms Galaxy has only the existing writable `/app/database` bind and belongs to `biomate-dev-net`; there are no named/anonymous mounts to trigger the refusal. Host `/app/database` resolves to the same persisted `/opt/biomate/galaxy_db`; host `/app/tools/interactive` exists. `gx-it-proxy` is running on the host network. Among36 host interactive `.py`/`.xml`/`.sh` files compared with Galaxy, one differs: `interactivetool_rstudio_bioc_3.20.xml`. The Jupyter files in that comparison agree. Job133's generated job directory/script has since been cleaned, so its exact original child mount list could not be rechecked. This supports the expected shared database path behavior; it does not prove successful child launch or browser proxy readiness. The stale RStudio mirror remains a separate follow-up before claiming all interactive tools ready.
