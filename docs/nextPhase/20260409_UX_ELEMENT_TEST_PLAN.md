# BioMate — UX Element Test Plan
**Date:** 2026-04-09  
**Author:** Claude Code (session 2026-04-09)  
**Status:** PLAN — coverage gaps identified; new tests to be authored

---

## Purpose

Map every interactive UX element in the BioMate frontend to its test coverage status. For each element: (1) the existing test file covering it, (2) the data-testid used, and (3) the gap/action needed.

Coverage target: **every user-facing control must have at least one E2E assertion.**

---

## 1. Chat Interface

| Element | data-testid / selector | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Chat text input | `#chat-input`, `.chat-input` | `full-workflow-e2e.e2e.ts` | — | ✅ covered |
| Send button | `button[type=submit]`, Enter key | `full-workflow-e2e.e2e.ts` | — | ✅ covered |
| File upload button | `file-upload-*` | `real-data-upload-through-chat.e2e.ts` | Upload progress UI | Add progress indicator test |
| AI response streaming | Detecting partial text | `trace-chat-flow.e2e.ts` | No assertion for mid-stream state | Add mid-stream indicator test |
| Thinking/reasoning display | `[data-testid="thinking-display"]` | None | **MISSING** | **UX-1** |
| Typing indicator | `.typing-indicator` | None | **MISSING** | **UX-2** |
| Message history scroll | Scroll to bottom on new message | None | **MISSING** | **UX-3** |
| Survey dialog dismiss | `survey-skip-btn`, `survey-submit-btn` | `germline-complete-e2e.e2e.ts` | — | ✅ covered |
| Session list / new chat | sidebar session items | `run-manager-multi-chat-scope.e2e.ts` | — | ✅ covered |

---

