# 2026-11-14 ~09:00 — Next after committee audit

Worktree tip base: `8c946897dd` · branch `sync/pr398-onto-dev`

## Priority pick (this batch)

| Rank | Open item | Why next | Action |
|------|-----------|----------|--------|
| **1** | **REINVENT4 HONEST_FAIL** (`CLI/package not found`) | Confirmed on Batch image `reinvent4-nf:x86`, exit 3; blocks generative design | Runtime bridge in `main.nf` + Dockerfile PATH/Zenodo priors |
| **2** | **Cryo coldstart `BLOCKED_REQUIRED`** | Demo narrates EMPIAR but never exposes absolute `movies_path` S3 URI | Fix `cryo_inputs.json` + cold-start demo context |
| defer | UI autopsy (`drugtest@`) | Needs owner creds | Still open |
| defer | Chat prose rewrite | Intentional — Findings/report SoT | Still open |
| defer | Voice Agent Voice/Speed/Mic | No backend catalog/API | Still deferred |
| defer | Sync from Cursor | SSM/proxy often blocked | Operator sync |

## Root causes

### REINVENT4
- Live Batch jobs use the correct image `…/biomate/reinvent4-nf:x86` but exit **3**.
- Nov-10 ECR push is effectively a **git checkout at `/opt/REINVENT4`** without PATH `reinvent` console script and without staged `.prior` files (priors dir README-only / Zenodo note).
- Repo Dockerfile (pip + curl priors) was **not** what got pushed; Nextflow Batch also strips micromamba ENTRYPOINT (`bash -c …`).

**Ship now (syncable without rebuild):** `GENERATE_REINVENT4` bridges `/opt/REINVENT4` on `PYTHONPATH`, calls `reinvent.Reinvent.main_script`, fetches `reinvent_pubchem.prior` from Zenodo when staged priors missing.

**Still needed for clean image:** rebuild/push `reinvent4-nf:x86` from updated Dockerfile (`PATH=/opt/conda/bin`, Zenodo priors, entrypoint-stripped CLI smoke).

### Cryo coldstart
- Bundle attached `cryo_inputs.json` with relative `Micrographs/` only — no `s3://biomate-cryo-data/empiar-10028/Micrographs/`.
- LLM invents EMPIAR narrative; clarify asks for `movies_path`; Confirm stays blocked (`BLOCKED_REQUIRED` was honest measurement).

**Ship now:** absolute `movies_path` / `staged_movies_s3` in JSON + demo context string with `movies_path=s3://…`.

## Tests
- `npx vitest run client/src/components/cold-start-demo-catalog.test.ts` → **103 passed** (includes new cryo S3 assertion)
- Inline Python fragment from `GENERATE_REINVENT4` → `compile()` OK

## Sync
- Needs `BIOMATE_SYNC_DB=0 bash scripts/sync_to_dev.sh` when lease FREE / SSM reachable.
- After sync: re-run `design-generate-sm-0` (expect past exit 3 if `/opt/REINVENT4` importable + Zenodo egress); re-seed cryo coldstart str-0 (expect `movies_path` prefilled, Confirm enabled if license OK).
- Image rebuild still recommended so priors/CLI are baked in (no runtime Zenodo dependency).

## Still open after this pass
1. Authenticated UI autopsy (`drugtest@biomate.dev`)
2. Retroactive chat-prose rewrite (deferred by design)
3. Voice catalog / speed / mic / keywords (no backend)
4. Organic I1 Galaxy ECONNREFUSED intermittency
5. `reinvent4-nf:x86` ECR rebuild + live REINVENT re-measure
6. Cryo GPU execution path (license + Confirm after movies bind)
7. Operator sync of prior Bugbot tip + this tip
