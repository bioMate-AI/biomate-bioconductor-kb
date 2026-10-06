# Design & Implementation Plan — On-Prem Scope Layer

**Date:** 2026-10-05 · **Status:** design (approved direction; not yet built) · **Target branch:** `integration/next-phase`
**Related:** `docs/20261005_ONPREM_SCOPED_DEPLOYMENT.md` (verified capability assessment).

## 1. Problem & goal
A customer wants BioMate on-prem limited to a **required subset** of domains / tasks / instruments — not the
full ~4,210-workflow catalog with every biocontainer. Today the on-prem stack ships and serves **everything**,
and nothing refuses an out-of-scope workflow at run time. Goal: a **one-command scoped build** —
declare scope → produce a manifest + an in-scope image set → the running instance only surfaces and only
executes in-scope work, refusing the rest with a clear error.

## 2. Core design decisions
1. **Enforce, don't subtract (DB ships whole).** The catalog DB (`galaxy_ai_tools.db`, ~324 MB) and its
   `.npz` embeddings and all `.nf` files ship **complete**. Scope is a **runtime allow-list**, not a filtered
   DB. Rationale: the DB is tiny next to the GB-scale container images; subsetting it means a fragile FTS5
   rebuild + keeping `.npz` rows index-aligned, for ~zero size payoff. (User decision, 2026-10-05.)
2. **The only trimmed artifact is the container-image set.** That is where the GBs are. The build emits a
   pull/mirror list of **in-scope images only**, seeded into the on-prem private registry.
3. **Fail-safe OFF for SaaS.** Enforcement is active **only** when a scope manifest is configured
   (`BIOMATE_SCOPE_MANIFEST` set). Unset → unchanged full-catalog behavior. This mirrors the quota
   fail-safe pattern and guarantees the SaaS platform is never accidentally scoped.
4. **Single source of truth.** One `manifest.json` drives both the runtime gate and (by construction) the
   image mirror-list, so "what's installed" and "what's allowed" cannot drift.
5. **Minimal surface.** Reuse the existing offline manifest generator and the plain-SQLite `domain` column;
   add one small guard module and three call-site hooks. No executor rewrite.

## 3. Architecture

```
  deployment_scope.yml ──► build_scope_manifest.py ──► manifest.json  ──┐
         (operator)              (offline, read-only DB)                │ (BIOMATE_SCOPE_MANIFEST)
                                        │                               ▼
                                        └─► image_mirror.sh ──►  scope_guard.py  (loaded once at startup)
                                            (seed private registry)      │
                                                                         │ is_in_scope(...)
                                   ┌─────────────────────────────────────┼───────────────────────────┐
                                   ▼                                     ▼                             ▼
                        execute_nextflow()                    UnifiedWorkflowSearch /        connector/MCP
                        (nextflow_executor.py:5272)           generate_workflow_*            instrument surface
                        → 409 OUT_OF_SCOPE                    → filter results               → hide out-of-scope
```

Full DB + `.npz` + `.nf` are present on disk at all times; `scope_guard` is the gate between them and the user.

## 4. The manifest (`manifest.json`)
Emitted by the build tool; consumed by the runtime. Frozen allow-list, declarative, human-auditable:
```json
{
  "scope": { "domains": ["transcriptomics", "variant_calling"], "explicit_workflows": [] },
  "workflows": { "by_name": ["nf-core/rnaseq", "nf-core/sarek", ...],
                 "by_nextflow_path": ["nextflow_nfcore/.../rnaseq/main.nf", ...] },
  "tools_allowlist": ["fastqc", "star", "salmon", "gatk4", ...],
  "instruments": ["illumina_novaseq", "thermo_orbitrap"],
  "images": ["quay.io/biocontainers/star:2.7...", ...],
  "generated_at": "2026-10-05T...", "catalog_sha": "<db content hash>"
}
```
- `by_nextflow_path` is the authoritative key for the execute gate (the execute request carries
  `nextflow_path`). `by_name` + `tools_allowlist` serve the search filter and messaging.