## 2. Workflow Viewer (`nextflow-workflow-viewer.tsx`)

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| **Run controls** | | | | |
| Confirm & Run button | `button-run-workflow-panel` | `workflow-controls-comprehensive.e2e.ts` (WC-1) | — | ✅ covered |
| Cancel button | `button-cancel-run-panel` | `workflow-controls-comprehensive.e2e.ts` (WC-2) | — | ✅ covered |
| Rerun (full) button | `button-restart-workflow-panel` | `workflow-controls-comprehensive.e2e.ts` (WC-3) | — | ✅ covered |
| Download Commands panel | `download-commands-panel` | `workflow-controls-comprehensive.e2e.ts` (WC-5) | — | ✅ covered |
| **Parameter editor** | | | | |
| String input field | `[id="<param>"]` | `workflow-controls-comprehensive.e2e.ts` (WC-7) | — | ✅ covered |
| Number input field | `[id="max_spots"]` | `workflow-controls-comprehensive.e2e.ts` (WC-7) | — | ✅ covered |
| Boolean toggle | `[data-testid="param-bool-*"]` | None | **MISSING** | **UX-4** |
| Select dropdown | `[data-testid="param-select-*"]` | None | **MISSING** | **UX-5** |
| File param field | `[data-testid="param-file-*"]` | None | **MISSING** | **UX-6** |
| AI pre-fill badge | `[data-testid="param-autofill-badge-*"]` | None | **MISSING** | **UX-7** |
| Override button | `[data-testid="param-override-btn-*"]` | None | **MISSING** | **UX-7** |
| **Phase cards** | | | | |
| Expand/collapse | `phase-card-expand-*` | `workflow-controls-comprehensive.e2e.ts` (WC-4) | — | ✅ covered |
| Status badge colors | `phase-card-status-*` | `workflow-controls-comprehensive.e2e.ts` (WC-4) | — | ✅ covered |
| Run Step button | `phase-card-run-step-*` | `workflow-controls-comprehensive.e2e.ts` (WC-4) | — | ✅ covered |
| Preview button | `phase-card-preview-btn-*` | `workflow-controls-comprehensive.e2e.ts` (WC-6) | Hard-assert iframe | WC-6 updated |
| **Output viewers** | | | | |
| HTML iframe | `iframe[sandbox]` | `workflow-controls-comprehensive.e2e.ts` (WC-6) | Real Batch HTML run | WC-6 updated |
| CSV/JSON table | `csv-table-viewer` | `workflow-controls-comprehensive.e2e.ts` (WC-5) | — | ✅ covered |
| Image viewer | `img[src*="step-file"]` | None | **MISSING** | **UX-8** |
| Sequence viewer | `[data-testid="seq-viewer"]` | `bioinformatics-viewers.e2e.ts` | — | ✅ covered |
| VCF viewer | `[data-testid="vcf-viewer"]` | `bioinformatics-viewers.e2e.ts` | — | ✅ covered |
| BAM viewer | n/a | None | **NOT YET BUILT** | **P2: future** |
| Annotation viewer | `[data-testid="annotation-viewer"]` | `bioinformatics-viewers.e2e.ts` | — | ✅ covered |
| **Metrics strip** | | | | |
| Duration display | `run-metric-duration-value` | `workflow-controls-comprehensive.e2e.ts` (WC-8) | — | ✅ covered |
| Started-at display | `run-metric-started-at` | `workflow-controls-comprehensive.e2e.ts` (WC-8) | — | ✅ covered |
| Completed-at display | `run-metric-completed-at` | `workflow-controls-comprehensive.e2e.ts` (WC-8) | — | ✅ covered |
| Per-step LLM costs | `run-metric-per-step-costs` | `workflow-controls-comprehensive.e2e.ts` (WC-9/10) | — | ✅ added |
| Execution triage | `execution-triage-summary` | `ux-execution-triage.e2e.ts` (UX-9a/b/c) | — | ✅ covered (2026-04-09) |
| **Prereq checklist** | | | | |
| Checklist visible | `prereq-checklist-*` | `ux-prereq-checklist.e2e.ts` | — | ✅ covered |
| Blocked run indicator | `prereq-blocked-*` | `ux-prereq-checklist.e2e.ts` | — | ✅ covered |
| "Continue in chat" button | `prereq-chat-link-*` | None | **MISSING** | **UX-10** |
| **Compare runs** | | | | |
| Parameter differences | compare endpoint | `workflow-controls-comprehensive.e2e.ts` (WC-7) | — | ✅ covered |
| **AI analyze error badge** | | | | |
| AI-analyzed badge | `ai-analyzed-badge` | None | **MISSING** | **UX-11** |

---

## 3. Run Manager Panel

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Run list items | `run-list-item-*` | `ux-run-manager-panel.e2e.ts` | — | ✅ covered |
| Status badge colors | `run-status-badge-*` | `ux-run-manager-panel.e2e.ts` | — | ✅ covered |
| Active run anchoring | focused run highlight | `run-manager-switch-anchoring.e2e.ts` | — | ✅ covered |
| Run list pagination | limit/offset params | `run-manager-limit-offset-stress.e2e.ts` | — | ✅ covered |
| Multi-chat run scope | per-session isolation | `run-manager-multi-chat-scope.e2e.ts` | — | ✅ covered |
| All Chats view | `run-manager-all-chats` | `run-manager-all-chats-mixed-load.e2e.ts` | — | ✅ covered |
| Sort stability | sort by status/date | `run-manager-refresh-sort-stability.e2e.ts` | — | ✅ covered |
| Large set (visibility cap) | `run-list-cap-indicator` | `run-manager-large-set-visibility-cap.e2e.ts` | — | ✅ covered |

---

## 4. Auth Flows

| Element | data-testid / selector | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Register form | `#name, #email, #password` | `auth-flows-smoke.e2e.ts` | — | ✅ covered |
| Login form | `#email, #password` | `auth-flows-smoke.e2e.ts` | — | ✅ covered |
| Logout | logout button | `auth-flows-smoke.e2e.ts` | — | ✅ covered |
| Pilot account bypass | no billing on pilot email | `germline-complete-e2e.e2e.ts` | — | ✅ covered |
| Terms checkbox | `#terms` | `auth-flows-smoke.e2e.ts` | — | ✅ covered |

