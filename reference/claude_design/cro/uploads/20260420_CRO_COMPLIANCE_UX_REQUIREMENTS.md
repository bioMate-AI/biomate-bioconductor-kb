# BioMate CRO Compliance UI — Detailed UX Requirements
**Date**: 2026-04-20  
**For**: Claude Design  
**Status**: Ready for implementation

---

## Context and Scope

BioMate now has a complete CRO backend for Phase 1/2/3:

| Phase | Backend | Status |
|-------|---------|--------|
| 1 — PBPK Model Validation | `model_validation.py` + `applicability_domain.py` | ✅ Done |
| 2 — 21 CFR Part 11 Audit + eSig | `audit_store.py` + `esig.py` | ✅ Done |
| 3 — Auto-Retrain Loop + IND Assembly | `auto_retrain.py` + `ind_assembly.py` | ✅ Done |

None of Phase 1/2/3 has any frontend. The existing drug discovery UI (`drug-discovery-action.tsx`, 412 lines) covers assay upload, CRO CSV export, and basic compound ranking — it needs to be extended, and several new surfaces need to be built.

This document specifies **seven new UI surfaces** required to make BioMate's CRO product usable end-to-end. It follows the same design language as the existing BioMate panel system (see `docs/20260419_BIOMATE_UI_DESIGN_SPEC.md` for reference patterns).

---

## Reference: Existing Design Language

Carry forward these conventions from the existing codebase and spec:

**Colors & Tokens**
- Panel border: `border-blue-200 dark:border-blue-800`
- Panel bg: `bg-blue-50/50 dark:bg-blue-950/20`
- Status badge colors: green = completed/pass, amber = advisory/warning, red = failed/halt, blue = running, gray = pending
- Text primary: default foreground; muted: `text-muted-foreground`
- Success block: green bg with checkmark; error block: red bg with alert triangle
- Dark mode: all components must have `dark:` variants

**Component Patterns**
- Collapsible sections: `<Collapsible>` with trigger + content (chevron rotates on open)
- Status badges: `<Badge variant="outline">` with color class override
- Cards: `<Card><CardHeader><CardTitle>` + `<CardContent>`
- Tabs: `<Tabs defaultValue="..."><TabsList><TabsTrigger>` + `<TabsContent>`
- Dialogs: `<Dialog>` wrapping a `<DialogContent>` with `<DialogHeader>`
- Buttons: primary = `<Button>`, secondary = `<Button variant="outline">`, icon = `<Button variant="ghost" size="icon">`
- Progress: `<Progress value={n} className="h-1.5"/>`
- Loading: `<Loader2 className="h-4 w-4 animate-spin"/>`
- Icons from `lucide-react` throughout

**Layout Rule**
All new CRO surfaces live inside the **right panel** (the 500px `nextflow-workflow-viewer` area) or as **chat-embedded cards** triggered by drug discovery AI responses. No new pages or routes.

**Existing file to extend**: `frontend/client/src/components/drug-discovery-action.tsx`

---

## Surface 1 — Campaign Dashboard (Enhanced)

### What it replaces
The current `dashboard` mode in `drug-discovery-action.tsx` shows a basic compound ranking table (top 10, score bars). Replace it with a full campaign lifecycle view.

### Layout

```
┌─ Campaign: {campaign_id} ──────────────────────── [↻ Refresh] ─┐
│ ● ACTIVE  •  Round 3  •  42 compounds ranked  •  Last: 2h ago  │
│                                                                  │
│ ▸ DMTA Loop Progress                                            │
│   DESIGN ──●── MAKE ──○── TEST ──○── ANALYSE                   │
│             completed  pending  pending   waiting               │
│                                                                  │
│ ▸ Top 10 Compounds  [See all 42 →]                              │
│   # │ Compound ID │ Score │ AD Status │ Round proposed          │
│   1 │ CPD-0087   │ ████░ 0.89│ in domain │ Round 2             │
│   2 │ CPD-0043   │ ███░░ 0.71│ in domain │ Round 1             │
│   3 │ CPD-0021   │ ███░░ 0.68│ ⚠ OOD    │ Round 1             │
│   ...                                                            │
│                                                                  │
│ [↑ Ingest New Assay Results]  [→ Export CRO Order]             │
└──────────────────────────────────────────────────────────────────┘
```

### Data Source
`GET /api/drug-discovery/{campaign_id}/compounds`  
Returns: `{compounds: [{compound_id, rank, composite_score, ad_status, round_proposed}], campaign_round, total_compounds, last_updated}`

