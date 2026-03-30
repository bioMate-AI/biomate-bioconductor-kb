# BioMate Pilot Study — Walkthrough Video Script

> **Format:** Screen-recorded demo with narration overlay.  
> **Target audience:** Pilot participants (lab PIs, postdocs, clinical researchers) — assume no prior BioMate experience.  
> **Total runtime target:** 8–10 minutes.  
> **Recording checklist:** Dark mode, 1080p minimum, hide browser bookmarks bar, use a demo account (not personal credentials), use realistic but anonymised sample data.

---

## Scene 0 — Title Card (0:00–0:10)

**Screen:** BioMate logo on dark background + tagline.  
**Overlay text:** "BioMate AI · Pilot Study Walkthrough · 2026"

**Narration:**  
*"Welcome to BioMate — an AI-powered bioinformatics platform that takes you from a plain-language research question to a publication-ready QC report, in a single conversation."*

---

## Scene 1 — Login and Dashboard (0:10–0:40)

**Screen actions:**  
1. Show the BioMate login page (`/login`).  
2. Type a pilot participant email and password. Click Sign in.  
3. Dashboard loads — show the run list (empty or previous runs).

**Narration:**  
*"After receiving your pilot invitation, you log in with the credentials we emailed you. You land on the dashboard, which shows all of your previous workflow runs. Today, let's start a new analysis."*

**Pointer highlights:**  
- "New conversation" / chat button in the sidebar.

---

## Scene 2 — Starting a Conversation (0:40–1:15)

**Screen actions:**  
1. Click "New conversation" (or equivalent).  
2. The chat interface opens — show the empty input box.  
3. Type the following query (type slowly, character by character):  
   > *"I have bulk RNA-seq data from a gastric adenocarcinoma cohort — 8 tumour samples vs 8 normal controls. Run a full DE analysis with DESeq2, produce volcano plot and heatmap, and tell me if there is a clear TP53 or ERBB2 signature."*
4. Press Enter / Send.

**Narration:**  
*"You ask BioMate in plain English — just as you would explain the task to a colleague. No command line, no script writing. BioMate reads your question, selects the right workflow, and begins planning the analysis."*

---

## Scene 3 — Workflow Planning Response (1:15–2:00)

**Screen actions:**  
1. Show the AI response appearing — the tool call plan, selected workflow name ("RNA-seq Differential Expression — DESeq2").  
2. Highlight the "Execution plan" summary card if visible.  
3. Show the typing indicator while the workflow is being prepared.

**Narration:**  
*"BioMate responds with a structured execution plan. It identifies the right workflow — in this case DESeq2-based differential expression — confirms the parameters it will use, and asks if you want to proceed or adjust anything."*

*"For the pilot, just press 'Run' or type 'yes, proceed'. You don't need to specify genome version, normalisation method, or p-value thresholds unless you want to — BioMate applies validated defaults."*

**Pointer highlights:**  
- Workflow name chip / badge.  
- "Run" button or confirmation message.

---

## Scene 4 — Live Execution Progress (2:00–2:45)

**Screen actions:**  
1. Show the execution progress panel — step names ticking off ("FASTQ QC", "STAR alignment", "featureCounts", "DESeq2 normalisation", "DE testing").  
2. Show the status dots (green = done, spinner = running, grey = pending).  
3. If available, show a brief log snippet scrolling.

**Narration:**  
*"While BioMate is running, you can see each pipeline step in real time. You don't need to stay on this page — BioMate will notify you when it's done. You can open another conversation, or close the browser and come back later."*

---

## Scene 5 — Results and QC Report (2:45–4:30)

**Screen actions:**  
1. Show the completed state — results appear in chat.  
2. Scroll through the AI summary: number of DEGs, top hits (TP53 pathway, ERBB2 upregulation), brief interpretation.  
3. Click the "View QC Report" or "Download Report" button.  
4. Show the QC report page:  
   - **Overall QC status banner** (PASS / WARN / FAIL, with counts).  
   - **QC gates table** with PASS/WARN/FAIL status chips.  
   - **Evidence level badges** (GOLD, SILVER, BRONZE).  
   - **Methods section text** (auto-generated paragraph describing the analysis).  
5. Scroll to the methods text and highlight it.

**Narration:**  
*"When the analysis is complete, BioMate delivers three things: first, a plain-language summary of what it found — here it confirms an ERBB2 upregulation signature consistent with HER2-positive gastric cancer; second, all result files you can download; and third, a QC audit report."*

*"The QC report is the key deliverable for your manuscript. It shows every quality gate — alignment rate, library complexity, DESeq2 dispersion fit — with PASS, WARN, or FAIL status. The evidence level badges tell you how robust each result is."*

*"At the bottom is an auto-generated methods paragraph. You can copy this text directly into your methods section — it describes every tool, version, and parameter used. No more writing methods from memory."*

**Pointer highlights:**  
- PASS badge in green.  
- Methods text block — highlight and copy gesture.

---

## Scene 6 — Downloading Results (4:30–5:00)

**Screen actions:**  
1. Show the attachments / output panel.  
2. Click to download: `DESeq2_results.csv`, `volcano_plot.png`, `heatmap.png`, `QC_report.html`.  
3. Show the PDF print prompt briefly ("Print → Save as PDF" note in the QC report).

**Narration:**  
*"All result files are available for download. The QC report can be saved as a PDF by using the 'Download as PDF' button in the report — this uses your browser's print-to-PDF function and preserves all formatting."*

---

## Scene 7 — Changing Direction (Drug Discovery, 5:00–6:15)