---

## 5. License & Credential Gate

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| License gate modal | `license-gate-modal` | `license-gate-audit.e2e.ts` | — | ✅ covered |
| Credential modal | `credential-modal` | `license-gate-audit.e2e.ts` | — | ✅ covered |
| Run blocked by license | `run-blocked-license` | `license-gate-audit.e2e.ts` | — | ✅ covered |
| "Provide credentials" action | credential input flow | `license-gate-audit.e2e.ts` | — | ✅ covered |

---

## 6. QC Gate

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| QC modal | `qc-gate-modal` | `qc-gate-inline.e2e.ts` | — | ✅ covered |
| QC threshold display | `qc-threshold-*` | `qc-governance.e2e.ts` | — | ✅ covered |
| Override QC | `qc-override-btn` | `qc-gate-inline.e2e.ts` | — | ✅ covered |

---

## 7. File Upload & Dataset Browser

| Element | data-testid / selector | Existing coverage | Gap | Action |
|---|---|---|---|---|
| File drag & drop | `.file-drop-zone` | `real-data-upload-through-chat.e2e.ts` | — | ✅ covered |
| Upload progress bar | `upload-progress-*` | None | **MISSING** | **UX-12** |
| Dataset browser | `galaxy-dataset-browser` | None | **MISSING** | **UX-13** |
| Dataset session list | `GET /api/datasets/session` | None | **MISSING** | **UX-13** |

---

## 8. Settings & Theme

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Settings dialog open | `settings-dialog` | None | **MISSING** | **UX-14** |
| Theme toggle (dark/light) | `theme-toggle` | None | **MISSING** | **UX-15** |
| API key setting | `api-key-input` | None | **MISSING** | **UX-14** |

---

## 9. Navigation & Layout

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Sidebar open/close | `app-sidebar` | `ux-run-manager-panel.e2e.ts` | — | ✅ partial |
| Create new chat | `new-chat-btn` | `run-manager-multi-chat-scope.e2e.ts` | — | ✅ covered |
| Workflow artifact panel | `workflow-artifact-panel` | `full-workflow-e2e.e2e.ts` | — | ✅ covered |
| Landing page hero | `hero-section` | `landing-page-responsiveness.e2e.ts` | — | ✅ covered |
| Responsive layout mobile | viewport 375px | `landing-page-responsiveness.e2e.ts` | — | ✅ covered |

---

## 10. Billing / Checkout

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Checkout flow | stripe checkout | `checkout-flow-smoke.e2e.ts` | — | ✅ covered (smoke) |
| LLM cost display | `llm-cost-display` | `drug-discovery-pilot-e2e.e2e.ts` | — | ✅ covered |

---

## 11. Error & Recovery States

| Element | data-testid | Existing coverage | Gap | Action |
|---|---|---|---|---|
| Network offline banner | `offline-banner` | `ux-offline-recovery.e2e.ts` | — | ✅ covered |
| API error toast | `[data-testid="toast"]` | Multiple files | — | ✅ covered |
| Autofix state display | `autofix-state-*` | `ux-autofix-gate.e2e.ts` | — | ✅ covered |
| Run failed error message | `error-message-panel` | `workflow-controls-comprehensive.e2e.ts` | — | ✅ covered |
| AI error analysis badge | `ai-analyzed-badge` | None | **MISSING** | **UX-11** |

---

## Priority Gap Tests to Implement

Each gap entry follows a consistent structure:
- **User story** — the real researcher scenario the test guards
- **Success looks like** — what the user observes when the feature works correctly
- **Failure risk** — what regression goes undetected if this test is absent
- **Assertions** — the concrete Playwright checks

---

### UX-1: Thinking Display

**User story:** As a researcher, I need to see the AI's reasoning steps while it formulates a response, so that I can follow along and trust the answer it produces.

**Success looks like:** While the AI is generating, a collapsible "Thinking" panel appears with progressive reasoning text. Once the response is complete the panel collapses automatically and only the final answer is visible.