### Behaviour
- **DMTA progress bar**: 4 fixed nodes (Design → Make → Test → Analyse). Active step highlighted with solid dot. Completed steps have check icon. Pending steps hollow. Tooltip on hover shows last action timestamp.
- **AD Status column**: Green `in_domain` badge or amber `⚠ OOD` badge. OOD row has slightly muted text.
- **Score bar**: Green if ≥ 0.7, amber 0.4–0.69, red < 0.4. Width proportional to score. Score value shown to right.
- **[↑ Ingest New Assay Results]**: Switches to assay upload mode (existing).
- **[→ Export CRO Order]**: Switches to CRO export mode (existing).
- **[See all 42 →]**: Expands inline table from 10 to all rows (no new page).
- Refresh polls every 30s when auto-retrain loop is running (see Surface 4).

---

## Surface 2 — PBPK Validation Panel

### Entry point
New tab "Validation" inside the drug-discovery-action component. Also triggered when AI mentions model validation in chat (a new card type rendered in the message list).

### Layout

```
┌─ Model Validation Report ─────────────────────── [↻ Re-run] ──┐
│ EMA/CHMP/EWP/37498/2011 criterion                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ ✅ EMA 2-FOLD CRITERION MET                             │  │
│  │    Cmax: 76% within 2-fold  (≥67% required)            │  │
│  │    AUC:  100% within 2-fold (≥67% required)            │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ▸ Aggregate Metrics                      (collapsible)         │
│   ┌──────────┬─────────────┬─────────────┐                    │
│   │ Metric   │ Cmax        │ AUC         │                    │
│   ├──────────┼─────────────┼─────────────┤                    │
│   │ AFE      │ 1.12        │ 1.03        │                    │
│   │ AAFE     │ 1.38        │ 1.28        │                    │
│   │ R²       │ 0.71        │ 0.93        │                    │
│   │ Within 2× │ 76%        │ 100%        │                    │
│   │ Within 3× │ 86%        │ 100%        │                    │
│   └──────────┴─────────────┴─────────────┘                    │
│                                                                 │
│ ▸ Per-Compound Results (31 drugs)        (collapsible)         │
│   [Search: _____________]  [Filter: All ▾]                     │
│   ┌─────────────┬───────┬────────┬──────────┬──────────┐      │
│   │ Drug        │Obs Cmax│Pred Cmax│Fold Err │ AD       │      │
│   ├─────────────┼───────┼────────┼──────────┼──────────┤      │
│   │ Caffeine    │ 2.34  │ 2.71   │ 1.16 ✓  │ in_domain│      │
│   │ Warfarin    │ 0.28  │ 0.31   │ 1.11 ✓  │ in_domain│      │
│   │ Ibuprofen   │ 24.1  │ 18.3   │ 0.76 ✓  │ in_domain│      │
│   │ Propranolol │ 0.14  │ 0.09   │ 0.64 ✓  │ in_domain│      │
│   │ Quinidine   │ 1.8   │ 4.1    │ 2.28 ✗  │ in_domain│      │
│   ...                                                           │
│   Showing 10 of 31  [Load more]                                │
│                                                                 │
│ Generated: 2026-04-20 14:32 UTC  [📄 Download PDF report]     │
└────────────────────────────────────────────────────────────────┘
```

### Data Source
`GET /api/drug-discovery/model-validation?model=pbpk`  
Returns: `ValidationReport` (Pydantic model already defined)

### Behaviour
- **EMA criterion banner**: Green with checkmark when both Cmax and AUC meet the 67% criterion. Red with X if either fails. Always displayed at top — never collapsible.
- **Fold error cell**: Value shown with ✓ (green) if ≤ 2.0, ✗ (red) if > 2.0. Color coding makes scan fast.
- **Filter dropdown**: "All", "Within 2×", "Outside 2×", "OOD compounds only".
- **Search**: Filter by drug name substring.
- **Load more**: Increments view by 10. "Showing 10 of 31" counter always visible.
- **Download PDF report**: Calls `GET /api/drug-discovery/model-validation?model=pbpk&format=pdf` (backend already generates Markdown; pandoc produces DOCX; add PDF or just serve Markdown as download).
- **Re-run**: Calls `POST /api/drug-discovery/model-validation` and shows spinner during re-computation (~1–2s).
- **Excluded drugs note**: Small footnote "1 drug excluded from validation (Clopidogrel — prodrug). [Why?]" with tooltip explaining CL_true > hepatic blood flow.