**Screen actions:**  
1. Open a new conversation.  
2. Type:  
   > *"Screen these 15 compounds against the KRAS G12D binding pocket: [list of SMILES strings, or say 'use the demo compound set']. Run ADMET prediction and flag anything with hERG liability or poor oral bioavailability. Then do a molecular docking run against PDB 6OIM."*
3. Show the AI response — selects Drug Discovery workflow, lists ADMET + docking steps.  
4. Cut to completed run — show the ADMET table with flagged compounds highlighted in red.  
5. Show the docking score summary (top 3 compounds with scores).

**Narration:**  
*"BioMate supports five research directions in this pilot. Here's a drug discovery example. I ask it to screen compounds for ADMET liabilities and dock them against a KRAS crystal structure. BioMate flags any compound with predicted hERG toxicity or poor solubility — you see them highlighted in red in the table."*

*"The top docking candidates are ranked by score. This entire screen — from 15 SMILES strings to a shortlist of 3 lead compounds — takes under 30 minutes."*

---

## Scene 8 — Providing Feedback (6:15–7:00)

**Screen actions:**  
1. After the run completes, show the post-run micro-survey appearing in the bottom-right corner.  
2. Answer two questions: QC rating (click "4"), workflow ran without correction ("Yes").  
3. Enter prior time estimate: "8 hours".  
4. Click Submit.  
5. Show the "Thank you" confirmation.

**Narration:**  
*"After each run, BioMate shows a short feedback survey. There are two required questions: a rating of whether the QC output is publication-ready, and whether the workflow ran without you needing to correct anything. These two questions directly measure whether the pilot is achieving its goals."*

*"The prior-time estimate — 8 hours in this example — captures how long this analysis would have taken you before BioMate. This data helps us quantify the time saving across the pilot cohort."*

*"The survey takes about 60 seconds and you can always skip it."*

---

## Scene 9 — Admin Dashboard (optional, 7:00–8:00)

> *Include this scene only in the PI/faculty version of the video — skip for general participant version.*

**Screen actions:**  
1. Navigate to `/admin/feedback-dashboard` (log in as admin).  
2. Show the Pilot KPI panel at the top:  
   - H1 Workflow quality: 85%  
   - H2 Time to result: 22 min  
   - H3 QC defensibility: 4.1/5  
   - H4 Pricing: 72% Yes  
   - H5 Hallucinations: 0
3. Scroll down to show the feedback summary and confusion triage tables.

**Narration:**  
*"If you are a study coordinator or PI, the admin dashboard gives you a real-time view of all five pilot evaluation hypotheses. You can see the aggregate pass rates, average time savings, and QC ratings across all participants. This is the data we will review together at the pilot debrief."*

---

## Scene 10 — Exit Survey and Close (8:00–8:45)

**Screen actions:**  
1. Navigate to `/pilot-exit-survey`.  
2. Quickly click through the pages (don't fill in real data — just show the structure).  
3. Show Page 1 (About you, pilot direction selection).  
4. Show Page 2 (H1 — total runs, correction rate, hallucinations).  
5. Show Page 3 (H2 time, H3 QC rating).  
6. Show Page 4 (pricing, literature agent).  
7. Show Page 5 (overall rating, biggest gap, co-authoring).

**Narration:**  
*"At the end of the 21-day pilot, you will receive an email with a link to the exit survey. This is the most important piece of data we collect — it aggregates your experience across all runs into a single structured response. It takes about 5 minutes."*

*"The exit survey directly measures the five hypotheses we are testing in this pilot. Your responses will be shared back with you at the pilot debrief, along with the aggregate results across all participants."*

---

## Scene 11 — Closing (8:45–9:15)

**Screen:** Return to BioMate homepage or dashboard.

**Narration:**  
*"That's the BioMate pilot study workflow. To recap: you ask a plain-language research question, BioMate runs the pipeline and delivers results with a publication-ready QC report, you download your files and copy the methods text, and you complete a short feedback survey after each run."*

*"If you encounter any issues, use the 'Report an issue' button in the chat interface, or contact your pilot coordinator directly. We will respond within one business day."*

*"Thank you for participating in the BioMate pilot. We look forward to your feedback."*

---

## Post-Production Notes

| Item | Specification |
|---|---|
| Screen resolution | 1920 × 1080 minimum |
| UI theme | Dark mode recommended (better contrast for screen recording) |
| Font zoom | Browser at 110% zoom for readability |
| Cursor | Use a large, visible cursor (e.g., Cursor Highlighter extension) |
| Background music | None (professional narration only) |
| Captions | Auto-generate with Whisper; review manually before publishing |
| Chapters | Add YouTube chapters at each Scene marker |
| Hosting | Upload to Vimeo (pilot access only, password-protected) |
| Length cap | Hard cut at 10 minutes — defer additional features to a follow-up video |

## Scenes by Pilot Direction

If time allows, record individual 2-minute clips for each direction and link them from the user guide:

| Direction | Query example | Key result to show |
|---|---|---|
| A — Drug Discovery | "Screen 15 compounds against KRAS G12D..." | ADMET table, docking ranks |
| B — RNA-seq | "DE analysis, gastric cancer 8v8..." | Volcano plot, DEG count, methods text |
| C — Cryo-EM | "Run CryoSPARC SPA on the attached MRC stack..." | 3D map, resolution estimate, FSC curve |
| D — Single-Cell | "Seurat clustering of PBMC 10X data, annotate cell types..." | UMAP coloured by cell type |
| E — Multi-Omics | "DIA-LC-MS/MS proteomics QC + differential abundance for 6v6 HCC vs normal..." | Volcano + missing-value heatmap, GOBP enrichment |