**Failure risk:** Without this test, a regression that silently stops rendering the thinking panel goes undetected. Researchers lose visibility into AI reasoning quality, eroding trust in responses.

**Target:** `thinking-display.tsx` — renders AI reasoning steps during response  
**Test file:** `frontend/e2e/ux-thinking-display.e2e.ts` (new)  
**Assertions:**
- Send a complex bioinformatics query that triggers reasoning
- Assert `[data-testid="thinking-display"]` becomes visible during AI response
- Assert it collapses/hides once response is complete
- Screenshot at both states

---

### UX-2: Typing Indicator

**User story:** As a researcher, I need immediate visual feedback that BioMate received my message and is working on a response, so that I don't wonder if my message was lost.

**Success looks like:** Within 1–2 seconds of hitting Send, a typing indicator (three-dot animation or "BioMate is typing" text) appears. It disappears once the first token of the AI response streams in.

**Failure risk:** Without this test, a regression that removes the typing indicator leaves the UI appearing frozen after a user submits a query. Researchers may re-submit or assume the system is broken.

**Target:** `typing-indicator.tsx` — 3-dot animation while AI generates  
**Test file:** `frontend/e2e/ux-thinking-display.e2e.ts` (combined with UX-1)  
**Assertions:**
- Assert typing indicator appears immediately after sendMessage
- Assert it disappears before first message token arrives

---

### UX-3: Chat Scroll-to-Bottom

**User story:** As a researcher conducting a multi-turn conversation, I need the chat to automatically scroll to the latest message, so that I never have to manually scroll down after each AI response.

**Success looks like:** After each new message (user or AI), the viewport snaps to the bottom of the message list. Long conversations do not require manual scrolling.

**Failure risk:** Without this test, a regression that breaks auto-scroll means researchers in long sessions miss AI responses unless they notice the scroll has stalled — a silent UX failure that degrades the conversation flow.

**Target:** chat message list auto-scroll  
**Test file:** `frontend/e2e/ux-chat-scroll.e2e.ts` (new)  
**Assertions:**
- Send 20+ messages to fill scroll area
- Assert last message is within viewport
- Send new message, assert still scrolled to bottom

---

### UX-4: Boolean Toggle Parameter

**User story:** As a researcher configuring a workflow, I need boolean parameters (e.g. "save trimmed reads: yes/no") to render as a real toggle or checkbox, so that I cannot accidentally type an invalid value like "treu".

**Success looks like:** The parameter editor renders a visible toggle or checkbox for boolean fields. Clicking it flips the value between true and false. The correct value is passed to the workflow execution API.

**Failure risk:** Without this test, a regression that silently converts a boolean toggle into a free-text field goes undetected. Researchers can type invalid values, causing workflow failures that are hard to diagnose.

**Target:** Viewer parameter editor, boolean field type  
**Test file:** `frontend/e2e/workflow-controls-comprehensive.e2e.ts` (extend WC-4 or add WC-11)  
**Assertions:**
- Find a workflow with a boolean param (e.g. `save_trimmed = true`)
- Assert toggle is visible (`[type="checkbox"]` or switch)
- Click toggle, assert value flips in params
- Run with both values, verify param is passed correctly

---

### UX-5: Select Dropdown Parameter

**User story:** As a researcher, I need enum parameters (e.g. genome assembly: GRCh38/GRCm38) to render as a dropdown with only valid options, so that I cannot accidentally supply an unsupported genome string that would silently fail mid-run.

**Success looks like:** The parameter editor shows a `<select>` element with the correct enumerated choices. Changing the selection updates the parameter value. The chosen option is sent in the execution request.

**Failure risk:** Without this test, a regression that renders enum params as free-text inputs allows researchers to enter typo values. The workflow accepts the request but fails at runtime with an opaque error, wasting compute time.

