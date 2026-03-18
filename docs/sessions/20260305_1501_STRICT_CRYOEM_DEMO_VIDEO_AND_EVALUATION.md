# 2026-03-05 15:01 Strict Cryo-EM Demo Video and Evaluation

## Scope

- Replaced loose demo recording behavior with strict, evidence-oriented recording flow.
- Re-recorded Cryo-EM demo with deterministic selectors and terminal-status gating.

## Recorder hardening

Updated:
- `frontend/record_demo.mjs`

Improvements:
- Uses strict selectors:
  - chat input: `data-testid="chat-input"`
  - send button: `data-testid="chat-send-button"`
  - run button: `data-testid="button-run-workflow-panel"` (with controlled fallbacks)
- Waits for assistant completion window (`AI is typing` hidden) before proceeding.
- Handles blocked run state with explicit recovery prompt.
- Captures `/api/workflows/execute` response payload (run identifiers).
- Polls `/api/workflows/runs/:id/status` until terminal status (`completed|failed|cancelled`).
- Stores proof artifact:
  - `proof_summary.json` containing run IDs, execute response, final run status, and nextflow details.

## New strict demo artifact

Video:
- `/home/yzhang/biomate/demo_videos/biomate_demo_1772744291627.webm`

Evidence folder:
- `/home/yzhang/biomate/demo_videos/screenshots_1772744291627`
- Includes:
  - `03_workflow_presented.png`
  - `05_terminal_state.png`
  - `06_final_state.png`
  - `proof_summary.json`
  - `page_content.html`

## Evaluation outcome

### What is confirmed working

- End-to-end run execution completed successfully in this strict recording:
  - App run status: `completed`
  - Nextflow status: `succeeded`
  - Return code: `0`
- Output contract surfaced in status payload:
  - `hasOutputs: true`
  - `visualizableCount: 1`
  - `downloadableCount: 1`
  - `meetsContract: true`
- UI final state shows:
  - execution state completed
  - logs visible
  - output results section visible
  - download action visible

### Remaining scientific correctness gap

- Despite Cryo-EM prompt, recovered runnable workflow path resolved to:
  - `.../subworkflows/genomics/get_rna_seq_archs4/main.nf`
- This indicates technical execution is working, but domain path selection can still drift to a non-Cryo workflow under prerequisite-recovery mode.

## Conclusion

- **Technical workflow pipeline execution is real and functioning.**
- **Scientific/domain alignment for Cryo-EM remains a known gap in this demonstrated path.**
