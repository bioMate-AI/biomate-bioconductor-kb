# BioMate series — scientific and presentation audit

Scope: the three prepared bilingual episodes and the drug-development source chapter (T11). This is not a completed review of all 70 episode briefs or a validation of the underlying scientific models.

## Corrections made

| Finding | Correction | Evidence |
|---|---|---|
| hERG jargon lacked a definition and score direction | Define the cardiac potassium channel and explain blocker-class direction; distinguish classification score, IC50 and patient risk | [TDC endpoint definitions](https://tdcommons.ai/single_pred_tasks/tox/); preserved raw output |
| DILI panel aggregation was unexplained | Expand drug-induced liver injury; identify the highest compound score, caffeine's 0.8746 rounded to 0.875; identify the configured 0.5 threshold | `toxicity_report.json` and `qc_metrics.json` |
| Broad 89% ADMET / 98.5% PBPK claims lacked metric and dataset context | Removed from both T11 language editions; require a named endpoint, metric, split and retrievable evaluation | Source-chapter audit |
| Docking was described as establishing actual binding; docking → RBFE → MD implied increasing accuracy | Rewrote both language editions around the different questions, assumptions and limitations; removed an unqualified 1.73 kcal/mol claim | [Vina documentation](https://autodock-vina.readthedocs.io/en/latest/faq.html); [alchemical free-energy best practices](https://arxiv.org/abs/2008.03067) |
| PBPK wording implied a safe human dose and regulatory-ready output | Replaced with exposure scenarios, intended-use evaluation and explicit demonstration status | [FDA PBPK guidance](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/physiologically-based-pharmacokinetic-analyses-format-and-content-guidance-industry) |
| Reproducibility prose promised a complete record | Replaced with the observed empty input bindings/tool parameters and absent default hashes | `reproducibility-record.json` |
| Execution success could be read as scientific validity | Explicitly separated in the narration and tutorial | Actual completed run plus model/output review |

The numerical checker (`science-claim-audit.json`) passed 11 checks against the preserved output artifacts. It checks faithful representation of this example, not model calibration, generalization or biological validity. Cardiac risk interpretation is consistent with the integrated evidence approach described by [FDA](https://www.fda.gov/drugs/regulatory-science-action/streamlining-analysis-ion-channel-in-vitro-assays-data-support-clinical-cardiac-safety-decision-making). The [ADMET-AI paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC11226862/) supplies model context, not a blanket accuracy claim for BioMate's combined workflow.

## Presentation and language

- Matching English and Chinese scene structure and scientific qualifications; revised hERG/DILI narration regenerated in both languages.
- Genuine high-resolution BioMate panel captures, with the English interface identified in the Chinese lesson.
- 1080p layout and overflow checks passed for the 40 frames across the three bilingual episodes (20 ADMET frames and 20 platform-lesson frames).
- Representative full-size frames and an encoded result-download frame were inspected. The smaller UI text still needs closer crops for mobile delivery; do not claim phone readability has passed.
- Speech-only review masters use loudness normalization. Codec, duration, full decode and measured loudness/peak checks are recorded independently in `series-media-audit.json` when the batch completes.
- Captions are SRT/VTT drafts with proportional phrase timing. They are **not forced-aligned** and must not be marked synchronized until checked against the speech.
- These first masters are narrated storyboards with real screenshots. They still need action footage where the learning objective requires showing clicks, downloads or edits.

## Privacy and release clearance

The three panel images were inspected: they show a demonstration run and known small-molecule outputs, with no visible account email, credentials, patient details or signed storage URLs. The run ID remains visible for internal review. The uncropped QA screenshots and navigation-failure artifacts contain account/workspace context and are not client/public assets. Do not package the entire QA directory for distribution.

No external music, stock video or third-party figure reproductions were added. Narration uses a Gemini prebuilt voice under the user's explicit authorization. No publication rights or legal approval is inferred from successful generation. Final publication remains subject to the user's review.

## Open issues

1. **Scientific product limitation:** the workflow mixes raw hERG scores with heuristic IC50 estimates. The lessons distinguish them; this does not fix or validate the model implementation.
2. **Live navigation failure:** New Chat inserts a welcome message, while the cold-start modules require an empty message list. T0/M1/M2 are blocked for the documented route until corrected and rechecked. No UI was fabricated to pass the test.
3. **Audio review:** pronunciation, omissions and natural delivery still require a full listening pass. Technical audio tests cannot establish those properties.
4. **Caption and final video review:** align captions, add necessary UI close-ups/action footage, inspect the full encoded videos and then review platform-specific cuts.
5. **Series coverage:** the other episode briefs remain pending product/science/editorial checks. No all-series completion or release score is claimed.

## User review: static-screen defect

The user correctly identified that the MP4s contain narrated still frames. They are storyboards, not acceptable finished function tutorials. This is a production-format failure, not an intentional final presentation choice. The player and render receipts now explicitly identify the static format. Technical codec/audio passes must not be interpreted as audiovisual acceptance. Required correction: record real product actions, edit each action to the relevant narration, and review the resulting motion and readability before replacing the draft.


## Full-motion replacement progress

The output-download lesson now has complete English (95.517 s) and Chinese (98.037 s) real UI review exports in `recording/output/series-live-v2`. Both recording tests passed and validated a downloaded report containing three compounds. Both exports passed decode, format, loudness and scene-change checks in `live-video-review/media-audit.json` (17 significant changes each). These are technical checks, not release approval.

Visual inspection found the Chinese QC preview still loading at 40 seconds. The previous negative loading-text check did not establish visible content reliably. The recorder now requires a visible `pre` containing the expected file-specific content and targets a separate v3 take; that new guard has not yet been exercised. Both v2 exports remain changes-required pending complete preview inspection, narration review, precise captions, close-ups and review of scientific claims visible in the interface. The other four narrated masters remain static storyboards.