**Target:** Viewer parameter editor, select field type  
**Test file:** `frontend/e2e/workflow-controls-comprehensive.e2e.ts` (extend)  
**Assertions:**
- Find workflow with enum param (e.g. `genome` = GRCh38/GRCm38)
- Assert select element is present with correct options
- Change selection, verify param updated

---

### UX-6: File Parameter Field

**User story:** As a researcher, I need file-type parameters to block the Run button when no file has been provided, so that I get immediate guidance to upload a file rather than submitting an incomplete run that fails 10 minutes later.

**Success looks like:** The parameter editor renders a file picker or path input for file-type params. If a required file param is empty, the Confirm & Run button is disabled with a visible indication that a file is needed.

**Failure risk:** Without this test, a regression that removes the file-param validation blocker allows researchers to start runs without required inputs. Runs fail early with cryptic file-not-found errors instead of a clear pre-run validation message.

**Target:** Viewer parameter editor, file-type field  
**Test file:** `frontend/e2e/ux-param-file-field.e2e.ts` (new)  
**Assertions:**
- Workflow with `input_file` param
- Assert file picker or path input renders
- Assert run is blocked when required file param is empty

---

### UX-7: AI Pre-fill Badge + Override

**User story:** As a researcher, I need the AI to pre-fill workflow parameters it can infer from my query (e.g. SRA accession, genome version), and I need to be able to override any auto-filled value, so that I can accept the AI's sensible defaults quickly but correct mistakes without hunting through the parameter list.

**Success looks like:** After the AI matches a workflow and pre-fills params, each auto-filled field shows a badge (e.g. "AI: SRR1518169") with a tooltip rationale. Clicking "Override" on a badge makes the field freely editable and removes the badge. The overridden value is the one sent to the API.

**Failure risk:** Without this test, a regression that silently stops displaying autofill badges means researchers do not know which params the AI touched — they must review all parameters manually, slowing down every run submission.

**Target:** `parameter-recommendation-badge.tsx`, override button  
**Test file:** `frontend/e2e/ux-param-autofill.e2e.ts` (new)  
**Assertions:**
- Send message that triggers AI param pre-filling
- Assert `[data-testid^="param-autofill-badge-"]` visible
- Assert rationale tooltip visible on hover
- Click override, assert badge disappears, field becomes editable
- Verify override value is sent in execution params

---

### UX-8: Image Viewer in StepOutputPreview

**User story:** As a researcher who ran a GROMACS MD simulation, I need to preview the RMSD/RMSF PNG plots directly in the viewer without downloading them, so that I can quickly validate whether the simulation converged before spending time on further analysis.

**Success looks like:** After a workflow produces PNG output files, clicking the Preview button on a step shows an `<img>` element with non-zero dimensions rendered inside the step output panel.

**Failure risk:** Without this test, a regression that breaks image rendering in the preview panel means researchers see a blank area where plots should appear. They assume the workflow failed to produce outputs and rerun needlessly.

**Target:** `step-output-preview.tsx` image case (`img` element)  
**Test file:** Extend `workflow-controls-comprehensive.e2e.ts` (WC-6 or new WC-11)  
**Assertions:**
- Need a workflow that outputs PNG (e.g. GROMACS RMSD plot)
- Assert `img[src*="step-file"]` visible after clicking preview button
- Assert image has non-zero dimensions

---

### UX-9: Execution Triage Panel — Three-Part Coverage

The Execution Triage panel is the single most important post-run UX element: it converts raw workflow status into a one-glance action item. Three tests cover its full lifecycle.

**Test file:** `frontend/e2e/ux-execution-triage.e2e.ts` (new — implemented 2026-04-09)

#### UX-9a: All four triage fields populated at terminal state

**User story:** As a researcher whose germline workflow just finished, I need the triage panel to immediately tell me: what the status is, what I should do next, where the logs are, and where my outputs are — all without reading raw log lines.

**Success looks like:** After a run reaches terminal state (completed or failed), the triage panel shows four non-empty sub-fields: `execution-triage-status`, `execution-triage-next-action`, `execution-triage-logs`, `execution-triage-outputs`. Each contains a human-readable sentence. No field is blank.

