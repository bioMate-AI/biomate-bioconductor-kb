# BioMate IND Report Service — Product UI Requirements

**Date:** 2026-05-04  
**For:** Claude Design  
**Product:** BioMate IND Report — client-facing regulatory document generation service  
**Route:** `/ind-report` (new top-level page, separate from the existing CRO compliance workspace)  
**Stack:** React + TypeScript + Tailwind + shadcn, matching existing BioMate frontend  
**Reference design tokens:** `frontend/client/src/styles/reference-design.css`

---

## What This Product Does

A pharma/biotech client provides their compound data (SMILES, assay results, target/indication) and receives a complete, regulation-ready ICH M4 CTD Module 2.6 nonclinical written summary package — signed, frozen, and downloadable as DOCX — in under 10 minutes. The product covers §2.6.1–§2.6.6 for FDA, EMA, NMPA, and PMDA simultaneously.

This is not a form that generates a document. It is a pipeline where each step feeds into the next, with the document as the final deliverable.

---

## Two Entry Points — Both First-Class

There are two types of clients and both must feel natural:

### Entry A — Targeted (knows they need an IND package)

Client navigates directly to `/ind-report`. Creates a project, uploads SMILES, selects regions, runs each pipeline step deliberately. The five-step layout serves this flow perfectly — they know what they want and move through it systematically.

```
/ind-report → New Project → upload SMILES → run pipeline → sign → download
```

### Entry B — Spontaneous (starts in chat, discovers the product)

Client is already working in the BioMate chat. They type something like *"run ADMET on these compounds"* or *"screen my lead series for hERG and DILI"*. The workflow runs. Results appear in chat. At that moment, a chip appears beneath the ADMET results:

```
┌──────────────────────────────────────────────────────────────────┐
│  ✓ ADMET screening complete — 8/12 compounds passed all gates    │
│                                                                  │
│  [→ Generate IND §2.6 report from these results]                 │
└──────────────────────────────────────────────────────────────────┘
```

Clicking opens `/ind-report` with:
- Step 1 pre-filled from the chat session (molecule, target, indication inferred from conversation)
- Step 2 already complete (ADMET results imported from the workflow run)
- Step 3 auto-queued (PBPK dispatched automatically)
- Document panel already showing §2.6.1.3 and §2.6.4 generated from the ADMET data

The client went from "I want to screen my compounds" to "I have a draft IND §2.6" without ever planning to. This is the spontaneous discovery path.

**Chat triggers that should offer the IND chip:**
- `predict_admet_properties` workflow completes with ≥2 compounds
- `pbpk_simulation` workflow completes
- User asks about hERG / DILI / ADMET safety in the context of drug discovery
- User mentions "IND", "regulatory", "submission", "CTD" in chat

**Reverse path (IND → Chat):** From within the IND Report page, a link "Discuss in chat →" opens the main chat with the campaign context pre-loaded, so the client can ask questions about their specific results ("Why is BM-0042 flagged for DILI?").

---

## The End-to-End Journey

```
SMILES + target/indication
  → ADMET screening (BioMate workflow: predict_admet_properties)
  → PBPK qualification (BioMate workflow: pbpk_simulation)
  → Lead ranking (Bayesian optimizer)
  → IND document assembly (§2.6.1–§2.6.6)
  → Regulatory audit (35+ ICH/FDA/EMA checks)
  → Reviewer sign-off (21 CFR Part 11 eSig)
  → Frozen DOCX download
```

---

## What Has Changed Since the Pilot

The pilot UI (`/drug-discovery-cro`) was a proof-of-concept focused on the DMTA optimization loop with IND as one tab. The new product is inverted: **the IND document is the primary deliverable**, and the ADMET/PBPK workflows are the inputs that build it.

New capabilities the product UI must surface:
- **§2.6.4–§2.6.6** (Pharmacology, PK, and Toxicology Tabulated Summaries) — built, not in pilot UI
- **Multi-region output** (FDA / EMA / NMPA / PMDA) — supported, no UI
- **39-compound gold standard** validation with named reference compound comparison — no UI
- **Regulatory audit** with severity ratings (CRITICAL / MAJOR / MINOR) — viewer exists but buried in tab
- **Wet-lab data ingestion** (NDA PDFs, NTP GLP reports) — built, no UI at all
- **Reviewer credentials in eSig** (reviewer_title, reviewer_credentials, review_scope) — just added, no UI update yet
- **Document version history** (supersede after eSig freeze) — built, no UI
- **ADMET benchmark scores** (hERG AUROC 0.931, DILI 0.913, Ames 0.934 vs. TDC) — no UI

---

## Overall Layout

Three-column layout on desktop (≥1280px). No sidebar collapse. Permanent left nav.