- `catalog_sha` lets the runtime warn if the manifest was built against a different DB than the one shipped.

Operator-facing input `deployment_scope.yml` (ergonomic front-end over the manifest):
```yaml
domains: [transcriptomics, variant_calling]   # OR
workflows: [nf-core/rnaseq, nf-core/sarek]     # explicit (overrides domains)
deny: []                                        # optional subtractive
instruments: [illumina_novaseq, thermo_orbitrap]
```

## 5. Components to build

### 5.1 `scope_guard.py` (NEW) — `backend/lib/galaxy/ai/scope_guard.py`
The single enforcement authority. Loaded once (module-level, lazy) and cheap to query.
```python
def enforcement_enabled() -> bool:
    # True iff BIOMATE_SCOPE_MANIFEST points at a readable manifest.json. Fail-safe OFF otherwise.

def _manifest() -> dict | None:        # cached parse; re-read if mtime changes
def is_workflow_in_scope(*, nextflow_path: str = "", name: str = "") -> bool:
    # normalize path (strip leading ./, /app prefixes); match against by_nextflow_path, then by_name.
def is_tool_in_scope(tool: str) -> bool
def filter_workflows(rows: list[dict]) -> list[dict]   # for search/router result filtering
def assert_in_scope_or_raise(nextflow_path, name, file_content)  # raises ScopeError(409 payload)
```
Rules:
- `enforcement_enabled()` False → every `is_*` returns True (no-op; SaaS default).
- **Raw `file_content`** (no catalog identity): if its content resolves to a known in-scope `.nf` (by content
  hash against shipped in-scope files) → allow; otherwise **reject** (can't verify scope of arbitrary `.nf`).
- Path normalization must match how `execute_nextflow` receives `nextflow_path` (relative under the workflows
  root); unit-test the normalizer against real catalog paths.

### 5.2 Execute enforcement hook — `nextflow_executor.py:5272` (`execute_nextflow`)
Immediately after request parse / before any dispatch or Batch/local branch:
```python
try:
    scope_guard.assert_in_scope_or_raise(
        nextflow_path=request.nextflow_path,
        name=getattr(request, "workflow_name", "") or "",
        file_content=request.file_content,
    )
except scope_guard.ScopeError as e:
    raise HTTPException(status_code=409, detail=e.payload)   # {"error":"OUT_OF_SCOPE","workflow":...,"scope_hint":...}
```
Covers BOTH the catalog path (`nextflow_path`) and the raw `.nf` path (`file_content`, handled at :5289).
Also gate the resume/fallback entrypoints that reconstruct `nextflow_path` (:6558, :6594) so a resume can't
re-launch an out-of-scope run.

### 5.3 Search / router filtering — `unified_workflow_search.py:335` + `ai_assistant.py:3441/3919`
- In `UnifiedWorkflowSearch` result assembly, pass the final rows through `scope_guard.filter_workflows()`
  so out-of-scope workflows never appear in search, routing, or suggestions.
- In `generate_workflow_unified` / `generate_workflow_multi_agent`, if the selected workflow is out of scope,
  return a clean "not available in this deployment" response rather than a card the user can't run.
- This makes the gate *felt* as "not offered," with the execute 409 as the hard backstop.

### 5.4 `build_scope_manifest.py` (NEW, offline) — `evaluation/local_trial/` (+ land `export_deployment_manifest.py` on next-phase)
Thin evolution of the existing `export_deployment_manifest.py` (currently this-branch-only — land it on
next-phase first). Input `deployment_scope.yml` + read-only `galaxy_ai_tools.db`. Output:
- `manifest.json` (§4) — resolve domains/workflows → workflow ids + `nextflow_path`s + union of `tools_used`
  + instruments; record `catalog_sha`.
- `image_mirror.sh` — for in-scope workflows only, resolve images from `tools.container_info.image` **and**
  each `.nf`'s `container` directive (the executor honors the `.nf` directive over the DB —
  see memory `reference_executor_container_resolution`); emit `docker pull → tag localhost:5050/... → push`.