**Failure risk:** Without this test, a regression that wipes any sub-field text goes undetected. Researchers see a blank triage area and do not know whether to download results, check logs, or rerun — forcing them to inspect raw API responses manually.

**Assertions:**
- Send germline workflow query with max_spots=50, confirm and run, poll to terminal (up to 90 s)
- Assert `[data-testid="execution-triage-summary"]` is visible
- Assert `execution-triage-status` has non-empty text
- Assert `execution-triage-next-action` has more than 10 characters
- Assert `execution-triage-logs` has non-empty text
- Assert `execution-triage-outputs` has non-empty text
- Log all four triage text values for audit
- Screenshot showing triage panel

#### UX-9b: Triage panel visible while run is in progress

**User story:** As a researcher who just submitted a long-running genomics job, I need the triage panel to tell me "Running — monitor logs and wait for terminal status" immediately after the job starts, so that I know the system is working and what to do while I wait.

**Success looks like:** Within 15 seconds of receiving the `runId`, `[data-testid="execution-triage-summary"]` is visible and `execution-triage-next-action` is non-empty. After the run reaches terminal, the panel is still visible and the status text reflects the final outcome.

**Failure risk:** Without this test, a regression that hides the triage panel until terminal state means researchers get zero guidance during potentially long-running jobs. They either over-poll the status endpoint or abandon the session assuming the job is stuck.

**Assertions:**
- Start a germline run
- Assert triage summary visible within 15 s of run start (not just at terminal)
- Assert status and next-action text are non-empty at "running" state
- Screenshot at running state
- Poll to terminal (up to 90 s)
- Assert triage panel still visible at terminal
- Log both running-state and terminal-state field values for comparison

#### UX-9c: Next-action text differs by outcome

**User story:** As a researcher, I need the triage panel's "Next action" guidance to match my actual situation — if my run completed I should be told to download results, if it failed I should be told to fix the error and rerun. Getting the wrong guidance for my situation wastes my time on the wrong recovery path.

**Success looks like:** Completed runs produce next-action text containing terms like "download", "results", "outputs", "verify", or "open". Failed runs produce next-action text containing terms like "error", "fail", "retry", "rerun", "check", or "inspect". The two outcomes never produce the same next-action sentence. The idle/configure guidance ("Configure parameters and prerequisites") never appears after a run has started.

**Failure risk:** Without this test, a regression that hard-codes a single generic next-action message for all statuses goes undetected. A researcher whose run completed successfully might see "check the error and rerun" — triggering unnecessary diagnostic work. Conversely, a researcher whose run failed might see "open output results" — causing them to look for artifacts that do not exist.

**Assertions:**
- Run germline workflow to terminal
- If completed: assert next-action references results/download; assert it does not mention failure/retry
- If failed: assert next-action references error/rerun/check; assert it does not say to open outputs
- If timeout (status unknown): assert next-action is at least non-empty (>10 chars)
- Hard-assert: next-action does NOT contain the idle default text ("Configure parameters and prerequisites")
- Screenshot of the outcome-specific triage panel

---

### UX-10: "Continue in Chat" Button in Prereq Checklist

**User story:** As a researcher whose workflow is blocked because a prerequisite requires clarification (e.g. "which genome version should I use?"), I need a "Continue in chat" button that pre-fills the chat input with the exact question I need to answer, so that I can resolve the blocker in one click rather than re-reading the prereq description and composing a message myself.

**Success looks like:** When a confidence-gate prereq item is visible, a "Continue in chat →" button appears alongside it. Clicking it puts the prereq's `chatPrompt` text into the chat input and focuses the input. Sending that message resolves the prereq and enables the Run button.

**Failure risk:** Without this test, a regression that removes the `chatPrompt` field from prereq items silently breaks the "Continue in chat" button path. Researchers who need to resolve a prereq see a button that does nothing, and have to manually figure out what to type — a high friction point that causes run abandonment.