```
┌──────┬──────────────────────────────────┬─────────────────────────┐
│      │                                  │                         │
│ LEFT │         CENTER                   │   RIGHT                 │
│ NAV  │         PIPELINE                 │   DOCUMENT              │
│      │                                  │   PANEL                 │
│ 220px│         ~600px                   │   ~460px                │
│      │                                  │                         │
└──────┴──────────────────────────────────┴─────────────────────────┘
```

**Left nav:** Project list + settings. Same projects across sessions (persistent).  
**Center:** The pipeline — 5 steps, each showing status and key outputs.  
**Right:** The live document panel — shows the assembled IND text, updating as each step completes.

On ≤1024px: right panel collapses to a "View Document" button that opens as a bottom sheet.

---

## Left Navigation Panel

```
BioMate IND
─────────────────────────────
+ New Project

  ● BM-0042 · EGFR · Oncology          ← active
    FDA · EMA · NMPA
    IND ready · signed 2026-05-04

  ○ BM-0031 · CDK4/6 · Breast Ca
    FDA only
    Draft · step 3/5

  ○ BM-0019 · KRAS G12C · NSCLC
    EMA · PMDA
    Signed 2026-04-21

─────────────────────────────
Settings
Billing
Help
```

**Project list items show:**
- Molecule name + target + indication (1-2 lines)
- Region badges (FDA / EMA / NMPA / PMDA as small colored chips)
- Status: "Step N/5", "IND ready", "Signed [date]", "Needs data"

**Status dot:** green = signed/complete, blue = in progress, amber = blocked/needs input, gray = not started.

---

## Center Panel — The Pipeline

Five numbered steps displayed as a vertical stack. Each step has: step number, title, status indicator, key output summary, and an expand/edit zone.

### Step 1 — Project Setup

```
① Project Setup                                              ✓ Complete
─────────────────────────────────────────────────────────────────────
  Molecule:    BM-0042
  Target:      EGFR (ErbB1)
  Indication:  Non-small cell lung cancer (NSCLC), first-line
  Sponsor:     Acme Therapeutics, Inc.

  Target regions:  [FDA] [EMA] [NMPA] [PMDA]

  Compounds:   12 SMILES uploaded    [Edit]
               Lead: CC(=O)Nc1ccc(Oc2ncnc3…
```

**Collapsed when complete.** Click to expand and edit. Editing re-triggers downstream steps with confirmation.

**Region selector:** FDA / EMA / NMPA / PMDA as toggleable chips. Each selected region adds its specific sections to the document. NMPA adds GLP declaration. PMDA adds ethnic bridging.

**SMILES input:** paste text area or CSV upload. Shows parsed count + invalid SMILES list inline.

---

### Step 2 — ADMET Screening

```
② ADMET Screening                                        ⟳ Running…
─────────────────────────────────────────────────────────────────────
  Workflow: predict_admet_properties (AWS Batch)
  12 compounds · 41 endpoints · hERG / DILI / Ames / PPBR / Caco-2…

  ████████████████░░░░  80%   ETA: ~45s

  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
  When complete: feeds §2.6.1.3 + §2.6.4
```

**When complete, step collapses to summary row:**

```
② ADMET Screening                                            ✓ 8/12 pass
─────────────────────────────────────────────────────────────────────
  Lead (BM-0042):  hERG ✓  DILI ✓  Ames ✓  Ro5 ✓   all clear
  Campaign:        8/12 passed all gates   4 flagged

  [View ADMET Table ↓]                          [Add wet-lab data]
```

**[View ADMET Table ↓] expands an inline table:**

```
  Compound     hERG IC50   hERG      DILI      Ames     logP  MW    Ro5
               (µM)        (risk)

  BM-0042      >30         ✓ clear   ✓ clear   ✓ clear  3.2   421   ✓
  BM-0031      0.08        ✗ flag    ✓ clear   ✓ clear  4.1   489   ✓
  BM-0019      12.4        ~ border  ✗ flag    ✓ clear  2.8   398   ✓
  BM-0054      >30         ✓ clear   ✓ clear   ✗ flag   5.8   612   ✗ MW
  …
```

Column headers tooltip to cite the guideline threshold (hERG: "Redfern 2003, ICH S7B — IC50 < 10 µM").  
Color: green ✓ / amber ~ / red ✗. Clicking any cell opens a side panel with the raw prediction score + model confidence + TDC benchmark context.

**[Add wet-lab data]** opens an upload panel:

```
  Enrich with measured data (optional)
  ─────────────────────────────────────────────────────────────
  Upload GLP assay results to override computational predictions.
  Measured values always take precedence.

  Supported formats:
  • NTP GLP Technical Report PDF  (auto-extracted)
  • FDA NDA nonclinical review PDF
  • CSV (compound_id, assay_type, value, units, source)

  [Upload PDF or CSV]
  
  Or link an existing NDA:   NDA # [_______]  [Fetch →]
```

