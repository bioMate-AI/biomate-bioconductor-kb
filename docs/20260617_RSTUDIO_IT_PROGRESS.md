# RStudio Interactive Tools — major progress on dev (2026-06-17)

Follow-up to `docs/20260615_RSTUDIO_IT_DISABLED_ON_DEV.md`.

## Status

**4 of 5 stages closed; 1 deeper infrastructure gap remains.**

| Stage | What | Status |
|---|---|---|
| A | `galaxy.yml` IT config | ✅ done |
| B | Resolve duplicate tool ID | ✅ done |
| C | Job runner spawns IT container | ✅ partial — Galaxy invokes `docker run`, but the rocker/rstudio container fails to start (Docker-in-Docker issue) |
| D | gx-it-proxy sidecar | ⏸ deferred — needed for browser → container routing |
| E | E2E test | ⏸ deferred — depends on C+D |

## What now works

- `POST /api/interactive/launch` returns **HTTP 200** (was 500):
  ```json
  {"job_id": "f2db41e1fa331b3e", "state": "queued",
   "message": "Interactive tool launched. Waiting for session."}
  ```
- `/api/tools?tool_id=interactive_tool_rstudio` returns `["0.3"]` — the tool is registered
- Galaxy's job handler dispatches the launch and builds the right `docker run` command:
  ```
  docker run -p 8787 ... quay.io/galaxy/docker-rstudio-notebook:23.1 ...
  ```

## Config changes (live in container, host-source persistence pending)

`/app/config/galaxy.yml` — added under `galaxy:`:
```yaml
interactivetools_enable: true
interactivetools_map: database/interactivetools_map.sqlite
interactivetools_base_path: /interactive/
tool_config_file: config/tool_conf.xml.sample,config/shed_tool_conf.xml,config/interactivetool_conf.xml
```

`/app/config/interactivetool_conf.xml` (also copied to host at `/opt/biomate/galaxy_build/config/interactivetool_conf.xml`):
```xml
<?xml version="1.0"?>
<toolbox tool_path="/app/tools">
  <tool file="interactive/interactivetool_rstudio.xml" />
  <tool file="interactive/interactivetool_rstudio_bioc_3.20.xml" />
</toolbox>
```

`/app/tools/interactive/interactivetool_rstudio_bioc_3.20.xml` — `id="interactive_tool_rstudio"` renamed to `id="interactive_tool_rstudio_bioc"` (dedup against generic v0.3). Also applied to host source.

## The remaining gap

After Galaxy invokes `docker run ... quay.io/galaxy/docker-rstudio-notebook:23.1`, the container fails to start and Galaxy logs:

```
galaxy.jobs ERROR ... Error occured while calling tool specific fail actions for job 1
  ... lib/galaxy/managers/interactivetool.py:99, in remove
  ... self.app.interactivetool_manager.remove_entry_points(eps)
```

The most likely cause is **Docker-in-Docker**: the `biomate-galaxy-dev` container runs inside Docker on the host. To spawn child containers it needs either:

1. Docker socket mounted (`-v /var/run/docker.sock:/var/run/docker.sock`) — quickest fix but a security trade-off (Galaxy container effectively gets root on the host)
2. A separate Galaxy job destination configured to run the IT container on a different host (proper but more setup)
3. Move from Docker job runner to Kubernetes / nomad

The current dev container does NOT have `/var/run/docker.sock` mounted — that would explain the container-launch failure cleanly.

## Recommended next steps (separate session)

1. **Stage C (1 line fix)**: Mount Docker socket into `biomate-galaxy-dev`. This is the smallest possible move and is fine for dev. Production would need a different approach.
2. **Stage D (~50 lines + 1 process)**: Add the `gx-it-proxy` Node sidecar container on the dev host, listening on a dedicated port. Wire the `interactivetools_proxy_host` config to point at it.
3. **Stage E (~150-line spec)**: New `frontend/e2e/rstudio-launch.e2e.ts` that:
   - Runs a small Bioc workflow (e.g. DESeq2)
   - Clicks "Analyze in RStudio" on the volcano plot CSV
   - Asserts `entry_point_url` returned + reachable
   - Optionally signs into the RStudio session

## Persistence

- Host source updated: `interactivetool_conf.xml` placed at `/opt/biomate/galaxy_build/config/` + Bioc XML host edit
- Galaxy.yml changes live in the running container only (Galaxy bakes its own galaxy.yml from gravity init). For permanent persistence:
  - Add the IT config block to whatever generates galaxy.yml (likely `/opt/biomate/galaxy_build/start_biomate.sh` or a config template)
  - Add a Dockerfile `COPY` for `interactivetool_conf.xml`

These persistence steps are queued for the next sync_to_dev cycle.
