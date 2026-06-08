# Bioconductor Validation — Working Items & Parallel Execution Plan (2026-06-08)

Continuation of the real-execution validation + product-integration effort (master ref:
`biomate-bioc-fix/docs/BIOCONDUCTOR_VALIDATION_MASTER.md`). This doc captures the current
**working items**, the **4-track parallel plan**, and the **repeatable pipeline** so any session
can resume without re-deriving state.

## Goal
Every in-scope Bioconductor workflow (top-650 ∪ rising-stars, infra excluded) is **executable
with accurate output**, written back to the DB, **enriched** (per-step viz/QC), and **routable +
renderable** in BioMate. Tail (rank-651+ non-rising) stays on-demand.

## Current scoreboard (DB `real_exec_status`, source='bioconductor')
| status | count | note |
|---|---|---|
| ok / ok_warnings | **347** | validated, enriched (viz 271/QC 60), routable |
| exec_error | 245 | frontier (version-skew, analysis errors, shape/dim) |
| fixture_failed | 191 | install / masked-error / AnnotationHub / deprecated pkgs |
| skip_input_type | 52→ | binary inputs — fix in flight (real example data) |
| skip_infra | 48 | excluded (empty input_types — not pipelines) |
| NULL (not attempted) | ~2165 | mostly tail; ~807 of the head not yet run |

Rising-stars/cherry (292 pkgs → 448 wf): 137 attempted, **48 executable**, ~311 un-attempted.

## Working items (tracked as tasks #42–#49)
1. **#43** Verify binary re-validation (21 wf) — real BAM/CEL/FCS/cool/VCF fixtures.
2. **#45** Validate remaining ~311 rising-star workflows.
3. **#44** ✅ Binary fixture install timeout (180→900s for `BiocManager::install` fixtures).
4. **#46** fixture_failed (191): (a) on-demand install on fixture path [wired], (b) `_real_err`
   strips docker-pull/AnnotationHub/masking noise ✅, (c) AnnotationHub network = offline/accept,
   (d) deprecated-removed pkgs (ADaCGH2…) → mark, don't chase.
5. **#47** exec_error (245): version-skew `could-not-find-function`, analysis errors, shape/dim.
6. **#48** no_reads viz/API (14): `ggcyto`/`gtrellis`/`mygene`/`rwikipathways` — viz-on-object vs
   input-less API; regenerate or classify.
7. **#49** Sync enrichment to dev (blocked on parallel dev test + parallel libz commit).
8. **#42** Terminate fleet when validation done.

## 4-track parallel plan
| Track | Items | Where | Depends on |
|---|---|---|---|
| **A · Fleet** | #43 (running), #45 rising-stars | spots, background | fixtures generated |
| **B · Code fixes** | #44 ✅, #46 ✅(code), #48 | local, concurrent | — |
| **C · Dev** | #49 sync | watcher → sync | parallel dev test clearing |
| **D · Cleanup** | #42 terminate | after A | A done |

**Sequencing:** B's harness fixes (timeout + honest error capture + install) land BEFORE the big
re-validation wave so spot-hours aren't wasted re-running identical failures. #43 + #45 dispatch
as soon as their fixtures exist (binary fixtures built; rising-star fixtures generating).

## Repeatable re-validation pipeline (run per wave as spots land)
```
1. generate fixtures   build_bioc_fixtures_structured.py --pkg-file PKGS   (deterministic)
                       generate_bioc_fixtures.py --pkg-file LLM_TAIL       (GEMINI, novel pkgs)
2. deliver + run       rebuild kit (scripts + corpus+fixtures) -> scp to spot ->
                       realrun_test_bioc_workflows.py --pkg-file SHARD --audit result.json
3. collect             scp result.json -> /tmp/spotresults/
4. write back          write_realexec_to_db.py /tmp/spotresults/*.json   (best-status-wins)
5. sync .nf            copy newly-validated .nf into main tree (render + run)
6. enrich              enrich_bioc_step_metadata.py + enrich_bioc_viz_qc.py  (per-step viz/QC)
7. E2E                 bioconductor-all-validated.e2e.ts  (served + with-steps)
```
Steps 4–7 are idempotent; re-run after every collection. The executable count climbs each wave.

## In-flight background jobs (2026-06-08)
- `b40gksnpq` — waits for rising-star LLM fixture gen (pid 4111326) → signals dispatch of #45.
- `bmy8vvg4k` — collector for #43 binary re-validation on bioc-cherry-10.
- `bf4k1e2vx` — watches parallel nf-core dev test (pid 734611) → unblocks #49 dev sync.

## Commits this session (NOT pushed to integration CI; bioc-fix branch pushed)
- main `03aab7aa6` — DB step_metadata-first steps endpoint + 141 .nf synced
- bioc-fix `d13b742fd` — extract_r fix + viz/QC vocab + 3-tier step extraction
- bioc-fix `0ae9fe9c4` — exclude 32 more infra pkgs (Path-null + empty input_types)
- bioc-fix `dbbca30411` — real binary inputs from ExperimentData pkgs (BAM/CEL/FCS/…)
- bioc-fix `b09fce4c2` + `13adee00b` — adaptive fixture timeout + masked-error stripping

## Known unfixable / out-of-scope
- **Removed-from-Bioconductor packages** (ADaCGH2 dep. since 3.14, …) → mark deprecated, exclude.
- **Pure network/AnnotationHub** workflows with no offline path → accept or provide offline cache.
- **48 infra** (containers/IO/data-access) → validated transitively, never as standalone.