**Model confidence badge** on the step header: shows the TDC benchmark scores (hERG AUROC 0.931 · DILI 0.913 · Ames 0.934) as a tooltip — "BioMate ADMET engine accuracy, validated on TDC scaffold test sets".

---

### Step 3 — PBPK Qualification

```
③ PBPK Qualification                                         ✓ EMA ✓ FDA
─────────────────────────────────────────────────────────────────────
  Model: One-compartment · Rodgers & Rowland · Well-stirred liver
  Reference set: 30 drugs · EMA/CHMP/EWP/37498/2011

  Cmax:  73.3% within 2-fold  (EMA criterion ≥67%) ✓
  AUC:  100.0% within 2-fold                        ✓

  Lead (BM-0042):
    f_u = 0.032   Vd = 0.91 L/kg   t½ = 8.4 h   F% = 61%

  [View qualification table ↓]              [Re-run with new params]
```

**Expand shows per-compound qualification table** with fold errors, colored by pass/fail.

The **EMA criterion badge** (green/red) is the most prominent element in this step — it's the regulatory gateway. If it fails, a red banner appears with a specific message: "EMA criterion NOT met. The §2.6.2 section will include a model limitation statement. Consider reviewing excluded compounds or updating clearance parameters."

**OSP Benchmark context** shown as a small footnote: "BioMate PBPK within-2-fold (73.3%) is within the OSP-approved range for EMA-accepted PBPK platforms (65–90%)."

---

### Step 4 — Lead Selection

```
④ Lead Selection                                             ✓ BM-0042 #1
─────────────────────────────────────────────────────────────────────
  Method: Gaussian Process · EHVI acquisition · Morgan fingerprints
  Evaluated: 12 compounds · 2 optimization rounds

  Rank  Compound  Score  hERG   DILI  Ames  Potency  AD
  ─────────────────────────────────────────────────────
    1   BM-0042   0.89   ✓      ✓     ✓     ●●●●○   in-domain
    2   BM-0031   0.71   ✗      ✓     ✓     ●●●○○   in-domain
    3   BM-0019   0.68   ~      ✗     ✓     ●●●○○   in-domain

  Applicability domain: 10/12 in-domain  2 OOD (flagged in §2.6.1.5)

  [View all 12 →]
```

**Potency column:** filled circle icons (●) for quick visual comparison. Click opens SMILES structure viewer (use RDKit.js / Kekule.js for 2D structure rendering).

**AD status:** "in-domain" (green) / "out-of-domain" (amber with flag). OOD compounds still included but flagged with a disclaimer in §2.6.1.5.

This step is **read-only** — it is populated by the Bayesian optimizer output. No user input needed here beyond the SMILES library already uploaded in Step 1.

---

### Step 5 — IND Document

```
⑤ IND Document                                          ✓ Ready to sign
─────────────────────────────────────────────────────────────────────
  Sections generated: §2.6.1.1–§2.6.1.6 · §2.6.2 · §2.6.3
                      §2.6.4 · §2.6.5 · §2.6.6

  Regulatory audit:   ✓ 0 CRITICAL  · ✓ 0 MAJOR  · 2 MINOR  · 4 INFO

  Regions:  [FDA ✓] [EMA ✓] [NMPA ✓] [PMDA ✓]

  Generated: 2026-05-04 18:41 UTC · 24,310 characters · DOCX ready

  [View Document →]   [Download DOCX ↓]   [Sign & Freeze →]
```

