# BioMate Learning Series — production index

This is a coordinated English and Chinese series. Each episode teaches a focused user outcome, explains the necessary concepts, demonstrates the real BioMate interface, and ends with interpretation and a practical next step. Broad chapter episodes orient viewers; focused episodes demonstrate individual functions.

The initial catalog has **28 source chapters and 42 focused episodes: 70 episode briefs, 140 language editions planned**. These are production entries, not completed videos. The catalog must continue to be reconciled with the shipped workflow inventory; its count is not proof of exhaustive product coverage.

## Format and review standard

- Maintain consistent typography, colors, title cards, terminology and navigation across the series.
- Teach the question, prerequisites and input format before showing actions. Explain the resulting files and scientific limitations afterward.
- Demonstrate working product behavior with real, traceable evidence. Source-code availability and a design prototype do not establish successful execution.
- Produce English and Chinese narration and captions separately. Preserve actual UI labels while explaining them in the audience's language.
- Keep a 1920 × 1080 master for client delivery and long-form viewing. Create platform-specific cuts only after the master passes review; do not crop interface text into an unreadable vertical video.
- Review the final encoded MP4 for readable text, synchronized narration, captions, pronunciation, factual accuracy and privacy before client delivery or publication.

Current drafts: ADMET interpretation, downloading run outputs, and inspecting the reproducibility record. The user authorized Gemini narration generation. Narrated review masters and draft captions are now in production; silent copies remain as earlier layout previews. Narrated masters are not approved client or marketing deliverables.

## Existing pipeline, extended

The entry point remains `reference/claude_design/tutorials-work/make_video.py`. New catalog mode uses the existing tutorial folder and does not invoke an external speech service.

From the repository root, inventory every English and Chinese edition:

```sh
python3 reference/claude_design/tutorials-work/make_video.py   --catalog reference/claude_design/tutorials/series/catalog.json   --report docs/qa/20261003-tutorial-release/series-inventory.json
```

Render the three available bilingual silent review drafts:

```sh
python3 reference/claude_design/tutorials-work/make_video.py   --catalog reference/claude_design/tutorials/series/catalog.json   --action render --only admet-evidence,result-downloads,reproducibility-record   --silent-preview   --report docs/qa/20261003-tutorial-release/series-render.json
```

An existing output is protected unless `--overwrite` is supplied. Omit `--only` to request the whole catalog; any unavailable edition is reported and causes the render command to exit unsuccessfully. No missing episode is silently declared complete.

Narrated mode requires an `audio` directory per episode, with `en/` and `zh/` subdirectories. Each `step-NNN.wav` must be mono 24 kHz, 16-bit PCM and accompanied by a JSON receipt containing the SHA-256 of the exact UTF-8 narration text (`narrationSha256`) and WAV bytes (`audioSha256`). A changed script or audio file invalidates the receipt. These checks establish asset consistency, not factual accuracy or voice quality. Review remains required.

## Episode inventory

All entries are pending release review. “Partial” verification applies only to the explicitly recorded checks, not the entire source tutorial. Each episode has English and Chinese editions.