**Target:** `chatPrompt` field on PrereqItem → "Continue in chat →" button  
**Test file:** Extend `ux-prereq-checklist.e2e.ts`  
**Assertions:**
- Trigger a workflow with a confidence-gate prereq item
- Assert `[data-testid^="prereq-chat-link-"]` visible
- Click it, assert chat input is pre-filled with `chatPrompt` text
- Assert chat session is in focus

---

### UX-11: AI Analyze Error Badge

**User story:** As a researcher whose workflow failed, I need the viewer to automatically analyze the error and show me a plain-English explanation (e.g. "The FASTQ file was not found at the specified S3 path"), so that I do not have to parse raw Nextflow stack traces to understand what went wrong.

**Success looks like:** Within a few seconds of a workflow failing, an "AI-analyzed" or "pattern-matched" badge appears on the error panel. The badge text is a non-empty, human-readable explanation of the failure cause.

**Failure risk:** Without this test, a regression that silently stops the AI error analysis from running means researchers see raw stack traces with no interpretation. Diagnosing failures requires Nextflow expertise, locking out domain scientists who are not workflow engineers.

**Target:** `ai-analyzed-badge` — shown after workflow failure  
**Test file:** `frontend/e2e/ux-error-analysis.e2e.ts` (new)  
**Assertions:**
- Trigger a workflow failure (e.g. invalid SRA accession)
- Assert `[data-testid="ai-analyzed-badge"]` visible after failure
- OR `[data-testid="pattern-matched-badge"]` if API key not set
- Assert error explanation text is non-empty

---

### UX-12: Upload Progress Indicator

**User story:** As a researcher uploading a large FASTQ file, I need a progress bar so I know how much longer the upload will take and can confirm the system is not frozen.

**Success looks like:** While a large file is uploading, a progress bar appears and advances toward 100%. The file name appears in the chat input area once the upload completes.

**Failure risk:** Without this test, a regression that removes progress bar rendering leaves researchers staring at a frozen UI during slow uploads. They cancel and retry, causing duplicate uploads and confusion.

**Target:** `file-upload.tsx` — progress bar during upload  
**Test file:** Extend `real-data-upload-through-chat.e2e.ts`  
**Assertions:**
- Upload a large FASTQ file (>1MB)
- Assert progress bar appears (`[data-testid="upload-progress"]`)
- Assert progress reaches 100% before upload completes
- Assert file name appears in chat input after completion

---

### UX-13: Dataset Browser

**User story:** As a researcher who already uploaded a FASTQ file in a previous session, I need the workflow parameter editor to show me my previously uploaded files in a browser panel so I can select them without re-uploading.

**Success looks like:** When configuring a workflow with a file param, a dataset browser panel appears listing previously uploaded files. Clicking a file in the browser populates the corresponding parameter field with the file's path.

**Failure risk:** Without this test, a regression that breaks the dataset browser means researchers must re-upload files for every run. Large genomics files (>10 GB) take hours to upload — a broken browser forces enormous redundant data transfers.

**Target:** `GalaxyDatasetBrowser` — lists uploaded files for workflow params  
**Test file:** `frontend/e2e/ux-dataset-browser.e2e.ts` (new)  
**Assertions:**
- Upload a file via chat
- Open a workflow with file param
- Assert dataset browser shows uploaded file
- Select file, assert it populates the param field

---

### UX-14: Settings Dialog

**User story:** As a researcher, I need to be able to enter my own Claude API key in the settings dialog so that my LLM usage is billed to my own account rather than the shared BioMate key.

**Success looks like:** Clicking the settings icon opens a dialog with an API key input. Entering a key and saving shows a success toast. After a page reload, the saved key is still present.

**Failure risk:** Without this test, a regression that breaks the settings dialog save flow means researchers cannot configure their own API keys — they silently fall back to the shared key, causing unexpected billing on the BioMate account.

**Target:** `settings-dialog.tsx`  
**Test file:** `frontend/e2e/ux-settings-dialog.e2e.ts` (new)  
**Assertions:**
- Click settings icon in sidebar
- Assert settings dialog opens (`[data-testid="settings-dialog"]`)
- Assert API key field visible
- Enter API key, save, assert toast "Settings saved"
- Reload page, assert key persists

