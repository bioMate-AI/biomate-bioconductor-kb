# BioMate UX, Param, Routing & Execution Fixes — 2026-04-10

## Summary

Two sessions of iterative UX hardening across the workflow viewer, parameter panel,
chat interface, routing layer, and Nextflow executor.  All changes are on branch
`integration/next-phase`, commits `39a545db7` and `3f809d4e4`.

---

## 1. QC Settings Redesign

**Problem:** QC settings panel showed a generic profile picker + blank key/value boxes.
**Fix:** Replaced with labeled, editable threshold fields auto-detected from workflow domain.

### State changes (`nextflow-workflow-viewer.tsx`)
```typescript
const [availableQcProfiles, setAvailableQcProfiles] = useState<Array<{
  id: string; description: string; domain_hint: string;
  overrides: Record<string, number>;
}>>([]);
const [qcDefaults, setQcDefaults] = useState<Record<string, { bound: number; direction: string; rationale?: string }>>({});
const [qcOverrides, setQcOverrides] = useState<Record<string, number>>({});
```

### Auto-detect profile useEffect
Matches workflow name keywords to domain (cryo_em, rnaseq, …) and pre-selects
the appropriate QC profile without user action.

### `displayedQcThresholds` useMemo
Merges `qcDefaults` + `activeQcProfile.overrides` + user `qcOverrides` into a
flat array of `{ key, label, unit, direction, value, modified }` objects.
Metrics with a user-modified value show a blue border and an × reset button.

### `QC_THRESHOLD_LABELS`
23-entry constant mapping metric keys → human labels + units
(e.g. `resolution_angstrom → "Resolution (Å)"`).

---

## 2. Execution Checklist — Remove When All OK

**Problem:** Checklist showed even when all checks passed, adding noise.
**Fix:** Checklist only renders when `!canRun` AND at least one item has
`status === 'missing'` that isn't `input_data` or `required_parameters`
(those are surfaced directly in the parameter panel).

---

## 3. `hasInlineData` — File Paths Must Not Trigger "Input Data OK"

**Problem:** `beta_gal.mrc` in the user query matched `hasInlineData = true`
because any non-empty param value was counted.
**Fix (`chat-message.tsx`):** Added `FILE_PATH_RE` covering 30+ bioinformatics
extensions. Values matching the regex (bare filenames) are excluded from the
inline-data check.

```typescript
const FILE_PATH_RE = /^[\w./~\-]+\.(mrc|pdb|cif|tif|tiff|eer|fastq|...)$/i;
```

---

## 4. Browse Button — Only on Actual Path Parameters

**Problem:** Backend `_FILE_KW` heuristic matched substring `file` in
`filename`, `file_format`, `sigma_threshold` → assigned `type='file'` → Browse
button appeared on numeric fields.
**Fix (`parameter-group.tsx`):** Browse button gated on param ID ending with
one of `_path`, `_paths`, `_dir`, `_directory`, `_input`, `_output`, `_file`,
`_files`. Numeric/string fields with `type='file'` but no path suffix get a
plain text Input with no Browse button.

---

## 5. License / Credential Masking

**Problem:** `cryosparc_license` rendered as plain text.
**Fix (`parameter-group.tsx`):** `isSecret` check on param ID — any param
containing `license`, `password`, `secret`, `token`, `api_key`, `apikey`,
`credential`, `passphrase`, or `passwd` renders as `type="password"` with
`autoComplete="off"`.

---

## 6. Auto-Scroll on Param Edit — Fixed

**Problem:** `handleParameterChange` → `onChatUpdated` → messages array
reference changes → `displayMessages` dep in scroll useEffect → page scrolled
to bottom on every keystroke in a param field.
**Fix (`chat-interface.tsx`):** Added `prevMessageCountRef = useRef(0)`.
Scroll only fires when `displayMessages.length > prevCount || displayTyping`.

---

## 7. Session Titles — LLM-Generated Summaries

**Problem:** Session titles were first 6 words of the user's query.
**Fix:**
- `chat-history.ts`: After first message pair, async `POST /api/sessions/generate-title`
  with the query text. Word-based title shown immediately as placeholder; replaced
  with Haiku-generated 4-6 word title once the response arrives.
- `routes.ts`: New endpoint calls `claude-haiku-4-5-20251001` with `max_tokens:30`,
  instructed to produce a 4-6 word title. Falls back to first-6-words if no API key.

---

## 8. Routing Fixes

### "Generate sample data" — No Workflow Panel
Added explicit "NEVER workflow_generation" guidance in `galaxy-assistant.ts`
system prompt for data-fabrication requests:
- "Generate a sample [file] for me" → polite refusal + suggest public data sources
- "Create a synthetic/fake/mock [file]" → same
These must not trigger workflow generation regardless of file names in the query.

