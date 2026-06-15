# RStudio output analysis — Interactive Tools never enabled on dev

**Status:** Discovered 2026-06-15. Production-impact: "Analyze in RStudio" button on any output preview returns HTTP 500.

## TL;DR

The end-to-end flow Bioconductor workflow → "Analyze in RStudio" → live R session has **never** worked on dev. Galaxy's Interactive Tools (IT) infrastructure is on disk but not configured. The launch endpoint, the InteractiveLauncher React dialog, the two RStudio tool XMLs, the UI buttons — all present. But Galaxy treats `interactive_tool_rstudio` as an unknown tool ID, so every launch attempt 400s.

## Evidence

### 1. Launch returns 500 (Galaxy upstream returns 400)

```
$ curl -X POST https://dev-public.biomate.ai/api/interactive/launch \
    -H "Authorization: Bearer $JWT" \
    -d '{"tool_id":"interactive_tool_rstudio","inputs":{}}'
{"error":"InteractiveLaunchError","message":"Request failed with status code 400"}
HTTP 500
```

### 2. Galaxy logs reveal "tool not found"

```
galaxy.webapps.galaxy.services.tools DEBUG ...
  Not found tool with kwds [{'tool_id': 'interactive_tool_rstudio',
                             'tool_uuid': None, 'tool_version': None}]
uvicorn.access INFO ... "POST /api/tools HTTP/1.1" 400
```

### 3. Config layer is empty

```
$ docker exec biomate-galaxy-dev grep -E 'interactivetool|gx_it_proxy' /app/config/galaxy.yml
(no matches)
```

No `interactivetools_enable`, no `interactivetools_proxy_host`, no
`gx_it_proxy`, no `interactivetools_map`. Galaxy needs all of these to
turn an IT tool ID into a running container.

### 4. Toolbox config registers only the v0.3 generic, not Bioc 3.20

```xml
<!-- /app/config/interactivetool_conf.xml -->
<toolbox>
  <tool file="interactive/interactivetool_rstudio.xml" />
</toolbox>
```

Both `interactivetool_rstudio.xml` (v0.3) and
`interactivetool_rstudio_bioc_3.20.xml` (24.2+bioc) are on disk under
`/app/tools/interactive/`. Both declare the same tool ID
`interactive_tool_rstudio`. The conf file references only the
generic one. Even if loaded, the duplicate ID would cause a registry
collision.

### 5. Startup log shows no IT scan

```
$ docker logs biomate-galaxy-dev | grep -iE 'interactivetool|gx_it'
(no matches — Galaxy never even attempts to load IT tools)
```

## What the user sees today

1. Workflow runs (Bioc DESeq2, for example), produces a CSV output.
2. In `step-output-preview.tsx:562`, the "Analyze in RStudio" button
   appears next to tabular outputs.
3. User clicks it → `InteractiveLauncher` dialog opens with RStudio
   pre-selected.
4. User clicks "Launch RStudio" → `POST /api/interactive/launch` →
   error toast.

No screenshot — the failure is silent in our test suite because there
is no e2e that exercises this path (the interactive-launcher
component-level test mocks the API).

## Why this wasn't caught

- `interactive-launcher.test.tsx` is a React Testing Library test that
  mocks the launch API and only verifies the dialog UI. The backend is
  never touched.
- No e2e test exists for the post-workflow → "Open in RStudio" flow.
- Users likely tried it, saw an error, gave up, and assumed it was
  per-account quota or "feature in development."

## Fix sketch (NOT applied — bigger scope than a single session)

This is genuine infrastructure enablement work. Stages:

### Stage A — Galaxy IT config

Add to `backend/config/galaxy.yml`:
```yaml
interactivetools_enable: true
interactivetools_map: database/interactivetools_map.sqlite
interactivetools_proxy_host: dev-public.biomate.ai
interactivetools_base_path: /interactive/
interactivetools_shorten_url: true
outputs_to_working_directory: true
gx_it_proxy:
  enable: true
  port: 4002
  sessions: database/gx_it_proxy.sqlite
```

### Stage B — Resolve duplicate tool IDs

Either:
- Remove `interactivetool_rstudio.xml` (the v0.3 generic), OR
- Give the Bioc one a distinct ID (`interactive_tool_rstudio_bioc`) and
  list both in `interactivetool_conf.xml`.

Recommend the second — keeps the generic RStudio for non-Bioc workflows.

### Stage C — gx-it-proxy sidecar

The proxy that bridges `https://dev-public.biomate.ai/interactive/<token>/`
→ `localhost:<port>` on the container. Galaxy bundles `gx-it-proxy`
(node.js). Needs to run as a sidecar on the EC2 host.

```
docker run -d --name gx-it-proxy --network host \
  ghcr.io/galaxyproject/gx-it-proxy:latest \
  --port 4002 \
  --sessions /app/database/gx_it_proxy.sqlite
```

### Stage D — Job destination

`job_conf.xml` needs a docker destination that allows containers with
exposed ports (Galaxy's `<container type="docker">` with
`<param id="docker_default_container_id">`). Confirm dev's job_conf
has an `<destination id="interactive">` block.

### Stage E — E2E test

After Stage A–D, add `frontend/e2e/rstudio-launch.e2e.ts` that:
1. Runs a Bioc DESeq2 workflow with the fixture user.
2. Polls for completion (will need #56 Stage 3 first for reliable
   completion).
3. Clicks "Analyze in RStudio" on the volcano-plot CSV output.
4. Asserts `/api/interactive/launch` returns `entry_point_url` not
   `error`.
5. Optionally: opens the URL and asserts the rstudio login page renders.

## Open questions

1. **Should this run on AWS Batch or a Galaxy-managed EC2 instance?**
   Interactive Tools traditionally run on the Galaxy job runner's host.
   On AWS Batch the entry_point_url routing gets harder. Dev probably
   needs a Galaxy-host docker destination for IT specifically, even if
   batch workflows go to Batch.

2. **Single shared RStudio per user, or per-output?** Current
   InteractiveLauncher offers per-output. That implies N concurrent
   RStudio containers per user. Resource budget?

3. **How do outputs land in RStudio's filesystem?** The Bioc XML does
   `mkdir -p /import && ln -s /import /home/rstudio/galaxy_imports` —
   Galaxy's GalaxyConnector is supposed to populate /import. Need to
   verify this works against S3-resident workflow outputs.

## Recommendation

Treat this as a follow-on after #56 (run-state persistence) lands.
Reasons:

- IT launch fires AFTER workflow completion; without #56 Stage 3, the
  trigger event for "workflow done → outputs available" is unreliable.
- The IT proxy + galaxy.yml config changes need testing on a fresh
  Galaxy boot, which requires a sync_to_dev that's already busy with
  the persistence refactor.
- Customer-facing impact: "Open in RStudio" was never advertised as a
  Bioc-domain headline feature; it's a power-user shortcut. We can ship
  the persistence fix first, then enable IT in a separate focused PR.

This doc is the reference for whoever picks up Stage A–E.
