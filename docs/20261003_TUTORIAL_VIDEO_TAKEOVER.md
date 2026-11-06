# Tutorial and video production — takeover and release review

Source: `reference/0930_todo.md`, marketing/tutorial scope; Claude handoff supplied by the user.
Release status: **HOLD. No deliverable approved for client distribution or public publishing in this review.**

## Confirmed inventory

- 57 Markdown tutorial documents; six older MP4 exports (drug development, T0, T3, EN/ZH).
- All referenced local image files exist. There are **92 unfinished figure placeholders** across the documents. File existence is not visual or scientific approval.
- MP4s are 1920×1080 H.264, 25 fps, with stereo AAC at 48 kHz.
- Upgraded drug-development source has 17 scenes and a 516.1-second raw recording. Its older exported MP4s are approximately 326 seconds EN / 333 seconds ZH: the upgrade was not exported into those files.
- Both upgraded narration sets fit the recorded scene slots. Their content remains under review; timing fit alone is not approval.
- The Chinese export uses Chinese narration with the shared English visual deck. Localized educational slides and captions are still required.

Machine-readable inventory: `qa/20261003-tutorial-release/asset-inventory.json`.

## Current live BioMate evidence

Read-only check against `https://dev-public.biomate.ai`, 2026-10-03.
Run: `c40459b2-4dd0-407e-bbbd-e985df4ce0fc`; session: `chat-1790955154245-s17yy1qla`.

1. Run execution status is `completed`; the normal chat opens the ADMET workflow without a debug route.
2. Canonical output inventory lists six files. **Downloading the first file returns S3 HTTP 403 / `InvalidAccessKeyId`.** A separate unauthenticated request follows the presigned storage redirect, so the failure is not caused by forwarding BioMate's bearer token to S3.
3. Summary visibly says **“Analysis in progress…”**; chat also says “analyzing results.” This cannot support a claim of complete, readable findings.
4. Reproducibility record lists six outputs, but default SHA-256 fields are null, `inputBindings` is empty, and `toolParameters` is empty. Checksum computation is opt-in in current code. The pilot's claim that exact inputs, parameters, software versions, checksums and citations are automatically present for every run is not established.
5. Repeated project/chat labels remain visible. Capture should use a clean demo context or collapse navigation through the real interface; do not fabricate a clean product state by editing screenshots.

Evidence and screenshots: `qa/20261003-tutorial-release/`.
Strict audit: `frontend/e2e/tutorial-release-audit.e2e.ts`.
Earlier screenshot harnesses catch exceptions and log failures without failing the test: their green exit status is not release evidence.

## Content corrections required

- Remove unqualified 89% ADMET and 98.5% PBPK claims. Any future metric needs a named dataset, metric, split, sample count, software/model version, limitations and retrievable result. A workflow execution or internal test pass rate is not predictive accuracy.
- Separate measured experimental values, model predictions and illustrative teaching numbers. The displayed hERG 0.71 / 0.50 example is illustrative; it is not a measured result from this run or a universal safety threshold.
- Explain endpoint direction and units before applying a threshold. Higher predicted risk and higher hERG IC50 do not mean the same thing.
- Docking proposes poses; RBFE estimates relative affinity under defined assumptions; MD samples motion. None establishes binding or clinical safety by itself, and they are not a guaranteed accuracy ladder.
- Do not imply a PK simulation alone determines a safe first-in-human dose, or that an automatic report satisfies regulatory requirements.
- Replace blanket “VALIDATED” badges with scoped evidence labels: demonstrated in this run / concept explanation / awaiting product verification.
- Use the actual visible tab labels: Summary, Outputs, Reproducibility record.
- Remove internal implementation details and debug metrics from client-facing narration. Keep evidence in internal review records.

