# BioMate UI scenario — ANDV pocket druggability (what users see)

This is the **chat-first** path: no raw Nextflow scripts and no direct `POST /api/nextflow/execute` from scripts. Execution still lands on **AWS Batch** with **ECR** images when your deployed BioMate stack has `NEXTFLOW_USE_AWS=true` — that is decided **server-side**, not by the Playwright test.

---

## Persona

Medicinal chemist / program lead on the **ANDV oral inhibitor** track, using Guo et al. Cryo-EM structures for tractability.

## Goal

Get **binding-pocket detection + druggability QC** from BioMate so the team can prioritize sites before docking campaigns.

## Designed user query (natural language)

Use this (or close variants) in the BioMate chat:

```text
I'm on the ANDV glycoprotein oral inhibitor program (Guo et al. Cryo-EM structures).
I need pocket detection and druggability assessment for tractability before we order compounds.

Please run the Pocket Detection Druggability workflow with:
- pdb_input = 1IEP
- min_druggability = 0.35
- min_volume = 200

1IEP is a reliable RCSB PDB for end-to-end UI validation. For our actual ANDV GP builds we use 9P3I — note RCSB often has mmCIF only for new entries, so we upload a converted PDB when needed.

All parameters are explicit — show me the workflow card so I can Run it.
```

**Why `1IEP` in the template:** RCSB serves `1IEP.pdb` over HTTPS; **9P3I** is often **mmCIF-only** (`*.pdb` 404), which breaks head-node staging unless you **upload** `9P3I.pdb` via datasets/chat. Swap `pdb_input` to **9P3I** only after upload or when your deployment resolves accessions to mmCIF.

---

## Expected UI sequence (monitoring checklist)

What users should see — matches `data-testid` hooks in `frontend/client/src/components/nextflow-workflow-viewer.tsx` and chat helpers in `frontend/e2e/helpers.ts`:

| Step | User-visible signal | Selector / hint |
|------|---------------------|-----------------|
| 1 | Thinking / analysis state | `[data-testid='chat-response-pending']`, “Analyzing request”, etc. |
| 2 | Assistant reply + workflow artifact | Workflow panel opens, `[data-testid="workflow-artifact-panel"]` |
| 3 | Ready to execute | `[data-testid="button-run-workflow-panel"]` |
| 4 | Run acknowledged | Network: `POST` to `/api/workflows/execute` and/or `/api/nextflow/execute` |
| 5 | Live run state | `[data-testid="workflow-overall-status-badge"]` → **RUNNING** |
| 6 | Progress bar | `.run-bar` / percentage in panel |
| 7 | Terminal success | Badge **COMPLETED**, `[data-testid="workflow-completion-banner"]` |
| 8 | Outputs | Step outputs list; `[data-testid="button-download-all-workflow-panel"]` when enabled |

---

## Automated UI test (Playwright)

Implementation: `frontend/e2e/andv-pocket-druggability-ui.e2e.ts`

Run against your **deployed** BioMate (not localhost unless that is your stack):

```bash
cd frontend
BIOMATE_URL=https://your-biomate.example.com \
E2E_TEST_TOKEN=<matches server> \
npx playwright test e2e/andv-pocket-druggability-ui.e2e.ts --project chromium
```

HTML report: `npm run e2e:report` (see `frontend/playwright.config.ts`).

Screenshots for this scenario: `frontend/e2e/screenshots/andv-pocket-ui/`.