### CryoSPARC Standard SPA Priority
- `cryosparc_standard_spa/main.nf` was accidentally deleted (git working-tree
  deletion); `_parse_nextflow_steps` returned empty → no phase cards → routing
  fell through to Multi Drug Atlas.
- Restored: `git checkout HEAD -- backend/biomni_workflows/.../cryosparc_standard_spa/main.nf`
- Added explicit routing rule in galaxy-assistant.ts:
  "ROUTING RULE: For ANY standard SPA request → always use cryosparc_standard_spa"
  "Use multi_drug_atlas ONLY when user explicitly has MULTIPLE drug datasets AND
   wants drug-minus-apo difference maps"

---

## 9. Phase Cards — Step Parsing Fix

### Root Cause
`_parse_nextflow_steps` in `ai_assistant.py` used `re.findall(r'\*\s+(\d+)\.\s+(.+)', content)`
on the full file. For `reinvent4_lead_design` and `moe_covalent_docking`, numbered
sub-step comments inside Python `script:` blocks overwrote the top-level phase names
(same `* N.` format, lower index numbers caused dict overwrites).

### Fix
Scan only the file **header** (lines before the first `process` or `workflow` keyword)
for numbered comment steps:
```python
header_lines = []
for line in content.splitlines():
    if re.match(r'^\s*(process|workflow)\s*\b', line):
        break
    header_lines.append(line)
header = '\n'.join(header_lines)
comment_steps = re.findall(r'\*\s+(\d+)\.\s+(.+)', header)
```

### Verified Results
All 26 drug discovery + 15 cryo-EM workflows now produce correct step counts:
- `reinvent4_lead_design`: 4 steps (was 6 overwritten sub-steps)
- `moe_covalent_docking`: 5 steps (was 9 mixed steps)
- `cryosparc_standard_spa`: 23 steps (unchanged, correct)
- All others: 1–11 steps via Strategy 2 (UPPERCASE process names)

---

## 10. Nextflow `cwd` — Permission Denied Fix

### Root Cause
Both `subprocess.Popen` calls launched Nextflow with `cwd=str(nf_path.parent)`.
In the Galaxy Docker container, `/app/biomni_workflows/...` is read-only for the
`galaxy` user (UID 999). Nextflow attempts to write temp files (`nxf-tmp.XXXXXX`)
and bootstrap `.nextflow/framework/` in the `cwd`, causing:
```
mktemp: failed to create file via template '...nxf-tmp.XXXXXX': Permission denied
ERROR: Cannot download nextflow required file
```

### Fix (`nextflow_executor.py`)
Changed both Popen calls to use `work_dir` (writable `/tmp/nextflow_runs/<run_id>/work/`):

**Normal path (line ~2370):**
```python
cwd=str(work_dir),   # was: cwd=str(nf_path.parent)
```

**Accession chain thread (line ~1944):**
```python
chain_work_dir = work_base / run_id / "work"
chain_work_dir.mkdir(parents=True, exist_ok=True)
# ...
cwd=str(chain_work_dir),   # was: cwd=str(nf_path.parent)
```

Nextflow is installed (v25.10.4) — the error was entirely due to the read-only cwd.

---

## 11. Docker Health Check Fix

**Problem:** `--health-cmd` passed via SSH heredoc stripped inner single quotes,
turning `require('http')` into `require(http)` → health check always failed.
**Fix (`sync_to_dev.sh`):** Removed `--health-cmd` override from `docker run`.
The Dockerfile's own `HEALTHCHECK` directive handles it correctly.

---

## Files Changed

| File | Change |
|------|--------|
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | QC redesign; checklist conditional; phase steps |
| `frontend/client/src/components/parameter-group.tsx` | Browse button path suffix gate; secret masking |
| `frontend/client/src/components/chat-message.tsx` | `FILE_PATH_RE` for hasInlineData |
| `frontend/client/src/components/chat-interface.tsx` | `prevMessageCountRef` scroll guard |
| `frontend/client/src/lib/chat-history.ts` | Async LLM title generation |
| `frontend/server/routes.ts` | `/api/sessions/generate-title` endpoint |
| `frontend/server/galaxy-assistant.ts` | "No workflow for data generation" rule; SPA routing priority |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | `_parse_nextflow_steps` header-only scan |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | cwd → work_dir in both Popen calls |
| `backend/biomni_workflows/.../cryosparc_standard_spa/main.nf` | Restored from git |
| `scripts/sync_to_dev.sh` | Removed --health-cmd override |

## Commits

- `39a545db7` — fix: QC settings redesign + param UX + routing fixes
- `3f809d4e4` — fix: Nextflow cwd read-only + phase step parsing for reinvent4/moe

## Post-Sync E2E Results

Both commits: `smoke-auth` 2/2 PASS, `cryo-em` 1/1 PASS.