When audit has MAJOR findings, the Sign button is **amber with a warning** rather than disabled — the system allows signing with known findings (regulatory scientist's judgment call) but makes it explicit:

```
  ⚠ 1 MAJOR finding before signing
  → §2.6.1.2: PBPK interpretation lacks AFE direction comment
     [View →]  [Regenerate section →]
```

**[Regenerate section →]** regenerates just that section with the audit finding injected as a constraint (Phase 0 implementation already supports this via `audit_constraint` parameter).

**Document version:** If a previously signed version exists, a "Versions" chip shows: "v2 (current) · v1 signed 2026-05-01 [view]".

---

## Right Panel — Document Viewer

The right panel shows the assembled IND document live. It updates section by section as Steps 2–5 complete. It is always visible while working, not a modal.

```
┌─────────────────────────────────────────────────────────────────┐
│  CTD Module 2.6 — Nonclinical Written Summaries            v2  │
│  BM-0042 · Acme Therapeutics · NSCLC                           │
│  FDA · EMA · NMPA · PMDA   |   Generated 2026-05-04           │
│                                                                 │
│  [§2.6.1] [§2.6.2] [§2.6.3] [§2.6.4] [§2.6.5] [§2.6.6]     │
│  ─────────────────────────────────────────────────────────     │
│                                                                 │
│  § 2.6.1  Nonclinical Overview: Pharmacology                   │
│                                                                 │
│  § 2.6.1.1  Overview of Computational Methods                  │
│                                                                 │
│  The nonclinical pharmacology evaluation of BM-0042 was        │
│  conducted using an integrated computational CRO platform...    │
│                                                                 │
│  ┄ ┄ ┄ [2.6.1.2 — loading] ┄ ┄ ┄                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
│  Audit   ○ 0 CRITICAL  ○ 0 MAJOR  ⚠ 2 MINOR                   │
│  [View audit →]   [Download .md]  [Download .docx]  [Sign →]  │
└─────────────────────────────────────────────────────────────────┘
```

### Section tabs
`[§2.6.1] [§2.6.2] … [§2.6.6]` — clicking jumps to that section. Active tab has underline.

### Loading states
Sections not yet generated show a skeleton line: `┄ ┄ ┄ [§2.6.1.2 — awaiting PBPK results] ┄ ┄ ┄`. When a workflow completes, the skeleton is replaced with the real text (no page reload — SSE update).

### Audit inline annotations
When the audit finds a MAJOR issue in a section, that paragraph has a left amber border and a small ⚠ chip at the end of the affected sentence. Clicking the chip opens an inline tooltip explaining the finding and offering "Regenerate this section".

### Region switching
A small region selector at the top-right of the document panel:
```
[FDA ▾]
 FDA
 EMA
 NMPA
 PMDA
 All regions (combined)
```
Switching region re-renders region-specific blocks (GLP declaration, ethnic bridging, PBPK assumption table) inline. The document body that applies to all regions stays visible.

### Document footer (always at bottom of panel)
```
SHA-256: a3f9c2d1… · Generated by BioMate v1.0 · 2026-05-04 18:41 UTC
Model: Gemini 3 Flash (T=0.3) · ADMET-AI v2.0 · Requires human review
[Not yet signed]
```
After eSig: shows "Signed by: Dr. Jane Smith · Director, DMPK · Sig ID: 3f82a1…"

---

## Sign & Freeze Flow

Clicking **[Sign & Freeze →]** opens a full-screen overlay (not a small modal — this is a regulated action):

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Electronic Signature                             │
│                    21 CFR Part 11 §11.200                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Document                                                           │
│  ─────────────────────────────────────────────────────             │
│  BM-0042 · §2.6.1–§2.6.6 · v2 · 24,310 characters                 │
│  SHA-256: a3f9c2d1e8b4f72a...                                       │
│                                                                     │
│  Meaning of this signature                                          │
│  ─────────────────────────────────────────────────────             │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ I have reviewed and approve the BM-0042 IND §2.6.1–§2.6.6 │    │
│  │ nonclinical written summary package for submission to       │    │
│  │ FDA/EMA/NMPA/PMDA. This document represents my scientific  │    │
│  │ judgment and was generated using validated computational    │    │
│  │ methods per FDA/EMA AI Guidance (January 2026).            │    │
│  └────────────────────────────────────────────────────────────┘    │
│  This statement is permanently recorded and cannot be changed.      │
│                                                                     │
│  Reviewer credentials (recommended for IND actions)                 │
│  ─────────────────────────────────────────────────────             │
│  Title / Role       [Director, Computational Pharmacology      ]   │
│  Credentials        [PhD Pharmacology · 10 years IND experience]   │
│  Review scope       [§2.6.1–§2.6.6 nonclinical pharmacology   ]   │
│                     These are recorded in the frozen document.      │
│                                                                     │
│  6-digit authenticator code                                         │
│  ─────────────────────────────────────────────────────             │
│       [  ] [  ] [  ] [  ] [  ] [  ]   refreshes in 22s            │
│                                                                     │
│  [Cancel]                                 [Sign and freeze →]       │
└─────────────────────────────────────────────────────────────────────┘
```

**After successful signing:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                          ✓  Signed                                  │
│                                                                     │
│    Document frozen · SHA-256 locked · version v2                    │
│    Signed by: Dr. Jane Smith                                        │
│    Sig ID: 3f82a1cc…  ·  2026-05-04 18:44 UTC                      │
│                                                                     │
│    [Download DOCX]     [Download Audit Trail PDF]     [Close]       │
└─────────────────────────────────────────────────────────────────────┘
```

The document panel footer immediately updates to show the signed state. The [Sign →] button in Step 5 changes to "✓ Signed — [View]".

---

## Audit Trail Panel

Accessible via [View audit →] in the document panel footer. Opens as an overlay over the right panel only (center panel stays visible).

```
Regulatory Audit                          ○ 0 CRITICAL  ○ 0 MAJOR  ⚠ 2 MINOR

  All findings ▾         Sections ▾           Severity ▾

  [§2.6.2] MINOR   PBPK within-3-fold metric not reported
  Recommended: Include within-3-fold percentage as secondary metric per EMA guidance.
  [→ Jump to section]

  [§2.6.1.5] MINOR   Training set composition not documented
  Recommended: Explicitly document hat-matrix training set for ICH M4 compliance.
  [→ Jump to section]

  [§2.6.1.2] INFO    AFE < 1 indicates Cmax underprediction
  Note: Systematic underprediction (AFE=0.611) is acknowledged in §2.6.2 narrative.
  ✓ Already addressed

  [§2.6.3.2] INFO    DILI mechanistic tier not implemented
  Note: EMA DILI Tier 2 (reactive metabolite structural alerts) is not yet available.

  ─────────────────────────────────────────────────────────────────────
  Chain integrity:  ✓ Valid (42 records · last verified 2 min ago)
  [View full audit log →]   [Export PDF]
```

**Finding rows:** Each finding shows section, severity badge, description, recommendation. CRITICAL = red, MAJOR = amber, MINOR = yellow, INFO = gray.

**[→ Jump to section]** scrolls the document panel to the relevant paragraph and briefly highlights it.

**[View full audit log →]** opens the existing `DrugDiscoveryAuditViewer` component in a modal.

---

## Empty / Onboarding State

When a user has no projects:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│                         BioMate IND Report                               │
│                                                                          │
│    Generate a complete ICH M4 CTD Module 2.6 nonclinical                │
│    written summary in under 10 minutes.                                  │
│                                                                          │
│    ✓ §2.6.1–§2.6.6  ·  FDA · EMA · NMPA · PMDA                         │
│    ✓ ADMET · PBPK · Lead ranking  ·  Validated models                   │
│    ✓ 21 CFR Part 11 eSig · SHA-256 audit trail · DOCX                   │
│                                                                          │
│                    [Start with a compound →]                             │
│                                                                          │
│    ────────────────────────────────────────────────────                 │
│                                                                          │
│    Or try a reference compound:                                          │
│    [Ibuprofen (all-clear)]  [Terfenadine (hERG+)]  [Nitrofurantoin]     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

The reference compound buttons pre-fill the wizard with the 9 gold standard test compounds and immediately run the full pipeline — showing a live demo in ~2 minutes.

---

## Connection to BioMate Workflows (Critical Design Decision)

**This service must connect to BioMate's workflow execution engine.** This is the entire differentiator — BioMate is the only tool that generates §2.6.1 from computational pipeline outputs rather than requiring completed wet-lab reports.

### How the connection works

Each pipeline step dispatches a BioMate workflow via the existing chat/workflow engine:

| Step | BioMate Workflow | Workflow ID / Domain |
|------|-----------------|----------------------|
| Step 2 ADMET | `predict_admet_properties` | drug_discovery, Nextflow on AWS Batch |
| Step 3 PBPK | `pbpk_simulation` | drug_discovery, Nextflow |
| Step 4 Lead ranking | `bayesian_optimizer` internal | Python, not Nextflow |
| (Optional) Clinical | `clinical_trial_simulation` | drug_discovery |

**The IND Report page does NOT need to show the chat interface.** But it should show workflow status using the same SSE infrastructure that powers the chat workflow panel:
- The workflow is dispatched via `POST /api/drug-discovery/{id}/run-workflow`
- Status updates come via SSE: step completions, output files
- The pipeline step UI updates in real time as the Nextflow workflow progresses

### From the chat to IND Report (and back)

When a user is in the main BioMate chat and runs `predict_admet_properties` or `pbpk_simulation`, the results should be usable in the IND Report without re-running:

- Chat workflow results are stored in the campaign DB
- The IND Report detects existing results via `GET /api/drug-discovery/{id}/pk-summary`
- Steps show "Results available from workflow run [date] — [Use ↗]" instead of "Run"
- User can re-run or use the cached results

**"Start from chat" entry point:** In the main BioMate chat, after ADMET results are shown, a chip appears: "Generate IND document from these results → [Open IND Report]". This is the natural handoff from the chat to the structured report tool.

---

## Section Coverage Display

Show which sections are populated vs. need data, at a glance. This is important because §2.6.4–§2.6.6 depend on assay data beyond SMILES.

```
Document completeness
─────────────────────────────────────────────────────────────────────
§ 2.6.1  Nonclinical Overview: Pharmacology                  ● Full
  §2.6.1.1  Overview of Computational Methods                ● 
  §2.6.1.2  PBPK Model Qualification                         ●
  §2.6.1.3  ADMET Screening Results                          ●
  §2.6.1.4  Compound Prioritization                          ●
  §2.6.1.5  Applicability Domain Assessment                  ●
  §2.6.1.6  Audit Trail and Regulatory Traceability          ●
§ 2.6.2  Nonclinical Overview: Pharmacokinetics              ● Full
§ 2.6.3  Nonclinical Overview: Toxicology                    ● Full
§ 2.6.4  Pharmacology Tabulated Summary                      ● Full
§ 2.6.5  Pharmacokinetics Tabulated Summary                  ◑ Partial
           ⚠ CLint data not available — using predicted values
§ 2.6.6  Toxicology Tabulated Summary                        ◑ Partial
           ⚠ No GLP in vivo data — computational only, add wet-lab data

Legend:  ● Full  ◑ Partial (computational only)  ○ Not generated
```

`◑ Partial` means the section is present but uses predicted rather than measured values. The document is still valid for pre-IND use but would need wet-lab enrichment for a full Phase I IND.

---

## Version History

Accessible from the "v2" chip in the document panel header.

```
Document versions — BM-0042
─────────────────────────────────────────────────────────────────
  v2  Current  ·  Not yet signed  ·  Generated 2026-05-04 18:41
      SHA-256: a3f9c2d1…
      Sections: §2.6.1–§2.6.6  ·  NMPA + PMDA region added

  v1  Superseded  ·  Signed 2026-05-01 ·  Dr. Smith
      SHA-256: 7e3a11b2…  [frozen]
      Sections: §2.6.1–§2.6.3  ·  FDA + EMA only
      Sig ID: 8f2a3c…
      [Download v1 DOCX]
```

When a signed document exists, creating a new version shows a confirmation: "Creating v2 will supersede the signed v1. The v1 signature record and frozen hash are preserved in the audit trail."

---

## Design Notes for Claude Design

### Tone
Precise and authoritative — this is a regulated document service. No playful language. No decorative illustrations. Clean, dense, professional. Similar aesthetic to Notion's document editor crossed with a regulatory dossier tool.

### Typography
- Section headers: 15px medium (Inter)
- Body text in document panel: 14px regular — readable as a document, not a UI
- Monospace for SHA-256 hashes, Sig IDs, timestamps
- ICH section numbers (§2.6.1.2 etc.): always monospaced

### Key color usage
- FDA = blue chip  
- EMA = purple chip  
- NMPA = red chip  
- PMDA = orange chip  
- CRITICAL finding = red background  
- MAJOR = amber background  
- MINOR = yellow background  
- INFO = gray background  
- eSig overlay = dark backdrop (trust signal — this is a legal action)

### What NOT to do
- No wizard-style "Next → Next → Next" flow. The pipeline steps are all visible at once, collapsing as they complete. The user can see the whole journey.
- No modal-heavy design. Inline expand/collapse everywhere.
- Don't hide the document. It is the product. It should be visible at all times.
- Don't require the user to navigate away to run a workflow. Workflow dispatch is embedded in the step.
- No skeleton placeholders that never resolve. If a section is loading, show which workflow it's waiting on.

---

## API Endpoints Needed

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ind-report/projects` | List all user projects |
| POST | `/api/ind-report/projects` | Create project (compounds + metadata) |
| GET | `/api/ind-report/projects/:id` | Project state (all 5 steps status) |
| POST | `/api/ind-report/projects/:id/run/:step` | Dispatch step workflow |
| GET | `/api/ind-report/projects/:id/admet` | ADMET results table |
| GET | `/api/ind-report/projects/:id/pbpk` | PBPK qualification results |
| GET | `/api/ind-report/projects/:id/leads` | Ranked compound list |
| POST | `/api/ind-report/projects/:id/generate` | Trigger IND document generation |
| GET | `/api/ind-report/projects/:id/document` | Full document (sections + audit) |
| GET | `/api/ind-report/projects/:id/document/versions` | Version history |
| GET | `/api/ind-report/projects/:id/document/download?format=docx|md` | Download |
| POST | `/api/ind-report/projects/:id/wetlab` | Upload wet-lab data (PDF or CSV) |
| POST | `/api/ind-report/projects/:id/sign` | eSig sign + freeze |
| GET | `/api/ind-report/projects/:id/audit` | Audit findings + chain |
| GET | `/api/ind-report/events/:id` | SSE stream for pipeline step updates |

Most of these are thin wrappers over existing `/api/drug-discovery/*` endpoints. The IND Report page is a new UI surface on top of the existing backend.

---

# Appendix B — Customer Feedback Loop (added 2026-05-14)

The original spec covers what the customer *sees and downloads*. It does not cover what we *learn from them*. This appendix specifies the four feedback surfaces that turn every customer interaction into training signal for the v6/v7 LLM, checker rules, and citation corpus.

This is the single most important addition for product → model coupling. Without it, every revision a customer makes is thrown away and the model never improves from real use.

---

## B1. Why this matters

Every customer revision is one of four signal types:

| Customer action | Signal type | Where it goes |
|---|---|---|
| Edits a sentence in the draft (Document Viewer) | **DPO pair** — their version = chosen, ours = rejected | `data/regulatory_training/dpo/customer_pairs.jsonl` |
| Dismisses a checker finding ("doesn't apply here") | **Checker rule refinement candidate** | `data/regulatory_training/checker_feedback.jsonl` |
| Adds a citation we don't know | **Corpus extension** | `data/regulatory_training/citation_extensions.jsonl` → `ich_corpus.py` |
| Regenerates a section with a verbal instruction | **Prompt-tuning preference** | feeds back into the system-prompt vocabulary for that section type |

These four flows must all be captured automatically — never as a separate "give us feedback" form (those go unfilled).

---

## B2. Surface 1 — Edit-tracking (the DPO loop)

**Where:** Document Viewer (existing `regulatory-document-editor.tsx` TipTap surface).

**How it works:**
- Every paragraph in the generated document is wrapped in a stable identifier (`data-pid="2.6.6.repeat-dose-summary-7"`).
- TipTap's transaction stream captures every edit. On save (debounced 5s after last keystroke), the system computes a diff between original and edited paragraph.
- If the diff is non-trivial (>5 characters changed, not just whitespace), a **candidate DPO pair** is created:
  - `prompt` = the structured input that produced this paragraph
  - `chosen` = customer's edited version
  - `rejected` = our original version
- The pair is **not** sent for training automatically. It enters a review queue (visible only to BioMate's regulatory science team, not the customer).

**Visual element (small, unobtrusive):**

```
┌───────────────────────────────────────────────────────────────────┐
│  The NOAEL of 100 mg/kg/day was established in the 28-day repeat- │
│  dose rat study. ✎ edited 2 min ago — saved for model improvement │
└───────────────────────────────────────────────────────────────────┘
```

Just a small gray "✎ edited — saved for model improvement" hint. **Not** a popup, not a confirm dialog. The customer is editing their own document; the fact that we learn from it is a footnote.

**Opt-out:** Project Settings has one toggle: "Contribute edits to model improvement" (default ON for free tier, default OFF for paid tier — paid customers get explicit opt-in).

---

## B3. Surface 2 — Audit finding dismissal (the checker-rule loop)

**Where:** Audit Trail Panel + inline ⚠ annotations (both already in the original spec).

**How it works:**
- When a customer dismisses an audit finding (existing UI has "Dismiss" button), capture *why* with a quick reason picker. **One click, four options:**

```
Dismiss this finding because…
○ Not applicable to this product (e.g. topical → no hERG required)
○ Already addressed elsewhere in the document
○ Acceptable risk — documented in Discussion
○ Disagree with the rule (regulatory judgment)
```

- The dismissal + reason becomes a **checker false-positive candidate**. Stored with the full context: section type, the rule that fired, the document state at dismissal.
- BioMate's regulatory science team reviews dismissals weekly. Patterns (e.g. 12 customers all dismissed "missing hERG" on topical products) trigger a checker rule refinement (e.g. `phase_gating.py` adds a "topical route exempt from hERG" branch).

**Why this matters:** v6 phase_gating failed at 70% partly because it flagged hERG as universally required. A real customer would correctly dismiss that on a topical product. Without this capture, we'd never know to refine the rule.

---

## B4. Surface 3 — "Suggest a citation" (the corpus loop)

**Where:** Document Viewer — small `[+]` icon next to existing citations.

**How it works:**
- Customer notices a missing citation (e.g. NMPA-specific guideline we don't reference for a China-bound submission).
- Clicks `[+]` next to a citation; small inline form opens:

```
Suggest a citation
  Guideline ID:  [_______________________]  (e.g. CDE 化学药物非临床研究技术指导原则)
  Why it applies: [_______________________]
  [Add to document only]   [Also suggest for BioMate]
```

- "Add to document only" — inserts the citation in the customer's draft. Doesn't update the corpus.
- "Also suggest for BioMate" — same, plus a candidate row in `citation_extensions.jsonl` for review by regulatory science team. Approved suggestions become new entries in `_GUIDELINE_FILES` (ich_corpus.py) and the BM25 index is rebuilt.

**Why this is critical for China readiness:** NMPA / CDE technical guidelines are vast and we won't index them all upfront. Customer-driven discovery is how we close the long tail.

---

## B5. Surface 4 — "Regenerate with instruction" (the prompt-tuning loop)

**Where:** Section header — `[Regenerate ▾]` already in original spec; this adds a sub-option.

**How it works:**
- When customer clicks `[Regenerate this section]`, a small dropdown appears:

```
Regenerate §2.6.6.3 Genotoxicity
  ○ Regenerate as is
  ● Regenerate with instruction:
    [Use more conservative language about the Ames equivocal finding]
```

- The instruction is appended to the section's system prompt for that regeneration only.
- If the customer is satisfied with the regenerated version (no further edits within 60s), the (instruction, before, after) tuple is stored as a **prompt-tuning signal**. Aggregated patterns surface to the BioMate team as candidate system-prompt vocabulary additions.

**Why this matters:** the v6 model has fixed system prompts per section type. Customer instructions reveal which qualifiers, hedges, or framings are commonly missing. This is cheaper to act on than full retraining.

---

## B6. Customer-visible vs. internal data flow

The customer sees:
- Their own edit history (Version History panel — already in spec)
- The "edited" hint on paragraphs (B2)
- The dismissal reason picker (B3)
- The citation suggestion form (B4)
- The regenerate-with-instruction option (B5)

The customer does NOT see:
- The DPO pair queue
- Other customers' edits or dismissals
- The model retraining schedule
- Any analytics on aggregated feedback

This separation is critical for the paid tier, where customers may demand isolation of their edits from any shared model. Two implementation choices:

1. **Free tier:** edits feed into shared `customer_pairs.jsonl` (with PII stripped — drug names, study IDs replaced with placeholders)
2. **Paid tier:** edits feed into customer-specific `pairs_{org_id}.jsonl`, optionally used for per-customer fine-tunes (per-org LoRA adapters resolved by `_resolve_adapter_path` if present)

---

## B7. Per-customer fine-tuning (paid tier, optional)

When a paid customer has accumulated ≥200 high-quality edits over ≥3 projects, offer them a **personal adapter**:

- BioMate trains a customer-specific LoRA on top of v6 using their accumulated pairs
- Adapter is named `regulatory_llm_v6_{org_id}_lora` and stored privately
- `_resolve_adapter_path` checks for it via header `X-BioMate-Org-Id` and prefers it over the public v6
- Customer sees a small badge in the UI:

```
Active model: BioMate v6 — Customized for {Org Name}
```

**This is the moat.** Schrödinger can't offer this because their tools don't have a feedback loop. We can because every edit is a training pair by construction.

---

## B8. API endpoints added

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/ind-report/projects/:id/edit` | Capture paragraph edit (auto-called on save) |
| POST | `/api/ind-report/audit/:finding_id/dismiss` | Capture dismissal + reason |
| POST | `/api/ind-report/citations/suggest` | Customer citation suggestion |
| POST | `/api/ind-report/sections/:section_id/regenerate` | Now accepts `instruction` param |
| GET | `/api/regulatory/feedback/queue` | Internal — review queue for reg science team |
| GET | `/api/regulatory/active_adapter` | Returns adapter name (public v6 vs customer-specific) |

---

## B9. What this changes for Claude Design

In terms of visible UI surfaces, the additions are small:

1. **Paragraph "edited" hint** — gray italic suffix after edited paragraphs
2. **Dismissal reason picker** — 4-option inline modal when clicking "Dismiss" on audit findings
3. **Citation `[+]` icon** — inline next to existing citations
4. **Regenerate-with-instruction dropdown** — extend existing `[Regenerate ▾]` button
5. **Active-model badge** — small pill in header showing which adapter is serving (only shown if customer has a personal adapter)
6. **Settings toggle** — "Contribute edits to model improvement" in Project Settings

The implementation cost is moderate (TipTap diff capture + 4 endpoint additions). The product value is large — this is the loop that turns customer revisions into product moat.

---

## B10. What this changes for the v6/v7 pipeline (engineering side)

- `build_dpo_pairs.py` gains a third mode: `--mode customer-edits` that reads `customer_pairs.jsonl` (with PII stripping) and validates each pair against the relevant checker before adding to the DPO pool
- A weekly cron rebuilds the merged DPO pool: synthetic + rejection-sampled + customer-validated, then triggers v7+1 training
- Checker modules grow a `regulatory_science_overrides.yaml` consumed at module load, where dismissal-driven rule refinements live (so changes don't require code edits)
- `ich_corpus.py` reads `citation_extensions/` directory at startup and merges into BM25 index

The handoff doc (`docs/20260514_REGULATORY_LLM_IMPLEMENTATION_HANDOFF.md`) is updated to track these as v8+ work items.