- Does **not** touch the DB, `.npz`, or `.nf` files.

### 5.5 Per-deployment instrument gating — connector/MCP surface
Gate the instrument/connector tools exposed to the assistant by `manifest.instruments`, mirroring the
existing `local_only` surface-gating pattern in the connector's `tools_manifest` (`to_anthropic`/`to_openai`).
Smallest piece; depends on `biomate-connector` coordination (separate repo).

## 6. Configuration (env)
| Var | Meaning | Default |
|---|---|---|
| `BIOMATE_SCOPE_MANIFEST` | Path to `manifest.json`. **Set = enforce; unset = full catalog (SaaS).** | unset |
| (reuses) `BIOMATE_LOCAL_REGISTRY` | Where `image_mirror.sh` pushes in-scope images | `localhost:5050` |

Document these in `.env.onprem.example` + `docs/ONPREM_SETUP.md` alongside the executor knobs (PR #271 pattern).

## 7. Behavior matrix
| Deployment | Manifest | Request | Result |
|---|---|---|---|
| SaaS | unset | any | runs (unchanged) |
| On-prem scoped | set | in-scope catalog wf | runs |
| On-prem scoped | set | out-of-scope catalog wf | `409 OUT_OF_SCOPE`; not shown in search |
| On-prem scoped | set | raw `.nf` matching an in-scope file | runs |
| On-prem scoped | set | arbitrary raw `.nf` | `409 OUT_OF_SCOPE` (unverifiable) |
| On-prem scoped | set | resume of an out-of-scope run | `409` |

## 8. Testing
- **Unit (`scope_guard`)**: enforcement off → all allow; path normalization vs real catalog paths; in/out
  workflow by path + by name; tool in/out; raw-`.nf` hash match vs mismatch.
- **Integration (execute)**: with a hand-written `manifest.json` (full DB present) — in-scope `nextflow_path`
  dispatches; out-of-scope → 409; `file_content` arbitrary → 409; resume of out-of-scope → 409.
- **Search filter**: a query that would rank an out-of-scope workflow first returns only in-scope results.
- **Build tool**: `build_scope_manifest.py` on a 2-domain scope → manifest's workflows all resolve, every
  referenced image is in `image_mirror.sh`, DB/`.npz`/`.nf` unchanged on disk.
- No manifest set → full regression suite unchanged (proves SaaS is untouched).

## 9. Sequencing (smallest-risk first)
1. **`scope_guard.py` + execute hook + unit/integration tests** — the hard backstop; independently testable
   with a hand-written manifest and the full DB. Ship first; this alone makes scoping real.
2. **Search/router filtering** — turns "refused" into "not offered."
3. **`build_scope_manifest.py` + image mirror** — automates manifest + the actual size win.
4. **`deployment_scope.yml` front-end** — ergonomics over #3.
5. **Instrument gating** — last; needs connector-repo coordination.

Each step is shippable on its own and leaves SaaS behavior unchanged (fail-safe OFF).

## 10. Risks & non-goals
- **Path-normalization mismatch** is the main correctness risk (the execute key is `nextflow_path`); mitigated
  by unit-testing the normalizer against real catalog rows and failing *closed* only for the raw-`.nf` path
  (catalog lookups fail *open*-to-404-style clarity, never a silent run).
- **Container-image resolution is incomplete today** (`container_info.image` largely empty in the DB); the
  mirror-list must fall back to the `.nf` `container` directive, and flag unresolved tools for manual mirroring.
- **Non-goals:** subsetting the DB (rejected by design); PBS/SGE/LSF executors (compute layer, separate);
  add-on domain packs (future — the manifest format already leaves room via `scope`).