### Chat card variant
When AI responds to "validate model" or "check EMA criterion", render this as an inline collapsed card in the message bubble (not in the right panel). Header shows EMA pass/fail badge. Click expands to full table in a modal.

---

## Surface 3 — Audit Trail Viewer

### Entry point
New tab "Audit" in the drug-discovery-action component. Also accessible from a global "Compliance" section in the left sidebar (small icon, collapsed by default).

### Layout

```
┌─ Audit Trail ─────────────────── 🔒 Chain: VALID ────────────┐
│ 21 CFR Part 11 §11.10(e)  •  SHA-256 hash chain              │
│                                                               │
│ [Filter by: User ▾] [Action ▾] [Date range ▾]  [⬇ Export]   │
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐  │
│ │ 2026-04-20 14:32 UTC                                    │  │
│ │ 👤 alice@biotech.com  •  INGEST_ASSAY  •  cmp-001      │  │
│ │ Payload SHA-256: 8f3a…d4c1                              │  │
│ │ Record hash: 3b7e…a902  ←  prev: 0000…0000 (genesis)  │  │
│ ├─────────────────────────────────────────────────────────┤  │
│ │ 2026-04-20 14:45 UTC                                    │  │
│ │ 👤 alice@biotech.com  •  PROPOSE_ROUND  •  cmp-001     │  │
│ │ Round 3, 10 proposals  •  Details: auto_retrain        │  │
│ │ Record hash: f1a9…cc32  ←  prev: 3b7e…a902            │  │
│ ├─────────────────────────────────────────────────────────┤  │
│ │ 2026-04-20 15:01 UTC                                    │  │
│ │ ✍ alice@biotech.com  •  ESIG  •  EXPORT_CRO_ORDER     │  │
│ │ Sig ID: 7d3f…  •  Meaning: "I approve synthesis order" │  │
│ │ Record hash: 9c4b…1e78  ←  prev: f1a9…cc32            │  │
│ └─────────────────────────────────────────────────────────┘  │
│                                                               │
│ Showing 10 of 47 records  [Load 10 more]                      │
│                                                               │
│ Chain: 47 records verified ✅  Last verified: just now        │
│ [🔍 Re-verify chain]                                          │
└───────────────────────────────────────────────────────────────┘
```

### Data Source
`GET /api/drug-discovery/audit?resource_id={campaign_id}&limit=10&offset=0`  
`GET /api/drug-discovery/audit/verify`  

### Behaviour
- **Chain validity badge**: Top-right, always visible. Green lock + "VALID" when `verify_chain()` returns `valid=True`. Red broken lock + "TAMPERED — record #{id}" on failure. Re-verified on every mount; "Re-verify chain" button forces a manual re-check.
- **Record rows**: Each row shows timestamp, user, action, resource, payload hash (truncated to 8 chars), record hash (truncated), and `← prev: {hash[:8]}`. Clicking a row expands to show full hashes.
- **ESIG rows**: Distinct visual treatment — ✍ icon, signature manifest hash, meaning text, sig_id. Styled with indigo left border.
- **SYSTEM rows** (auto_retrain events): Distinct robot 🤖 icon, muted styling.
- **Filters**: User dropdown (all users seen in log), Action dropdown (checkboxes for each `AuditAction` constant), Date range picker.
- **Export**: `GET /api/drug-discovery/audit/export?campaign_id={id}` returns a CSV or JSON file of all records + chain verification result.
- **Pagination**: Load 10 more at a time. Newest first.
- **Empty state**: "No audit records yet for this campaign. Records are created automatically when you ingest assay data, export CRO orders, or generate proposals."

---

## Surface 4 — Auto-Retrain Status + Proposal Viewer

### Entry point
New "Auto-Retrain" section inside the existing campaign dashboard card (Surface 1), visible when a virtual library has been saved.

### Layout

