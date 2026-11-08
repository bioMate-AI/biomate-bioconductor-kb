# Interactive-tool staging (Jupyter/RStudio on a data-hub dataset) — code map + gap

**Date:** 2026-10-28. Audit (read-only). For when we build the Phase-2 unlock. Parked while
appearance work takes priority.

## TL;DR
The staging endpoint dataset-object.tsx wants is genuinely missing, but **most building blocks
exist**. Critical correction: **run outputs do NOT actually bind to Jupyter today** — the Outputs
"Interactive panel" passes S3 paths as `dataset_ids`, and the server **ignores inputs for
Jupyter/RStudio** (routes.ts:15711 "Jupyter/RStudio ignore inputs"). So staging-as-HDA is needed
for BOTH uploaded project files AND Nextflow run outputs. Only CellxGene actually mounts its input,
and only legacy Galaxy-invocation outputs carry a real `galaxyDatasetId`.

## Proposed endpoint
`POST /api/projects/:id/files/:fileId/stage-interactive` — `authenticateToken` + `_isOwnerOrMember`
(NOT `optionalAuth`). Body `{ tool: 'jupyter'|'rstudio'|'cellxgene' }`. Returns the tool URL.

## Step-by-step (reuse vs build)
| Step | Reuse? | Where |
|---|---|---|
| 1 authZ + fileId→s3_key | **reuse** | project-routes.ts:687-696 (`_isOwnerOrMember`) |
| 2 presign S3 | **reuse** | `s3Service.generatePresignedDownloadUrl(s3_key, ttl)` (s3-client.ts:281) — long TTL |
| 3 ensure history | **reuse** | `userProxy(req).getHistories()/createHistory()` + `req.session.galaxyHistoryId` (routes.ts:10356,15700) |
| 4 URL → HDA | **reuse** | `userProxy(req).uploadFromUrl(presignedUrl, historyId, name)` → HDA id (galaxy-api-proxy.ts:577-603). Skip if source already has `galaxyDatasetId` |
| 5 wait HDA `ok` | **BUILD** (small) | poll `getHistoryContents` (galaxy-api-proxy.ts:872) until state ok — URL-fetch is async |
| 6 launch bound to HDA | **BUILD (the real gap)** | `launchInteractiveTool` exists (:1285) but input mapping doesn't MOUNT data for Jupyter/RStudio. Jupyter needs the `inputs` repeat per `interactivetool_jupyter_notebook_1.0.0.xml:23` (`data_style="staging_path_and_source_path"`); CellxGene `infile:{src:'hda',id}` (done, routes.ts:15718); **RStudio's `<param name="input">` is COMMENTED OUT** (`interactivetool_rstudio.xml:35`) → must un-comment or RStudio can't bind data |
| 7 resolve tool URL | **reuse** | `tokenForJob(job_id)` poll + `rewriteInteractiveToolUrl` (routes.ts:15734-15746) |

## Net new work
(5) HDA-ready poll; (6) correct per-tool input construction so the HDA is actually mounted + un-comment
the RStudio data param in the tool XML. Frontend: wire the commented-out "Open in Jupyter/RStudio"
buttons in `dataset-object.tsx:229-234` to the new endpoint, reusing `InteractiveLauncher`'s session/
readiness polling.

## Primary files
Launchers `interactive-launcher.tsx`, `viewers/interactive-tool-launcher.tsx`; routes `routes.ts:10330,
15691,15776,15793` (+ upload 3560-3649); proxy `galaxy-api-proxy.ts:536,546,554,577,608,1285`; identity
`project-routes.ts:682,1169`, `s3-client.ts:281`; Galaxy `managers/interactivetool.py`,
`webapps/galaxy/api/{tools,history_contents,nextflow_executor}.py`, the two interactive tool XMLs.