Scientific references for the editorial review:
- [FDA E14/S7B Q&A](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/e14-and-s7b-clinical-and-nonclinical-evaluation-qtqtc-interval-prolongation-and-proarrhythmic): integrated cardiac risk assessment, not a single computed hERG score.
- [Best Practices for Alchemical Free Energy Calculations](https://arxiv.org/abs/2008.03067): preparation, sampling, uncertainty and validation of binding free-energy estimates.

## Release workflow

1. Verify each taught journey on BioMate with real inputs, successful outputs, previews/downloads, units and interpretation. Preserve failed checks. A visible screen is not an executed workflow.
2. Fix product blockers and rerun the affected journey before filming success claims. Keep unverified capabilities out of demonstrations.
3. Use the existing Claude Design visual style. Alternate concept teaching, real UI actions and worked result interpretation; show learning objectives, prerequisites, inputs, expected outputs and limitations.
4. Produce EN and idiomatic Simplified Chinese slides, narration and synchronized captions. Readability must pass at 1080p and on a phone; use deliberate UI close-ups and callouts.
5. Review audio completeness, terminology, clipping/loudness, subtitle timing, text overflow, scientific fidelity and privacy. Never replace failed TTS with silent placeholders.
6. Deliver review masters, subtitle files, thumbnails, chapter markers, descriptions and companion tutorials with version/hash provenance. Prepare separate vertical excerpts for mobile channels without cropping away context.
7. Only after technical/editorial review and user review: publish or distribute. Uploading for review and public publication are distinct states.

Next work: diagnose the development service's S3 signing credentials, restore real downloads/findings, verify run inputs, then rebuild the bilingual pilot before scaling T0/T3/T10/T4/M1/M2 and instrument workflows.

## Configuration repair review (before execution)

The development container's NF-specific S3 credentials fail on the exact tutorial object, while its default credential provider successfully reads that same 1,656-byte object. `/opt/biomate/.env` exactly matches both providers in the running container. Repair removes only the two obsolete NF overrides from that persistent file and clears those overrides in a replacement container. It preserves the current filesystem using a local Docker snapshot, all other environment values, host configuration, network and mounts. No repository application code is deployed. The original container and a mode-0600 environment backup are retained; failed health checks restore both. Expected smoke result: healthy dev, the same completed run, and successful downloads through BioMate. This does not establish scientific validity or repair incomplete provenance by itself.

## Repair result and subsequent verification

- Repair completed successfully at 2026-10-03 16:47 UTC. Original container retained as `biomate-dev-frontend-pre-output-repair-20261003T164737Z`; restricted backup directory `/opt/biomate/credential-repair-backups/20261003T164737Z` on the dev host.
- Strict live audit **passed after repair**: same completed run, all six files downloaded through the authenticated BioMate path, real Summary/Outputs/Record tabs captured. Findings now populate in the Summary and chat. No speculative repository deployment was performed.
- New captures are high DPI, including isolated report panels captured by the browser to avoid duplicate navigation in the teaching slides.
- The raw output reveals a separate scientific blocker: `hERG_probability` is transformed into an IC50 by a single-compound-calibrated power law in `predict_admet_properties/main.nf`, while `per_compound` IC50 values retain descriptor heuristics. The aggregate field is 432.4246 µM while per-compound values are 52.725, 6633.041 and 5.227 µM. These are different estimators; they are not interchangeable experimental measurements. No workflow/model correction or fresh execution has yet been performed.
- The corrected pilot is scoped to inspecting raw ADMET classifications and records, and explicitly identifies those limitations. It does not claim a completed JAK1 discovery campaign. Actual inputs are aspirin, caffeine and ibuprofen.
- New bilingual storyboard: `reference/claude_design/tutorials/review-pilot/storyboard.json`; interactive preview: `index.html?lang=en` / `index.html?lang=zh`; companions: `qa/20261003-tutorial-release/PILOT_REVIEW_EN.md` and `PILOT_REVIEW_ZH.md`.
- Audio pipeline now stops on TTS errors rather than inserting silence. Mux guards reject stale scripts, wrong audio formats, missing/extra clips and scene overruns; the final scene is held for its full duration. Four regression checks passed.
- **External audio generation blocked by automatic approval review:** sending narration to Google Gemini requires explicit user permission because BioMate content may be proprietary. An asynchronous permission question is pending. No narration was sent by the rejected command and no revised MP4 has been generated.

## Visual review

All 20 localized slides were rendered at 1920×1080. Automated overflow checks passed after increasing title line height. Contact-sheet and full-size inspection caught an optional feedback popup covering the source record; the capture harness now dismisses it with the actual **Not now** button and recaptures the unobstructed panel, without submitting feedback. The captions and example values were checked against the downloaded per-compound JSON. Product screenshots remain the genuine English UI, explicitly labeled in the Chinese edition.

## Series scope and pipeline continuation

The user clarified that this is a full series, with a separate focused video for each use case or function. Added `reference/claude_design/tutorials/series/catalog.json` and its human-readable index: 28 existing bilingual tutorial chapters plus 42 focused episode briefs, for 140 planned language editions. This is an initial production inventory, not a statement that all product workflows have been covered or that the videos are complete. Every source tutorial in both languages is checked against the catalog. Future shipped-function reconciliation must add remaining unmapped cases.

Extended the existing `tutorials-work/make_video.py` with catalog inventory and batch rendering. It reports every selected language edition, protects existing outputs, rejects missing or stale narration, and exits unsuccessfully when a requested render has blocked editions. All outputs retain internal-review status. Seven regression checks pass across the existing media guards and new series tests.

Added two bilingual five-scene review lessons alongside ADMET interpretation: **downloading run outputs** and **inspecting the reproducibility record**. These use the actual captured BioMate output and record panels and the verified six-file retrieval. They do not claim fresh workflow execution, UI record export, or checksum computation has been demonstrated. Their 20 captured frames passed automated bounds/overflow checks; representative English and Chinese frames were visually inspected. These are still storyboard previews: final action recording, narration, captions, scientific/editorial review, and full encoded-video review remain required.

Speech-provider authorization remains pending the earlier request. No external narration call was made as part of this series continuation.

## Authorized narration and detailed review

The user explicitly authorized Gemini narration generation, then requested detailed scientific, clarity and presentation review. Narration generation is no longer permission-blocked. Six narrated review MP4s were generated for ADMET interpretation, result downloads and the reproducibility record. The ADMET hERG and DILI passages were revised during scientific review and regenerated in both languages; exact-text hashes prevent the superseded clips from being accepted. SRT/VTT caption timing is explicitly marked as a proportional draft, not forced-aligned.

Scientific edits also corrected both T11 language editions: removed unspecified ADMET/PBPK/RBFE benchmark numbers, the docking-to-MD accuracy ladder, implied experimentally proven binding, implied safe-human-dose determination, regulatory-ready output and complete-provenance claims. The preserved example passed 11 numerical/metadata fidelity checks. Eight media regression tests pass. The full review findings and open items are in `qa/20261003-tutorial-release/SCIENCE_AND_PRESENTATION_AUDIT.md`.

A new strict live navigation check found a real issue: `createNewSession` inserts an assistant message with ID `welcome`; `chat-interface.tsx` mounts the cold-start dashboard only when `displayMessages.length === 0`. Clicking New Chat therefore showed the welcome text instead of the four module cards. The earlier broad navigation scripts could silently skip this. The new check fails, and the affected T0/M1/M2 entries are blocked. No production app code was deployed or screenshot state fabricated.

Review room: `reference/claude_design/tutorials/series/review.html`. It provides both language editions and draft caption tracks without uploading or publishing anything. Full listening, pronunciation, exact caption alignment, needed UI close-ups/action footage, final audiovisual review and the rest of the episode library remain incomplete.

## Static-video correction after user review

The user identified that the videos only narrated still screens. Acknowledged this as the wrong format for finished tutorials. The review page and render receipts now explicitly say static storyboard. Captured actual BioMate tab switching, a successful toxicity-report preview, a UI-triggered download (parsed and checked: three compounds), and navigation to the reproducibility record. The strict action-recording test passed. The optional feedback popup is dismissed with its real Not now control before recording; the exact Close preview control is used.

First action footage: `recording/video/series-actions/outputs-actions-MOTION-REVIEW.mp4` (20.39 seconds, silent source footage, not a replacement finished episode). Source WebM, event timestamps and downloaded-file evidence are adjacent. Encoded frames at 7 and 18 seconds show the real preview and record respectively. Next required work: record and edit the full actions to match each language narration, improve UI close-ups, and replace the static tutorial masters. Do not claim the existing six narrated storyboards have already been converted.