```
┌─ Auto-Retrain Loop ──────────────────────────────────────────┐
│  Loop status:  ● RUNNING  (checks every 60s)          [Stop] │
│  Last retrain: 2026-04-20 14:45 UTC (triggered by new assay) │
│  Next check:   in 43s                                        │
│                                                              │
│ ▸ Latest Proposal — Round 3  (2026-04-20 14:45 UTC)         │
│   10 compounds proposed  •  triggered by: auto_retrain       │
│                                                              │
│   ┌──────────────────────────────────────────────────────┐  │
│   │ #  │ SMILES (truncated)    │ Score   │ CI 95%   │ AD │  │
│   ├────┼───────────────────────┼─────────┼──────────┼────┤  │
│   │ 1  │ CC(=O)Nc1ccc(O)cc…   │ 0.87    │0.79–0.95 │ ✓  │  │
│   │ 2  │ COc1cc2c(cc1OC)C…    │ 0.83    │0.74–0.92 │ ✓  │  │
│   │ 3  │ c1ccc(cc1)CC(=O)…    │ 0.71    │0.58–0.84 │ ⚠  │  │
│   │ …  │ …                     │ …       │ …        │ …  │  │
│   └──────────────────────────────────────────────────────┘  │
│                                                              │
│   [📋 Copy SMILES]  [⬇ Download CSV]  [→ Export to CRO]    │
│                                                              │
│ ▸ Proposal History (collapsible)                             │
│   Round 2 • 2026-04-20 11:03 • 10 proposals • manual        │
│   Round 1 • 2026-04-20 08:41 • 10 proposals • manual        │
│                                                              │
│ ▸ Virtual Library                                            │
│   282 compounds cached  •  [Replace virtual library]        │
└──────────────────────────────────────────────────────────────┘
```

### Data Sources
- `GET /api/drug-discovery/{campaign_id}/auto-proposal` — latest proposal
- `GET /api/drug-discovery/{campaign_id}/retrain/status` — loop running/stopped, next check
- `POST /api/drug-discovery/{campaign_id}/retrain/start` — start background loop
- `POST /api/drug-discovery/{campaign_id}/retrain/stop` — stop loop
- `POST /api/drug-discovery/{campaign_id}/virtual-library` — upload new library
- `GET /api/drug-discovery/{campaign_id}/virtual-library` — current library info

### Behaviour

**Loop Status Badge**:
- `● RUNNING` (green dot, pulsing) when `is_loop_running()` returns true.
- `○ STOPPED` (gray dot) when stopped.
- `[Start]` / `[Stop]` button toggles state.
- "Next check: in Xs" — counts down from `check_interval_s`; resets when loop fires.

**Proposal Table**:
- SMILES truncated at 25 chars; hover shows full string in tooltip.
- Confidence interval shown as range `lower–upper`. Wide CIs (range > 0.4) shown in amber.
- AD column: ✓ green for `in_domain`, ⚠ amber for `out_of_domain`.
- Row click expands to show full SMILES + all available details.

**Copy SMILES**: Copies newline-separated SMILES list to clipboard. Brief "Copied!" toast.
**Download CSV**: `GET /api/drug-discovery/{campaign_id}/auto-proposal?format=csv`
**Export to CRO**: Pre-fills CRO export mode (Surface 1) with the proposed SMILES set.

**Proposal History**: Collapsed by default. Each row shows round number, timestamp, n_proposed, trigger source. Click row to expand and view that round's proposal table inline.

**Virtual Library**:
- Shows `{n} compounds cached • saved {relative_time}`.
- `[Replace virtual library]` opens a file picker (`.csv`, `.smi`, `.txt`). Parsed client-side: one SMILES per line or first column of CSV. Uploads via `POST /api/drug-discovery/{campaign_id}/virtual-library` with `{smiles: [...], n_propose: 10, diversity_weight: 0.2}`.
- Small form below file picker: "# proposals per round" (number, 1–50), "Diversity weight" (slider 0–1, default 0.2, tooltip "Higher = more diverse proposals").
- If no library cached: "Upload a virtual library (.csv or .smi) to enable auto-retrain." with a prominent upload button.

**Manual trigger**: A `[Trigger retrain now]` button forces an immediate refit regardless of the polling interval. Shows spinner during execution (~5s). On completion, proposal table refreshes.

---

## Surface 5 — Electronic Signature (eSig) Modal

### When it appears
Automatically shown as a blocking modal when the user attempts any **regulated action** with `BIOMATE_ESIG_REQUIRED=1` env var set:
- Exporting a CRO order
- Ingesting assay results
- Generating an IND package
- Manually triggering a retrain

For non-regulated deployments (env var unset), eSig is skipped and actions proceed normally.

### eSig Setup (first-time enrollment)
Shown the first time a user needs to sign, if they haven't enrolled yet.