---

### UX-15: Theme Toggle

**User story:** As a researcher who works in low-light lab environments, I need a dark mode toggle so I can reduce eye strain during long analysis sessions.

**Success looks like:** Clicking the theme toggle switches the app from light to dark mode (the `<html>` element gains a `dark` class). Clicking again restores light mode. The preference persists across page reloads.

**Failure risk:** Without this test, a regression that breaks the theme toggle leaves researchers stuck in light mode. This is low severity on its own, but a broken theme toggle that throws JavaScript errors can mask unrelated component failures.

**Target:** `theme-toggle.tsx`, `theme-provider.tsx`  
**Test file:** `frontend/e2e/ux-settings-dialog.e2e.ts` (combined)  
**Assertions:**
- Assert initial theme is light (or system)
- Click theme toggle → assert `<html class="dark">` present
- Toggle again → assert dark class removed

---

## Implementation Priority

| Priority | Tests | Rationale |
|---|---|---|
| **P1 — Week 1 (DONE)** | UX-9a/b/c (triage panel — all three) | Core post-run orientation; highest researcher-impact regression risk |
| **P1 — Week 1** | UX-7 (AI pre-fill), UX-11 (error badge) | Core workflow quality signals |
| **P1 — Week 1** | UX-10 (prereq chat link) | Workflow unblocking UX path |
| **P2 — Week 2** | UX-1+2 (thinking/typing), UX-3 (scroll), UX-4+5+6 (param types) | Input/output fidelity |
| **P2 — Week 2** | UX-12 (upload progress), UX-13 (dataset browser) | Data ingestion UX |
| **P3 — Week 3** | UX-8 (image viewer), UX-14+15 (settings/theme) | Polish/settings |

---

## Test File Map (new files needed)

| File | Tests | Status |
|---|---|---|
| `frontend/e2e/ux-execution-triage.e2e.ts` | UX-9a, UX-9b, UX-9c | **IMPLEMENTED 2026-04-09** |
| `frontend/e2e/ux-thinking-display.e2e.ts` | UX-1, UX-2, UX-3 | planned |
| `frontend/e2e/ux-param-types.e2e.ts` | UX-4, UX-5, UX-6 | planned |
| `frontend/e2e/ux-param-autofill.e2e.ts` | UX-7 | planned |
| `frontend/e2e/ux-error-analysis.e2e.ts` | UX-11 | planned |
| `frontend/e2e/ux-dataset-browser.e2e.ts` | UX-13 | planned |
| `frontend/e2e/ux-settings-dialog.e2e.ts` | UX-14, UX-15 | planned |
| Extend `ux-prereq-checklist.e2e.ts` | UX-10 | planned |
| Extend `real-data-upload-through-chat.e2e.ts` | UX-12 | planned |
| Extend `workflow-controls-comprehensive.e2e.ts` | UX-8 | planned |

---

## Current Coverage Summary

| Category | Total Elements | Covered | Gap |
|---|---|---|---|
| Chat interface | 9 | 5 | 4 (UX-1,2,3 + file progress) |
| Workflow viewer controls | 22 | 15 | 7 (param types, autofill, image, error) |
| Run manager panel | 8 | 8 | 0 |
| Auth flows | 5 | 5 | 0 |
| License/credential gate | 4 | 4 | 0 |
| QC gate | 3 | 3 | 0 |
| File upload & dataset | 4 | 2 | 2 (progress, browser) |
| Settings & theme | 3 | 0 | 3 (UX-14, 15) |
| Navigation & layout | 5 | 5 | 0 |
| Billing/checkout | 2 | 2 | 0 |
| Error & recovery | 5 | 4 | 1 (error badge) |
| **TOTAL** | **70** | **53** | **17** |

**Current coverage: 53/70 = 76%** (UX-9a/b/c added 2026-04-09)  
**Target: 70/70 = 100%**
