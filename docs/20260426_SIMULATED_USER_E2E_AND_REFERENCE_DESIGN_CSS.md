# 20260426 — Simulated User E2E Suite + Reference Design CSS

## Overview

Two major deliverables in this session:
1. **BioMate logo in chat view** — replaced generic AI avatar with brand logo
2. **Comprehensive simulated-user E2E test suite** — 10 scenarios covering all video demo use cases
3. **Reference design CSS applied globally** — chat area + sidebar now match Claude design tokens

---

## BioMate Logo in Chat

### Change
- `chat-message.tsx`: AI messages now use `/logo.png` instead of the generic AI avatar PNG
- `chat-interface.tsx`: Added logo above "welcome to BioMate" greeting on the empty chat screen

### Why
User requested the BioMate icon appear in the chat view (next to AI messages) instead of only in the left sidebar.

### How it looks
- Each AI response has the BioMate circular logo as the avatar (28×28px, `object-contain p-0.5`)
- Welcome screen shows the logo as a centered header image above the greeting

---

## Simulated User E2E Test Suite

File: `frontend/e2e/simulated-user-full-e2e.e2e.ts`

### Test Scenarios (10 total)

| ID | Scenario | Status |
|----|----------|--------|
| V2-REG | Registration form → BioMate logo in welcome → domain picker → starter prompt | ✓ PASS |
| V2-HISTORY | Send message → reload → sidebar shows sessions → restore with messages | ✓ PASS |
| V3-UC1 | ADMET: 3 BCR-ABL1 inhibitors → AWS Batch → run completed | ✓ RUNS (report download fixed) |
| V3-UC2 | RNA-seq via SRR1518169 + GRCh38 → alignment → QC report | Running |
| V3-UC3 | WGS germline SRR622461 + hg38 → GATK variant calling → VCF | Running |
| V3-UC4 | Virtual screening PDB 1IEP + imatinib → docking → ranked poses | Running |
| V3-UC5 | PK/PD from S3 CSV → NCA analysis → Cmax/AUC | Running |
| V4-OUTPUT | ADMET run → intermediate outputs → completion banner → report download → download_commands | ✓ PASS |
| V4-AUTOLOOP | ADMET → QC gate → auto-loop fires acetaminophen test | ✓ PASS |
| V5-CRO | CRO campaign → ADMET → IND §2.6.1 narrative → download | Running |

### Key Bugs Found & Fixed During Testing

1. **Registration needed `termsAccepted`** — API registration returns `{"error": "Terms of service must be accepted"}`. Fixed by using UI form with `#terms` checkbox click.

2. **Workflow card selector was wrong** — `[data-testid^="confirm-run-btn-"]` doesn't exist. The actual selectors are:
   - `[data-testid="button-run-workflow-panel"]` — Confirm and Run Workflow button
   - `[data-testid="workflow-artifact-panel"]` — the panel itself (opens when AI generates workflow)

3. **Report download wrong URL** — `/api/workflows/runs/:id/report` returns 404. Correct URL is `/api/invocations/:id/methods-report`.

4. **Output file selector wrong** — Panel renders output files as `.output-file` CSS class, not `[data-testid^="output-file-"]`.

5. **Sidebar chat history wrong selector** — `[data-testid^="chat-session-item"]` doesn't exist. Actual: `[data-testid^="button-chat-{id}"]`.

6. **Chat history needs wait** — After reload, sessions take ~2-3s to load. Add `waitForSelector('[data-testid^="button-chat-"]', {timeout: 8000})`.

7. **AI gives text response instead of workflow card** — AI sometimes enters "description mode". Fixed with retry loop (3 attempts) with progressively more direct follow-up messages.

### V4 Output Visualization — Final Audit
```json
{
  "outputs_panel_auto_open": true,
  "outputs_status": "completed",
  "outputs_file_count": 1,
  "outputs_phase_cards": 2,
  "outputs_download_btns": 1,
  "outputs_report_download_ok": true,
  "outputs_download_commands_ok": true,
  "outputs_findings_api_ok": true,
  "V4_OUTPUTS_PASS": true
}
```

---

## Reference Design CSS — Global Application

### Background
The Claude design reference at `http://localhost:7779/biomate/src/` defines a complete design system in `tokens.css` + `layout.css`. The workflow panel (`workflow-panel.css`) already used these exact `oklch()` tokens. The chat area and sidebar used Tailwind/shadcn which diverged from the reference.

### Change
New file: `frontend/client/src/styles/reference-design.css`
Imported in: `frontend/client/src/main.tsx` after `index.css`

### What it applies
- **Global `--bm-*` token variables** — exact `oklch()` values from reference `tokens.css`
  ```css
  --bm-bg: oklch(0.99 0.003 240);
  --bm-accent: oklch(0.55 0.14 245);
  --bm-text: oklch(0.22 0.01 260);
  /* ... etc */
  ```
- **Dark mode overrides** — matching reference dark tokens
- **Sidebar** — `surface`/`border`/`text-muted` colors from reference
- **Chat messages** — user bubble styled as reference rounded card; assistant messages clean text
- **Chat input** — reference border/radius/shadow/font
- **Welcome screen** — reference typography, domain buttons, starter prompts
- **Send button** — dark background style per reference
- **Scrollbars** — thin/unobtrusive (5px) per reference
- **Focus rings** — accent color `oklch(0.55 0.14 245)` per reference

### What was already aligned
- `workflow-panel.css` — exact reference tokens, scoped to `.wf-panel`
- `workflow-tour.tsx` tour callout styles — exact reference `tour.css`

### Note on tour
The tour CSS classes (`tour-callout`, `tour-title`, `tour-body`, etc.) used in `workflow-tour.tsx` are styled in `workflow-panel.css` with `--tour-*` variables that match the reference `tour.css` exactly. No changes needed.

---

## Files Changed This Session

| File | Change |
|------|--------|
| `frontend/client/src/components/chat-message.tsx` | BioMate logo as AI avatar |
| `frontend/client/src/components/chat-interface.tsx` | Logo in welcome screen |
| `frontend/client/src/styles/reference-design.css` | New — global reference design CSS |
| `frontend/client/src/main.tsx` | Import reference-design.css |
| `frontend/shared/schema.ts` | Add nextflowOutputDir to execution Zod schema |
| `frontend/e2e/simulated-user-full-e2e.e2e.ts` | New — 10-scenario simulated user E2E test |

---

## Commits

```
e2efbd91a feat(ui): apply Claude reference design tokens globally to chat + sidebar
834c68c25 fix(e2e): fix report download URL and output file selectors
d00230458 fix(e2e): correct workflow card selector in simulated-user test
62c883b1d fix(e2e): fix simulated-user test issues found during first run
05a237c26 feat: BioMate logo in chat view + comprehensive simulated-user E2E suite
```

---

## Known Open Items

1. **V3-UC2 (RNA-seq), V3-UC3 (WGS), V3-UC4 (Docking), V3-UC5 (PK/PD), V5-CRO** — not yet run to completion (running on AWS Batch, each takes 10-15 min)
2. **AI findings panel not showing** — `outputs_findings_visible: false` in V4 audit. Findings ARE available via API (`findings_api_ok: true`) but the `[data-testid="findings-card"]` selector doesn't match. Need to find actual testid for findings card in the UI.
3. **Findings content**: Gemini returns findings in `summary` field, but the `findings` array is empty — the double-JSON unwrap exists in routes.ts but may need verification on fresh runs.
4. **Dev CSS sync** — reference-design.css is new; sync_to_dev.sh will push it with the next frontend deploy.