```
┌─ Set Up Electronic Signature ─────────────────────────────────┐
│                                                               │
│  BioMate uses time-based one-time passwords (TOTP) for       │
│  electronic signatures under 21 CFR Part 11 §11.200.         │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                                                         │ │
│  │          [QR CODE  160×160px]                          │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  1. Install an authenticator app (Google Authenticator,       │
│     Authy, or any TOTP-compatible app).                       │
│  2. Scan the QR code above.                                   │
│  3. Enter the 6-digit code shown in your app:                 │
│                                                               │
│     [  ___  ___  ___  ___  ___  ___  ]  ← OTP input         │
│                                                               │
│     [Verify and Enable →]                                    │
│                                                               │
│  ⚠ If you lose access to your authenticator, contact your    │
│    system administrator to reset your eSig enrollment.        │
└───────────────────────────────────────────────────────────────┘
```

### eSig Sign modal (enrolled users)

```
┌─ Electronic Signature Required ───────────────────────────────┐
│                                                               │
│  Action:  EXPORT_CRO_ORDER                                    │
│  Campaign: cmp-001                                            │
│  Target:  WuXi AppTec — 10 compounds                         │
│                                                               │
│  Meaning of signature:                                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ I approve the synthesis order for campaign cmp-001      │ │
│  │ and confirm I have reviewed the compound selection.     │ │
│  └─────────────────────────────────────────────────────────┘ │
│  (This text will be permanently recorded in the audit trail.) │
│                                                               │
│  Enter your 6-digit authenticator code:                       │
│                                                               │
│     [  ___  ___  ___  ___  ___  ___  ]                       │
│                                                               │
│     [Cancel]                      [Sign and Continue →]      │
│                                                               │
│  21 CFR Part 11 §11.200(a)(1): This signature is uniquely    │
│  linked to the signatory and cannot be reused.               │
└───────────────────────────────────────────────────────────────┘
```

### Data Sources
- `POST /api/drug-discovery/esig/register` — enroll user, returns `{secret_b32, qr_uri}`
- `POST /api/drug-discovery/esig/sign` — `{user_id, action, meaning, totp_token}`
- Frontend generates QR code from `qr_uri` using a QR library (e.g. `qrcode` npm package)

### Behaviour
- **OTP input**: 6 individual single-character inputs. Auto-focus advances on digit entry. Backspace returns focus. Auto-submits on 6th digit.
- **Error state**: Wrong code → red border on inputs + "Invalid code. Try again." message. No lockout (backend handles replay within window).
- **Success state**: Brief green "Signed ✓" flash (500ms), modal closes, original action proceeds.
- **Countdown**: Small timer below input shows seconds until code expires (30 - (now % 30)). Inputs auto-clear and refocus at expiry so user can enter a fresh code.
- **Loading**: While verifying, inputs disabled + spinner on "Sign and Continue" button.
- **Cancel**: Closes modal. Original action is NOT performed. Campaign stays unchanged.

---

## Surface 6 — IND Section Assembly Panel

### Entry point
New "IND Assembly" tab in the drug-discovery-action component. Only visible when the user has at least one completed validation report and at least 5 compounds ranked.

### Layout

```
┌─ IND Section Assembly (CTD §2.6.1) ───────────────────────────┐
│ ICH M4 Nonclinical Overview — Pharmacology                    │
│                                                               │
│ ▸ Campaign Details                    (required)              │
│   Investigational compound: [___________________________]     │
│   Biological target:        [___________________________]     │
│   Therapeutic indication:   [___________________________]     │
│   Sponsor organization:     [BioMate Technologies      ]     │
│                                                               │
│ ▸ Contents Preview                                            │
│   ✅ 2.6.1.1  Overview of Methods        (ready)             │
│   ✅ 2.6.1.2  PBPK Model Qualification   (31 drugs, EMA ✓)  │
│   ✅ 2.6.1.3  ADMET Predictions          (42 compounds)      │
│   ✅ 2.6.1.4  Compound Prioritization    (Round 3 data)      │
│   ✅ 2.6.1.5  Applicability Domain       (coverage: 89%)     │
│   ⚠  2.6.1.6  Audit Trail               (47 records, valid) │
│                                                               │
│ ⚠  1 warning: Pandoc not found — DOCX output unavailable.   │
│    Markdown report will be generated.                         │
│                                                               │
│                     [Generate IND Package →]                  │
│                                                               │
│ ──────────────────────────────────────────────────────────── │
│ Last generated: 2026-04-19 09:14 UTC  [Round 2]              │
│                                                               │
│ Downloads:                                                     │
│   📄 cmp-001_CTD_2.6.1.md    [⬇ Download]  42 KB            │
│   📝 cmp-001_CTD_2.6.1.docx  [⬇ Download]  186 KB  ← if available │
│                                                               │
│ [Regenerate]  — overwrites previous files                     │
└───────────────────────────────────────────────────────────────┘
```

