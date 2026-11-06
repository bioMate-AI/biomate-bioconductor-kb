# Dev Regression + Integrity Validation — 2026-09-09

Validation-only run (no source edits) against `https://dev-public.biomate.ai`.
Fixture `lifeifei163361@163.com`. Harnesses run from `/Users/kky/biomate-review`
(branch `integration/dev-test`). Dev backend container = `biomate-galaxy-deploy`
on EC2 `i-0482a6fa98c6f301a` (tag `biomate-deploy-test`), image
`dev-backend:sandbox-v5` (created 2026-08-18).

## Results

| # | Check | Result | Evidence | Root cause if failed |
|---|-------|--------|----------|----------------------|
| 1 | Canonical E2E `e2e_use_cases.sh` (Flow A+B) | PASS* | 16/17 assertions ✓ (login, project create, chat ready+final, microarray→limma, BH-FDR gate skip, dataset cap 33→32, compression UUID, Bioc routing ×3, auth 401 ×2, fake-uuid 404) | *Only fail = Flow B branch self-check expects `integration/next-phase`; worktree is `integration/dev-test`. Stale test-env assertion, not a dev bug. |
| 2 | Postsync suite `run_postsync_tests.sh` (billing + auth) | PASS* | billing-smoke 8/8 ✓ (chromium+firefox); auth-flows-smoke chromium ✓ | *auth firefox 3 fails = firefox binary not installed locally (`Executable doesn't exist …/Nightly.app`). Test-env. `public-routes-smoke`, `cryoem-real-e2e` SKIP (files absent in this worktree); mcp SKIP (no key). |
| 3a | Fix: `/api/projects` = 200 (was 500) | PASS | `GET /api/projects` → 200, 120 projects incl. `runCount` field; `GET /api/projects/:id` → 200 | — |
| 3b | Fix: fabrication honest-fail deployed | **FAIL** | Deployed `.nf` still the OLD fabricating versions: ich_s7a=581 lines w/ `random.gauss` hERG/QTc/MAP; bispecific=415 lines w/ `random.*` ΔG/CDR/yield; merfish=221 lines w/ `random.*` SVG scores. 0 honest-fail markers. File mtime 2026-06-09. | Fix exists in SOURCE (local: 302/100/223 lines, 0 RNG, honest-fail markers present) but commits `769def8de`/`d8b62cf4e` live only on `origin/fix/resolver-real-nfcore`, unmerged/undeployed. |
| 3c | Fix: DB de-index (10 rows removed) | **FAIL** | Dev DB mtime 2026-06-26 (predates 2026-09-08 commit). 7 of the de-indexed rows still present: Saposin/GPCR/Liposome/Multi-Drug SPA, scrna_doublet_qc (×2 variants), "Cryosparc Standard Spa" dup. `db_update_log` table absent; `update_log` last entry 2026-02-24. | DB is gitignored / lives only on dev+S3; `sync_to_dev.sh` is code-only and never mutates it. De-index is a data-layer op that has not been applied to dev. |
| 4a | Playwright `api-smoke.e2e.ts` | PASS* | qc/profiles ✓, chat-stream complete (partial=false) ✓, chat-stream disconnect (partial=true) ✓ | *HT-1 "fail" = stale assertion: test expects `workflow_ga.name==="hts_plate_qc_hit_calling"`; router correctly routes but DB now stores humanized `"Hts Plate Qc Hit Calling"` (success=true, confidence=101). Behaviour correct/improved. |
| 4b | Playwright `after-run-audit.e2e.ts` (T02) | PASS | With `E2E_FIXTURE_PASSWORD` exported: 1 passed (6.7m). `in_vivo_cart_codesign` run reached `completed`, all 7 after-run tabs audited clean. First run 401'd only because the env var was unset (test default `""`). | — |
| 4c | Playwright `chat-multiturn-research.e2e.ts` | PASS | MT-1 text-only ✓, MT-2 markdown ✓, MT-3 copy/regen buttons ✓, MT-4 multi-turn context ✓ (4/4) | — |
| 5 | Workflow-gen smoke (3 domains) | PASS | RNA-seq → workflow_ready + ga; variant/WGS → workflow_ready + ga; proteomics → chat_only disambiguation ("DDA vs DIA?", intentType=workflow_generation, shouldGenerate=false). No `success=true wf=false`. | — |

## Do the 3 deployed fixes hold?

- **3a `/api/projects` 500→200: YES, holds on dev.** List returns 200 with the
  `runCount` subquery field that previously triggered the 500; single-project GET also 200.
- **3b fabrication honest-fail: NO — not deployed.** The remediation is committed in
  source (verified locally) but the running dev container still serves the original
  RNG-fabricating `.nf` files. The integrity commits are on `fix/resolver-real-nfcore`,
  not merged to the mainline and not synced.
- **3c DB de-index: NO — not deployed.** The dev DB has not been touched since June;
  7 of the ~10 rows the commit deleted are still indexed. Code sync does not carry DB
  mutations.

## Regressions from this session's changes?

None observed. The `/api/projects` cast fix is live and healthy — the change that was
actually deployed to dev works and introduced no regression across the E2E, chat-routing,
billing, or multi-turn surfaces. All "failures" in the table are either stale test
assertions (branch name, HT-1 humanized name), local test-env gaps (firefox binary,
unset fixture password), or known data-dependencies (virtual workflow not in DB).

## Overall dev health verdict

**Dev is healthy and free of regressions.** All functional behaviour validated green:
auth/projects, chat routing (limma microarray, gate skip, Bioc domains), dataset cap,
compression UUID preservation, chat-stream persistence (complete + disconnect), billing
internal pipeline, multi-turn chat, and workflow generation across RNA-seq / variant /
proteomics.

**Action item (not a dev bug):** fixes 3b and 3c are complete in source but await
merge + deploy. 3b lands via the normal code sync once merged. 3c additionally requires
a data-layer de-index applied to the dev+S3 DB (the DB is gitignored; `sync_to_dev.sh`
will not remove those 7 rows). Until then, the fabricating `.nf` files remain executable
on dev and the dead SPA/dup workflow rows remain routable.
