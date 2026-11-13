# 2026-11-13 — Findings/report class audit: metrics-first, refuse hollow sidecars

## Session autopsy (live)

| Field | Value |
|-------|--------|
| URL | https://dev-public.biomate.ai/?session=chat-1794589821204-kwkyrwqu5 |
| Owner | `drugtest@biomate.dev` (E2E fixture `lifeifei163361@163.com` → **403** on run APIs) |
| Run | `727de1b4-5bed-4409-92ca-d7ba10a7f46e` · potency predictor · completed |
| S3 prefix | `s3://biomate-nextflow-work/nextflow/outputs/37942b0f-a383-47e5-a36e-d570e5331820/042dc0da/` |
| Live tip (build-info) | `562908a3` — **contains** findings fix `a41a9a76` as ancestor |

### After-run surfaces (quoted)

**Outputs (authoritative):**
- `results/metrics.json` → `test_mae=0.792046…`, `val_mae=0.943304…`
- `results/artifact/manifest.json` → scaffold `bemis_murcko_scaffold` train/val/test = 1211/151/151
- `…/training_progress.json` → best-checkpoint R² under **`pIC50.r2`** (not `combined.r2`): test 0.3724 / val 0.4462 / train 0.3007

**Findings sidecar BEFORE fix (poison):** Ludwig combiner / MolLogP means; caveat *"No model training or validation performance metrics are present"* — false.

**Findings sidecar AFTER heal (S3 `output/findings_data.json`, re-verified this session):**

> potency predictor finished. Key scores: test MAE=0.7920; validation MAE=0.9433; gate pass. Read the Key Results table below (sourced from metrics.json); full artifacts remain in Outputs.

Key Results order (score-first): Test MAE → Validation MAE → Test/Validation/Train R² → Data split → Gate · MAE.

**Report download bytes** (same source the `/findings/report` route renders from S3 when cache empty): markdown table with those rows. Evidence file: `frontend/e2e/execshots/ml-findings-report-healed.md`.

**Chat prose:** not re-fetched (owner ≠ fixture); Findings tab binds the same `/findings` JSON the sidecar holds.

---

## Pipeline trace (every gate)

```
output_files | runsOutputsService.list
        │
        ▼
scoreFindingsSampleName  ──►  top 8 text samples (~1MB each)
        │                     (metrics/toxicity/DESeq2 ↑ ; Ludwig hyperparams/qc_events/NF logs ↓)
        ▼
preProcessForFindings
  ├─ ADMET → deterministic findings (skip LLM)
  ├─ ml_training / name heuristics → parseMlTrainingFindings (skip LLM)
  ├─ DESeq2 / enrichGO / raredisease → context only (legacy)
  └─ else null
        │
        ▼
matchDescriptor → buildFindingsDocument  (ADMET/DESeq2/enrichGO/variant)
        │
        ▼
NEW: if no flat findings but document.records.length → documentToLegacy (skip LLM)
        │
        ▼
else LLM (8KB/file) + numeric grounding
        │
        ▼
_findingsCache + persistFindingsSidecar → S3 …/output/findings_data.json
        │
        ▼
GET /findings  read order:
  1. local findings_data.json  ── refuse if looksLikeHollowFindings
  2. S3 sidecar                 ── refuse if hollow
  3. in-memory cache            ── refuse if hollow
  4. regenerate
        │
        ▼
FE FindingsCard (summary + score-preferring chips + Key Results table always open in panel)
GET /findings/report → renderFindingsMd(cache|S3)  ── refuse hollow
```

### Gates that previously served fluff

| Gate | Failure mode | Status |
|------|--------------|--------|
| S3/local sidecar shape check | `isFindingsShaped` accepts any string summary | Still true — **hollow detector** now refuses fluff |
| Fluff refuse gated on `isModelTrainingRun` | Mis-tagged / name-only runs kept poison | **Fixed** — refuse on content for all workflows |
| Canonical resolver unranked `slice(0,6)` | Missed `metrics.json` when `/output_files` empty | **Fixed** — same `scoreFindingsSampleName` |
| DESeq2/enrichGO/variant → LLM only | Descriptor existed but flat still LLM | **Fixed** — `documentToLegacy` when records present |
| Key Results chips = `kr.slice(0,3)` | Gate row first buried Test MAE | **Fixed** — scores before gate; chips prefer non-Gate |
| Report route only in-memory | Empty report while Findings OK | Already fixed in `a41a9a76` (S3 fallback) |
| R² under `pIC50` not `combined` | Heal/parser missed live Ludwig shape | Parser already had `pIC50.r2`; tests + sidecar healed |

---

## Class coverage

| Domain | Deterministic path | Hollow refuse | Remaining gap |
|--------|-------------------|---------------|---------------|
| ml_training | `parseMlTrainingFindings` | yes | Docking-style models without metrics.json still LLM |
| ADMET | `_parseAdmetOutput` + descriptor | yes (class) | — |
| DESeq2 / enrichGO / variant | **descriptor → documentToLegacy** (new) | yes | Rare-disease flat parser still context-only if descriptor miss |
| Docking / Vina / Boltz | none | hollow only if LLM admits missing | **Open:** no vina-score descriptor yet |
| Generic LLM | last resort | hollow refuse on re-open | Can still write mediocre prose once; next open heals if hollow-shaped |

---

## Cache poison durability

- Refuse-fluff on **local disk, S3, in-memory, report route** — no longer requires `isModelTrainingRun`.
- Regen overwrites S3 via `persistFindingsSidecar` (durable across gunicorn/Node workers).
- In-memory `_findingsCache` is per-process; S3 is the cross-worker source of truth after first good persist.
- This session’s poison sidecar was overwritten with `evidence_version: ml-training-metrics-v1`.

---

## UX

- Card title: **Findings · key scores from outputs**
- Headline chips: prefer Test/Val/MAE/R² over `Gate · …`
- Panel: Key Results table **always expanded** (chat preview still collapsible)
- Summary string explicitly points at the Key Results table + metrics.json

---

## Tests

```bash
cd frontend && npx vitest run \
  server/ml-training-findings.test.ts \
  server/findings-quality.test.ts \
  client/src/components/findings-card.test.tsx
# 19 passed (as of this session)
```

Coverage added: sampling rank, hollow/fluff refusal (incl. source_file + empty redirect), missing metrics → null, score-before-gate report table, live pIC50 R² nesting.

---

## Live tip / deploy

- Public `build-info.json` at audit time: `562908a3` (ancestry includes `a41a9a76`).
- Class follow-ups in this worktree (findings-quality, routes, FindingsCard) need a normal `BIOMATE_SYNC_DB=0` sync after commit to land on DEV.
- S3 sidecar for this run is already healed without waiting for sync.

---

## Remaining gaps (honest)

1. **Docking / structure prediction** still lack deterministic score parsers (vina affinity, Boltz confidence).
2. **Owner ≠ fixture** blocked authenticated UI/API autopsy as lifeifei; S3 + report reconstruction used instead.
3. **Chat stream prose** from the original assistant turn is not rewritten retroactively — only After-run Findings/report.
4. Descriptor document summaries for DESeq2 are still generic (“Assessment completed for N genes…”) — better than LLM fluff, but narrative polish is open.