### Data Source
`POST /api/drug-discovery/{campaign_id}/ind-assembly`  
Body: `{molecule_name, target_name, indication, sponsor}`  
Returns: `AssemblyResult` — `{markdown_path, docx_path, sections, warnings, generated_at}`

`GET /api/drug-discovery/{campaign_id}/ind-assembly/download?format=md|docx`

### Behaviour

**Contents Preview** section (always shown before generation):
- Each section row shows a ✅ (data available) or ⚠ (data incomplete) or ❌ (missing prerequisite).
- Tooltip on each row explains what data it will pull: e.g. "2.6.1.2 pulls from the PBPK validation report run against 31 reference drugs."
- **Section 2.6.1.2**: Shows "(31 drugs, EMA ✓)" if criterion met or "(EMA ✗)" if not met. Clicking the row navigates to the Validation tab (Surface 2).
- **Section 2.6.1.6**: Shows audit record count and chain validity status.

**Generation**:
- "Generate IND Package →" button is disabled until all 3 required fields are filled.
- On click: button shows spinner + "Generating…" text. Progress shown via a simple indeterminate bar.
- On completion: downloads section appears with both files.
- On error: red error block with message.

**Warning about Pandoc**: Shown in amber if `pandoc_available: false`. Describes how to install. DOCX download is hidden (not shown with strikethrough — just absent).

**Regenerate**: Replaces previous files. Shows a brief "Are you sure? This will overwrite the existing IND package." inline confirmation (not a full modal — just a second click: button text changes to "Confirm overwrite" for 3 seconds, then reverts if not clicked again).

---

## Surface 7 — Campaign Creation Flow

### Entry point
A new "New Campaign" action in the drug-discovery-action component header area, or triggered when the AI responds to "start a drug discovery campaign".

### Layout (step-by-step, in-card wizard)

**Step 1 of 3 — Campaign Setup**
```
┌─ New Drug Discovery Campaign ──────────────────────────────────┐
│                                                           1/3  │
│                                                               │
│  Campaign ID:     [cmp-_______________]  (auto-generated ✓)  │
│  Compound name:   [_________________________]                 │
│  Target:          [_________________________]                 │
│  Indication:      [_________________________]                 │
│  Objective:       ○ Maximize potency                          │
│                   ○ Optimize ADMET profile                    │
│                   ○ Balance potency + ADMET                   │
│                                                               │
│                                    [Cancel]  [Next →]         │
└───────────────────────────────────────────────────────────────┘
```

**Step 2 of 3 — Upload Seed Compounds**
```
┌─ New Drug Discovery Campaign ──────────────────────────────────┐
│                                                           2/3  │
│  Upload your initial compound set (SMILES format):            │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  📄 Drag and drop .csv, .smi, or .txt file here        │ │
│  │     or [Browse files]                                   │ │
│  │                                                         │ │
│  │  Format: one SMILES per line, or CSV with SMILES in     │ │
│  │  first column. Compound IDs optional (second column).   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ✅ 282 compounds parsed  (0 invalid SMILES)                  │
│                                                               │
│  This library will be used as the virtual library for        │
│  auto-retrain proposals.                                      │
│                                                               │
│                                    [← Back]  [Next →]         │
└───────────────────────────────────────────────────────────────┘
```

**Step 3 of 3 — Confirm and Launch**
```
┌─ New Drug Discovery Campaign ──────────────────────────────────┐
│                                                           3/3  │
│  Campaign ID:        cmp-a4f3b2c1                             │
│  Target:             EGFR                                     │
│  Indication:         NSCLC                                    │
│  Virtual library:    282 compounds                            │
│  Auto-retrain:       ● Enabled (check every 60 min)          │
│  21 CFR Part 11:     ● Audit trail active                     │
│  Model validation:   Running…  ████████░░ 80%                 │
│                                                               │
│  Once launched, BioMate will:                                 │
│  1. Run PBPK model validation against 31 reference drugs      │
│  2. Start the audit trail for this campaign                   │
│  3. Activate auto-retrain loop (triggers on new assay data)  │
│  4. Enable CRO order export and IND assembly                  │
│                                                               │
│                              [← Back]  [Launch Campaign →]   │
└───────────────────────────────────────────────────────────────┘
```