| Episode | Track | Type | Product verification |
|---|---|---|---|
| m1-search-and-evidence — Module 1 — Search & evidence: asking "what is known?" | platform | chapter | blocked |
| m2-data-analysis — Module 2 — Data analysis: working on your own data | platform | chapter | blocked |
| s1-sidebar-navigation — Tutorial S1 — The sidebar: finding your way around BioMate | platform | chapter | pending |
| t0-getting-started — Tutorial 0 — Getting started: your first question to BioMate | platform | chapter | blocked |
| t1-design-and-generate — Tutorial 1 — Designing new drug molecules (Design & Generate) | drug-development | chapter | pending |
| t10-exploring-your-datasets — Tutorial 10 — Exploring your datasets: metadata, preview, lineage & versions | platform | chapter | pending |
| t11-drug-development-end-to-end — Tutorial 11 — The whole drug-development pipeline, end to end | drug-development | chapter | pending |
| t2-models-and-the-closed-loop — Tutorial 2 — Models and the closed loop (how BioMate gets smarter) | drug-development | chapter | pending |
| t3-running-a-workflow-and-reading-the-report — Tutorial 3 — Running a workflow and reading the report | platform | chapter | pending |
| t4-bringing-your-own-data — Tutorial 4 — Bringing your own data | platform | chapter | pending |
| t5-viewing-your-results — Tutorial 5 — Viewing your results: outputs, previews & interactive tools | platform | chapter | pending |
| t6-connecting-instruments — Tutorial 6 — Connecting lab & hospital instruments | platform | chapter | pending |
| t7-projects-and-collaboration — Tutorial 7 — Projects, standing instructions & collaboration | platform | chapter | pending |
| t8-reports-edit-and-export — Tutorial 8 — Reports as editable files, and exporting them | platform | chapter | pending |
| t9-connecting-data-and-tools — Tutorial 9 — Connecting data sources & tools | platform | chapter | pending |
| w1-workflow-panel-tabs — Tutorial W1 — The workflow panel before and during a run | platform | chapter | pending |
| w2-after-run-panel — Tutorial W2 — The after-run panel: Summary, Outputs, and the Reproducibility record | platform | chapter | pending |
| w3-full-step-view — Tutorial W3 — The full step view: opening one step as an object | platform | chapter | pending |
| basespace-sequencing — Instrument tutorial — Illumina BaseSpace → RNA-seq, variant calling (WGS) & 16S | instruments | chapter | pending |
| benchling-eln-lims — Instrument tutorial — Benchling ELN / LIMS → drug-discovery ADMET screening | instruments | chapter | pending |
| cryoem-reconstruction — Instrument tutorial — Thermo EPU / cryo-EM microscope → 3-D reconstruction | instruments | chapter | pending |
| flow-cytometry-gating — Instrument tutorial — flow cytometer → gating & immunophenotyping (FCS) | instruments | chapter | pending |
| lcms-proteomics-metabolomics — Instrument tutorial — LC-MS → proteomics (DDA/DIA) & metabolomics feature detection | instruments | chapter | pending |
| nanopore-minknow — Instrument tutorial — Oxford Nanopore MinKNOW → long-read analysis | instruments | chapter | pending |
| opentrons-liquid-handling — Instrument tutorial — Opentrons OT-2 / Flex (liquid-handling robot) | instruments | chapter | pending |
| plate-reader-assays — Instrument tutorial — plate reader → dose–response, IC50 & assay quantification | instruments | chapter | pending |
| qpcr-quantification — Instrument tutorial — qPCR → relative gene-expression (ΔΔCt) | instruments | chapter | pending |
| sila2-devices — Instrument tutorial — SiLA2 devices (a standard, not one machine) | instruments | chapter | pending |
| composer — The composer: attachments, clarification and lane selection | platform | focused | pending |
| molecule-generation — Generate small-molecule candidates | drug-development | focused | pending |
| multi-objective-ranking — Compare and rank candidates across objectives | drug-development | focused | pending |
| pretrained-models — Run and inspect a pre-trained model | drug-development | focused | pending |
| model-training — Train a model and inspect held-out evaluation | drug-development | focused | pending |
| model-adaptation — Adapt a model to a new task | drug-development | focused | pending |
| model-optimization — Optimize and compare model versions | drug-development | focused | pending |
| wet-lab-loop — Return measurements and review a closed-loop round | drug-development | focused | pending |
| table-viewer — Inspect tabular results | platform | focused | pending |
| sequence-viewer — Inspect sequence results | platform | focused | pending |
| variant-viewer — Inspect variant results | platform | focused | pending |
| structure-viewer — Inspect molecular structures | platform | focused | pending |
| interactive-analysis — Open results in an interactive analysis tool | platform | focused | pending |
| project-instructions — Set project instructions | platform | focused | pending |
| project-sharing — Share a project and check roles | platform | focused | pending |
| report-editing — Edit a report and save a version | platform | focused | pending |
| report-export — Export a report and inspect the downloaded files | platform | focused | pending |
| database-connectors — Connect a database and verify a query | platform | focused | pending |
| mcp-connectors — Connect an MCP tool and review capabilities | platform | focused | pending |
| dataset-lineage — Trace dataset origin and downstream use | platform | focused | pending |
| dataset-versions — Read a dataset version log | platform | focused | pending |
| admet-evidence — Interpret ADMET predictions and their limits | drug-development | focused | partial |
| physicochemical-properties — Inspect physicochemical predictions | drug-development | focused | pending |
| qsar-prediction — Interpret a QSAR prediction | drug-development | focused | pending |
| molecular-docking — Run docking and interpret poses and scores | drug-development | focused | pending |
| rbfe — Review relative binding free-energy results | drug-development | focused | pending |
| pk-pbpk — Interpret PK and PBPK simulations | drug-development | focused | pending |
| literature-evidence — Search literature and inspect citations | platform | focused | pending |
| database-evidence — Find evidence in scientific databases | platform | focused | pending |
| patent-evidence — Search patents and inspect source material | platform | focused | pending |
| internal-evidence — Search authorized internal evidence | platform | focused | pending |
| instant-analysis — Run an instant data analysis | platform | focused | pending |
| cloud-analysis — Run a cloud workflow with resolved inputs | platform | focused | pending |
| wgs-analysis — Analyze germline sequencing data | instruments | focused | pending |
| rnaseq-analysis — Analyze bulk RNA sequencing data | instruments | focused | pending |
| proteomics-dda — Analyze DDA proteomics data | instruments | focused | pending |
| proteomics-dia — Analyze DIA proteomics data | instruments | focused | pending |
| metabolomics — Analyze metabolomics data | instruments | focused | pending |
| dose-response — Fit and inspect a dose–response curve | instruments | focused | pending |
| hts-hit-calling — Review screening controls and hit calling | instruments | focused | pending |
| result-downloads — Keep the evidence behind a result | platform | focused | partial |
| reproducibility-record — Trace a result back to its run | platform | focused | partial |

## Narrated review batch

Three episodes now have English and Chinese narrated review masters (six MP4s), plus chapter markers and draft SRT/VTT captions. Open `review.html` through the local repository server to compare language editions. See the [detailed scientific and presentation audit](../../../../docs/qa/20261003-tutorial-release/SCIENCE_AND_PRESENTATION_AUDIT.md). None is approved for publication yet.