### Data Source
`POST /api/drug-discovery/campaigns`  
Body: `{campaign_id?, molecule_name, target_name, indication, objective, virtual_library_smiles}`  
Returns: `{campaign_id, created_at}`

### Behaviour
- Campaign ID is auto-generated (`cmp-{8 hex chars}`) but editable.
- SMILES parsing happens client-side using a lightweight regex (`^[A-Za-z0-9@/\\=#()[\]+\-.%*]+$`). Invalid lines shown as a count "3 invalid SMILES skipped" in amber.
- Step 3 model validation progress bar: polls `GET /api/drug-discovery/model-validation/status` every 2s until complete. If validation fails, shows error but allows campaign creation anyway (not a blocker).
- Launch: Creates the campaign, saves virtual library, starts audit trail, starts auto-retrain loop. On success, transitions directly to the Campaign Dashboard (Surface 1) for the new campaign.

---

## Integration Points with Existing Components

### 1. `drug-discovery-action.tsx`

The existing 412-line component has three modes (`assay-upload`, `cro-export`, `dashboard`). Add four new modes:

```typescript
type DrugDiscoveryMode = 
  | 'assay-upload'    // existing
  | 'cro-export'      // existing
  | 'dashboard'       // existing (enhanced per Surface 1)
  | 'validation'      // new — Surface 2
  | 'audit'           // new — Surface 3
  | 'auto-retrain'    // new — Surface 4
  | 'ind-assembly'    // new — Surface 6
  | 'new-campaign'    // new — Surface 7
```

Add a tab bar at the top of the card (when `campaign_id` is set):

```
[Dashboard] [Validation] [Audit] [Auto-Retrain] [IND]
```

For `new-campaign` mode, render the wizard inline without tabs.

### 2. `nextflow-workflow-viewer.tsx`

No changes needed — the drug discovery action card renders in the chat message stream, not in the right panel. It is triggered by a new `workflow_type = 'drug_discovery_cro'` branch in `chat-message.tsx`, similar to the existing `workflow_type = 'disambiguation'` branch.

### 3. Chat AI triggers

When the AI returns a drug discovery campaign response, the message should render the `DrugDiscoveryAction` card with the appropriate initial mode:

| AI intent | Initial mode |
|-----------|-------------|
| "show me my campaign" | `dashboard` |
| "validate the model" | `validation` |
| "show audit trail" | `audit` |
| "auto-retrain status" | `auto-retrain` |
| "generate IND" | `ind-assembly` |
| "new campaign" | `new-campaign` |

The AI backend already returns `campaign_id` in the response payload for drug discovery messages. The frontend reads this to pre-populate all forms.

---

## API Endpoints Required

All new endpoints follow the existing FastAPI pattern in `api_router.py`:

| Method | Path | Surface | Notes |
|--------|------|---------|-------|
| `GET` | `/api/drug-discovery/{id}/compounds` | 1 | Enhanced: add `round_proposed`, `ad_status` |
| `GET` | `/api/drug-discovery/model-validation` | 2 | Existing: add `format=pdf/md` query param |
| `POST` | `/api/drug-discovery/model-validation` | 2 | Trigger re-run |
| `GET` | `/api/drug-discovery/audit` | 3 | New |
| `GET` | `/api/drug-discovery/audit/verify` | 3 | New |
| `GET` | `/api/drug-discovery/audit/export` | 3 | New |
| `GET` | `/api/drug-discovery/{id}/retrain/status` | 4 | New |
| `POST` | `/api/drug-discovery/{id}/retrain/start` | 4 | New |
| `POST` | `/api/drug-discovery/{id}/retrain/stop` | 4 | New |
| `GET` | `/api/drug-discovery/{id}/auto-proposal` | 4 | Existing: add `format=csv` |
| `POST` | `/api/drug-discovery/{id}/virtual-library` | 4, 7 | Existing |
| `GET` | `/api/drug-discovery/{id}/virtual-library` | 4 | New |
| `POST` | `/api/drug-discovery/esig/register` | 5 | New |
| `POST` | `/api/drug-discovery/esig/sign` | 5 | New |
| `POST` | `/api/drug-discovery/{id}/ind-assembly` | 6 | Existing |
| `GET` | `/api/drug-discovery/{id}/ind-assembly/download` | 6 | New |
| `POST` | `/api/drug-discovery/campaigns` | 7 | New |

All endpoints use JWT Bearer auth (same as existing routes). All endpoints listed under "Regulated endpoints" in `api_router.py` (INGEST_ASSAY, EXPORT_CRO_ORDER, IND assembly, PROPOSE_ROUND) append to the audit log automatically via `Depends(_audit_fn)`.

---

## Visual Design Notes

### Status color system (consistent with existing BioMate)

| Status | Color | Usage |
|--------|-------|-------|
| Pass / Valid / In-domain | Green | EMA criterion met, chain valid, fold error ≤ 2× |
| Advisory / Warning / OOD | Amber | Wide CI, OOD compound, pandoc missing |
| Fail / Tampered / Error | Red | EMA criterion failed, chain tampered, invalid TOTP |
| Running / Active | Blue pulsing | Loop running, generation in progress |
| Pending / Stopped | Gray | Loop stopped, waiting for data |

### Regulatory context badges

On any panel that relates to 21 CFR Part 11 or ICH M4, show a small regulatory context chip near the title:

```
Audit Trail  [21 CFR §11.10(e)]  [SHA-256 hash chain]
```

These are `<Badge variant="outline" className="text-xs font-mono">` elements. They serve as persistent on-screen citations so auditors immediately understand the regulatory basis. Same approach as the citations in the existing `auto-loop-panel.tsx`.

### Loading states
- Short operations (< 2s): spinner only, no progress bar
- Medium operations (2–10s): indeterminate progress bar
- Long operations (> 10s): progress bar with percentage if API streams progress, otherwise indeterminate + estimated time

### Empty states
Every table/list has a purposeful empty state with an icon, a clear explanation, and a CTA:

```
Example:
  📋 No proposals yet
  Upload a virtual library and ingest at least one assay result
  to enable the auto-retrain loop.
  [Upload Virtual Library →]
```

---

## Implementation Priority

| Priority | Surface | Reason |
|----------|---------|--------|
| **P0** | Surface 3 — Audit Trail Viewer | Blocks any 21 CFR Part 11 demo; currently invisible |
| **P0** | Surface 4 — Auto-Retrain + Proposals | Core drug discovery loop; backend complete, zero UI |
| **P1** | Surface 2 — PBPK Validation Panel | Required for CRO pitch ("we validated against 31 drugs") |
| **P1** | Surface 6 — IND Assembly | Revenue-generating feature; backend complete |
| **P2** | Surface 1 — Campaign Dashboard (enhanced) | DMTA loop visualization improves comprehension |
| **P2** | Surface 7 — Campaign Creation | Improves onboarding; current flow requires API calls |
| **P3** | Surface 5 — eSig Modal | Only needed in regulated deployment (env var gated) |

---

## File Deliverables

New files to create:

```
frontend/client/src/components/
  drug-discovery-validation-panel.tsx    # Surface 2
  drug-discovery-audit-viewer.tsx        # Surface 3
  drug-discovery-auto-retrain.tsx        # Surface 4
  drug-discovery-esig-modal.tsx          # Surface 5
  drug-discovery-ind-assembly.tsx        # Surface 6
  drug-discovery-campaign-wizard.tsx     # Surface 7
```

Modified files:
```
frontend/client/src/components/
  drug-discovery-action.tsx              # Add tabs + new modes + enhanced dashboard
```

No new routes. No new pages. All surfaces mount inside the existing chat-embedded card or right panel.

---

## E2E Test Plan

Each surface needs at least one Playwright test following the existing pattern (no API mocking, real server responses):

| Test ID | Surface | What to assert |
|---------|---------|----------------|
| DD-CRO-1 | 2 — Validation | EMA criterion badge visible, table shows ≥ 20 drug rows, no "?" in table |
| DD-CRO-2 | 3 — Audit | At least 1 record after assay ingest, chain shows VALID, export downloads a file |
| DD-CRO-3 | 4 — Auto-Retrain | Loop starts, status shows RUNNING, proposal table renders after trigger |
| DD-CRO-4 | 4 — Proposals | Copy SMILES button copies text to clipboard, Download CSV returns non-empty file |
| DD-CRO-5 | 6 — IND Assembly | Generate button active after filling fields, Markdown file downloads |
| DD-CRO-6 | 7 — Campaign Wizard | 3-step flow completes, campaign_id appears in dashboard after launch |
| DD-CRO-7 | 5 — eSig (if env var set) | Wrong code shows error, correct code shows success and action proceeds |
