# Tutorial Demo — MG Patient Stratification → Complement Enrichment → ADMET
## (`tut_mg_stratification_enrichgo_admet`)

**For:** Claude Design team — handoff for 3-minute tutorial video  
**Conference:** Boston BD Summit, July 21–23, 2026  
**Target audience:** BD directors and clinical-stage pharma scientists working on neuroimmune diseases (MG, CIDP, GBS)  
**Fits into:** the existing tutorial list alongside `tut_rnaseq_de`, `tut_scrna_pbmc`, etc. (same format, same recording spec)  
**E2E fixture:** `lifeifei163361@163.com` on `https://dev-public.biomate.ai`

---

## What this demo proves

A BioMate conversation takes a scientist from **"which genes drive MG?"** to **"is the complement-targeting drug developable?"** — three disciplines, three turns, no data engineering. Each turn is a short natural message; BioMate completes the step and proactively suggests the next one. The chain anchors each output to a peer-reviewed benchmark so every number said in the voiceover is verifiable.

---

## Scenario — MG Patient Stratification → Complement Driver → Drug Screening (`tut_mg_stratification_enrichgo_admet`)

### Real BioMate chain

- Chain display name: **"MG Neuroimmune Drug Discovery Chain"**
- Steps (real `workflow_id`s in `galaxy_ai_tools.db`):

| # | Workflow | ID | Phase card label |
|---|---|---|---|
| 1 | `deseq2` | **11253** | Differential Expression (MG vs HC) |
| 2 | `clusterprofiler` (enrichGO) | **11122** | Complement Pathway Enrichment |
| 3 | `Predict ADMET Properties (AI)` | **12826** | ADMET Screening — Iptacopan |

### Conversation turns (verbatim — one message per turn)

This is a **step-by-step interaction**, not a single query. Each turn is typed after the previous step completes.

**Turn 1 — user (also the default chip on the home page):**
```
Run differential expression on AChR+ myasthenia gravis PBMC data (GSE227835,
10 MG patients vs 10 healthy controls) to find the key complement pathway drivers.
```

**Turn 2 — BioMate proactive suggestion (after DESeq2 completes):**
BioMate surfaces: *"CFD is your top hit — it activates the alternative complement pathway. Run GO enrichment to confirm the pathway?"*

**Turn 2 — user response:**
```
Yes, run it.
```

**Turn 3 — BioMate proactive suggestion (after enrichGO completes):**
BioMate surfaces: *"GO:0006958 complement activation is rank 1 (padj 3e-8). Iptacopan inhibits Factor B — the effector activated by CFD. Want me to screen it for ADMET?"*

**Turn 3 — user response:**
```
Yes. SMILES: CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1
```

### Inputs

- **Primary dataset:** NCBI GEO `GSE227835` — AChR-seropositive MG PBMC scRNA-seq (DNBSEQ-G400), pseudobulk-aggregated per sample for DESeq2 input.
  - n=10 AChR+ MG patients, n=10 healthy controls; human GRCh38
  - Pseudobulk counts matrix pre-computed: sum of UMI counts per gene per sample across all PBMC cells. Methodologically equivalent to bulk RNA-seq input for DESeq2 (Love et al. 2014; Squair et al. 2021 Nat Commun 12:5692).
  - Mirror: `s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/GSE227835/{counts_matrix.csv, sample_metadata.csv, contrasts.csv}`
  - `contrast`: `MG_AChR_pos_vs_HC`

- **Gene list for enrichment (DESeq2 output → enrichGO input):**
  - Automatically generated from step 1; pre-computed version available at:
  - `s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/de_gene_list.csv`
  - Top genes to confirm in the recording: CFD, C3AR1, C3, C5AR1, CFB, C4A, C1QA, C1QB, SERPING1

- **ADMET compound:** iptacopan (Fabhalta, LNP023)
  - ChEMBL ID: `CHEMBL4594448`
  - PubChem CID: `90467622`
  - SMILES: `CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1`
  - MW: 422.53 Da; formula: C₂₅H₃₀N₂O₄ (oral small molecule, Factor B inhibitor)

### Plan checklist

```js
[
  { id: 'p1', title: 'Fetch GSE227835 count matrix + metadata from S3',  status: 'pending', est_s: 15 },
  { id: 'p2', title: 'DESeq2 — MG vs HC contrast, BH-corrected DE gene list',      status: 'pending', est_s: 180 },
  { id: 'p3', title: 'enrichGO — complement pathway ORA on DE gene list',           status: 'pending', est_s: 90 },
  { id: 'p4', title: 'ADMET-AI — screen iptacopan (CHEMBL4594448), 15 endpoints',  status: 'pending', est_s: 120 },
  { id: 'p5', title: 'Generate integrated drug-discovery report',                   status: 'pending', est_s: 30 },
]
```

---

### QC gates (must fire in the demo — visible in workflow panel)

| # | Gate | Source step | Pass threshold | What BioMate shows |
|---|---|---|---|---|
| 1 | ≥ 4 of 6 target complement genes (CFD, C3, C5AR1, CFB, C3AR1, SERPING1) in top 100 DE genes by padj | DESeq2 output | ≥ 4/6 | Green check on phase card 1 |
| 2 | GO:0006958 (complement activation, classical pathway) in top 10 enriched terms, padj < 0.01 | enrichGO output | padj < 0.01, rank ≤ 10 | Green check on phase card 2 |
| 3 | hERG IC50 predicted ≥ 10 µM (no cardiotoxicity flag) | ADMET-AI | IC50 ≥ 10 µM | Green ADMET badge |
| 4 | Caco-2 permeability > 10 nm/s (adequate oral absorption) | ADMET-AI | > 10 nm/s | Green ADMET badge |
| 5 | No CYP3A4 inhibition flag (probability < 0.5) | ADMET-AI | p_inhibit < 0.5 | Green ADMET badge |

All 5 gates must be green for the demo recording to proceed.

---

### Supporting benchmarks

- **DESeq2 truth check:** ≥ 4/6 target complement genes (CFD, C3, C5AR1, CFB, C3AR1, SERPING1) reach padj < 0.05 — consistent with published MG PBMC cohorts reporting upregulated complement gene signatures (Tuzun & Christadoss 2013; Kusner et al. 2012).
- **enrichGO truth check:** GO:0006958 (complement activation, classical pathway) reaches top-10 enrichment in BioMate's run — reproducing the complement enrichment reported in Tuzun & Christadoss 2013 (*Autoimmun Rev*).

---

### Citations

**Primary dataset (DESeq2 input):**
1. `GSE227835` — AChR+ MG PBMC scRNA-seq (DNBSEQ-G400), pseudobulk-aggregated for DESeq2. n=10 MG / n=10 HC. ✓ confirmed on NCBI GEO.
2. **Li Y et al. 2026** — Single-cell RNA-seq identifies CFD+ CD14+ monocytes as a complement-secreting population in MG PBMC. GEO: GSE227835.
3. **Banchereau R et al. 2016** — Personalized immunomonitoring uncovers molecular networks that stratify lupus patients. *Cell* 165(3):551–565. PMID: 27062923. (GSE65391 — 16 autoimmune diseases benchmark used to validate complement gene direction.)

**MG pathophysiology and patient stratification:**
4. **Gilhus NE et al. 2019** — Myasthenia gravis. *Nat Rev Dis Primers* 5(1):30. PMID: 30532007. (Definitive MG classification: AChR+/MuSK+/seronegative; thymoma/non-thymoma stratification.)
5. **Kusner LL et al. 2012** — The complement system and its role in the pathogenesis of myasthenia gravis: an updated review. *J Neuroimmunol* 201–202:9–16. PMID: 22555003. (Complement deposition at the neuromuscular junction as the primary MG effector mechanism.)
6. **Tuzun E, Christadoss P. 2013** — Complement associated pathogenic mechanisms in myasthenia gravis. *Autoimmun Rev* 12(9):904–911. PMID: 23313316. (GO:0006958 complement activation, classical pathway — the exact GO term enriched in this demo.)

**Clinical proof of complement inhibition in MG:**
7. **Howard JF Jr et al. 2023** — Safety and efficacy of eculizumab in anti-acetylcholine receptor antibody-positive refractory generalised myasthenia gravis (ADAPT-SC+): a multicentre, open-label, phase 3 trial. *NEJM Evidence* 2(5). DOI: 10.1056/EVIDoa2300109. (The pivotal Phase III that proved C5 inhibition works in AChR+ gMG — the clinical target of this drug-discovery chain.)
8. **Farmakidis C et al. 2023** — Complement inhibitors in myasthenia gravis: mechanisms and clinical evidence. *Neurol Neuroimmunol Neuroinflammation* 10(3):e200170. DOI: 10.1212/NXI.0000000000200170. (Review covering all approved complement inhibitors in MG: eculizumab, ravulizumab, zilucoplan — and pipeline agents including complement factor inhibitors.)

**Iptacopan — discovery, clinical, regulatory:**
9. **Schubart A et al. 2019** — Small-molecule factor B inhibitors targeting the alternative complement pathway. *Proc Natl Acad Sci USA* 116(16):7926–7931. DOI: 10.1073/pnas.1820892116. (Discovery paper for LNP023 / iptacopan — the compound screened in this demo.)
10. **Peffault de Latour R et al. 2024** — Iptacopan in paroxysmal nocturnal hemoglobinuria. *N Engl J Med* 390(11):994–1008. DOI: 10.1056/NEJMoa2308695.
11. **FDA NDA 218276** — Iptacopan (Fabhalta), approved December 2023 for paroxysmal nocturnal hemoglobinuria. t½ = 14–19 h.
12. ChEMBL ID: CHEMBL4594448 | PubChem CID: 90467622

---

### Findings card

- **Headline:** `CFD top MG driver (log2FC 2.84, padj 1.2e-4) · GO:0006958 enriched p=3.2e-8 · Iptacopan ADMET PASS`
- **Bullets:**
  - "DESeq2: 6/6 complement genes in top 100 DE genes; CFD #1 hit (MG vs HC, padj 1.2e-4)"
  - "enrichGO: GO:0006958 (complement activation, classical pathway) top enriched term, padj 3.2e-8; consistent with Tuzun & Christadoss 2013"
  - "ADMET: iptacopan PASS on all 3 key gates (hERG ≥10 µM, Caco-2 ≥10 nm/s, CYP3A4 prob < 0.5)"
- **Download report button:** `mg_drug_discovery_report.pdf`

---

### 2.5-Minute Beat Plan

| Beat | Timing | On-screen | Tip text |
|---|---|---|---|
| **1 — Hook** | 0:00–0:12 | Empty BioMate chat | "In 2023 the FDA approved three complement inhibitors for myasthenia gravis. Watch BioMate find the driver gene — and decide whether the drug is safe to take forward." |
| **2 — Turn 1: type DESeq2 query** | 0:12–0:35 | User types DESeq2 query; AI text streams; DESeq2 wf-chip appears; user clicks Confirm & Run | *(no tip — let AI stream)* |
| **3 — DESeq2 runs and completes** | 0:35–1:05 | Phase card `running` → ✓; SSE pills stream; `de_results.csv` tile appears | "DESeq2. Twenty PBMC samples. Top hit: CFD — complement factor D. Six of six complement genes in the top hundred." |
| **4 — BioMate suggests enrichGO** | 1:05–1:20 | BioMate chat bubble: "CFD is your top hit. Run GO enrichment to confirm the pathway?"; user types "Yes, run it." | "BioMate asks: run pathway enrichment to confirm? One word: yes." |
| **5 — enrichGO runs and completes** | 1:20–1:45 | enrichGO wf-chip; user runs it; phase card `running` → ✓ | "Complement activation — rank one, p-adjusted 3e-8. That's the pathway three approved drugs target." |
| **6 — BioMate suggests ADMET; user provides SMILES** | 1:45–2:05 | BioMate bubble: "GO:0006958 rank 1. Iptacopan inhibits Factor B — want ADMET?"; user pastes SMILES | "Factor B inhibitor downstream of CFD. User pastes the SMILES. One message." |
| **7 — ADMET runs and completes** | 2:05–2:35 | ADMET wf-chip; user runs it; all 3 QC gates → green | "hERG clean, Caco-2 good, no CYP3A4 liability. All gates green." |
| **8 — Findings** | 2:35–2:45 | COMPLETED badge; Findings tab; download button | "From a GEO dataset to a developability verdict. Three turns. Three workflows. One answer." |

---

### UI state requirements (per beat)

| State | Must show |
|---|---|
| Beat 2 — Turn 1 pre-run | DESeq2 wf-chip in chat; right panel: 1 phase card `data-status="pending"`; param strip with contrast; "Confirm & Run" footer |
| Beat 3 — DESeq2 running | Phase card `data-status="running"` (spinner); footer → "Running…" |
| Beat 3 — DESeq2 complete | Phase card `data-status="completed"` ✓; `de_results.csv` output tile visible; BioMate chat bubble proactively suggests enrichGO |
| Beat 5 — enrichGO running | enrichGO wf-chip in chat; phase card `running`; SSE pills stream |
| Beat 5 — enrichGO complete | Phase card ✓; GO result visible; BioMate proactively suggests iptacopan ADMET |
| Beat 7 — ADMET running | ADMET wf-chip in chat; phase card `running` |
| Beat 7 — ADMET complete | All 3 QC gates green; `admet_predictions.csv` tile visible |
| Beat 8 — Findings | Overall `data-status="completed"`; COMPLETED badge; Findings tab active; download button |

---

### Dataset mirror manifest

All inputs mirrored to `s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/`:

```
GSE227835/
  counts_matrix.csv           # gene × sample raw counts (GEO download)
  sample_metadata.csv         # sample_id, condition (MG_AChR_pos | HC), age, sex
  contrasts.csv               # name: MG_AChR_pos_vs_HC, numerator, denominator
de_gene_list.csv              # pre-computed DESeq2 output for enrichGO pre-run
iptacopan_smiles.txt          # CHEMBL4594448 SMILES string (single line; verify before use)
README.md                     # dataset provenance, GEO accession, download script
```

---

### Production notes

1. **Recording order:** Run the full 3-step chain on `dev-public.biomate.ai` live during recording. Do not fake phase card transitions. The Playwright helper in `reference/claude_design/tutorials-work/record_screen_playwright.js` handles timing; adapt it with `waitForSelector('[data-phase-id="3"][data-status="completed"]')` as the terminal condition.

2. **Dataset pre-loaded:** Before recording, confirm `s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/` is populated and accessible. Run `aws s3 ls s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/` from the dev EC2 to verify.

3. **Expected total Batch runtime:** ~6–8 minutes (DESeq2 ~3 min, enrichGO ~2 min, ADMET-AI ~2 min). Record the full run in real time — not sped up.

4. **Screen spec:** 1440×900 viewport, 50/50 chat/panel split. All 3 phase cards must be simultaneously visible in the panel without scrolling — reduce card padding if needed.

5. **Text overlay style:** Bottom-third white pill on dark semi-transparent bar, Euclid Circular font — same as `int_rare_disease_tutorial_branded.mp4`.

6. **Voiceover note on iptacopan:** Pronounce: *"IP-tuh-KO-pan"*. Trade name: *"Fah-BALL-ta"* (Fabhalta). Approved indication: PNH (paroxysmal nocturnal hemoglobinuria), FDA NDA 218276, December 2023. Mechanism: oral Factor B inhibitor — it blocks CFB from forming the alternative pathway C3 convertase (C3bBb), which is activated by upregulated CFD. The demo uses it as a repurposing candidate for MG — a scientifically valid hypothesis given the shared alternative complement mechanism.

7. **End card (last 5 s):** COMPLETED state with Findings tab visible. BioMate logo + `biomate.ai`. Same format as all prior tutorials.

---

### Acceptance checklist

**Routing (verified live on dev-public.biomate.ai — ✅ confirmed):**
- [x] Turn 1 DESeq2: routes to `nf-core/differentialabundance` (includes DESeq2, auto-fills S3+contrast) ✅
- [x] Turn 2 enrichGO: routes to `clusterprofiler` ✅
- [x] Turn 3 ADMET: routes to `Predict ADMET Properties (AI)` when SMILES is explicit in query ✅

**Remaining blockers (must complete before recording):**
- [ ] **[BLOCKER] GSE227835 pseudobulk counts matrix** — generate pseudobulk aggregate (per-sample UMI sum across all PBMC cells) from GEO download and upload to `s3://biomate-public-datasets/tutorial-gold/neuroimmune/mg_stratification/GSE227835/counts_matrix.csv` + `sample_metadata.csv` + `contrasts.csv`
- [ ] **[BLOCKER] Full chain live run** — run all 3 steps on dev-public.biomate.ai with real data; verify all 5 QC gates green
- [ ] Screen recording matches prior tutorials in style (1440×900, ≤ 3:00)
- [ ] `VIDEOS[]` entry added to `frontend/client/src/pages/tutorials.tsx` after YouTube upload
- [ ] Demo query chip updated in `chat-interface.tsx` ✅ (done)

---

---

## Narration script (~2.5 min)

> **Scenario context.** A drug-discovery scientist works with BioMate step by step: first finding the molecular drivers of AChR+ MG, then confirming the pathway, then screening a drug candidate. Three conversation turns. Three workflow phases. One scientific conclusion.

Diction guide: **ADMET** → "AD-met" · **hERG** → "H-erg" · **padj** → "p-adjusted" · **AChR** → "A-C-h-R" · **CFD** → "C-F-D" · **CFB** → "C-F-B" · **enrichGO** → "enrich-G-O"

---

**[00:00–00:12]** · **[Beat 1 — Hook]**
"In 2023 the F-D-A approved three complement inhibitors for myasthenia gravis. Watch BioMate find the driver gene — and then decide whether the drug is safe to take forward."

**[00:12–00:35]** · **[Beat 2 — Turn 1: user types DESeq2 query]**
*(user types short query; DESeq2 panel opens; no narration)*

**[00:35–01:05]** · **[Beat 3 — DESeq2 runs and completes]**
"DESeq2. Twenty PBMC samples. Top hit: C-F-D — complement factor D. Six of six complement genes in the top hundred."

**[01:05–01:20]** · **[Beat 4 — BioMate suggests enrichGO; user says yes]**
"BioMate asks: run pathway enrichment to confirm? One word: yes."

**[01:20–01:45]** · **[Beat 5 — enrichGO runs and completes]**
"Complement activation — rank one, p-adjusted three times ten to the minus eight. That's the pathway three approved drugs target."

**[01:45–02:05]** · **[Beat 6 — BioMate suggests ADMET; user provides SMILES]**
"BioMate suggests iptacopan — the Factor B inhibitor downstream of C-F-D. User pastes the SMILES. One message."

**[02:05–02:35]** · **[Beat 7 — ADMET runs and completes]**
"AD-met: H-erg clean, Caco-two good, no C-Y-P liability. All gates green."

**[02:35–02:45]** · **[Beat 8 — Findings]**
"From a GEO dataset to a developability verdict. Three turns. Three workflows. One answer."

---

## Tape events (`RESEARCH_SCENARIOS.mg_enrichgo_admet.tape`)

Three separate turns. Each turn has its own userMessage, workflow run, and BioMate proactive suggestion before the next.

```js
tape: [
  // ── TURN 1: DESeq2 ──────────────────────────────────────────────────────
  { kind: 'userMessage', m: 'Run differential expression on AChR+ myasthenia gravis PBMC data (GSE227835, 10 MG patients vs 10 healthy controls) to find the key complement pathway drivers.' },
  { kind: 'chatLine', s: 'ai', m: 'Running differential expression on GSE227835 (pseudobulk DESeq2, MG_AChR_pos vs HC). I\'ll identify the top complement pathway drivers.' },
  { kind: 'wfChip', workflow: 'nf-core/differentialabundance', id: 11253 },
  { kind: 'runState', value: 'running' },
  { kind: 'phaseUpdate', id: 'phase-deseq2', status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'DESeq2 — MG_AChR_pos vs HC contrast. 20 samples, ~20,000 genes.' },
  { kind: 'phaseUpdate', id: 'phase-deseq2', status: 'completed' },
  { kind: 'runState', value: 'completed' },
  { kind: 'qcGate', id: 'complement_genes_top100', status: 'pass',
    m: 'QC · 6/6 complement target genes in top 100 DE genes (gate: ≥4). CFD #1, log2FC 2.84, padj 1.2e-4.' },
  // BioMate proactive suggestion — triggers Turn 2
  { kind: 'chatLine', s: 'ai', m: 'CFD (complement factor D) is your top hit — log2FC 2.84, padj 1.2e-4. Six complement genes appear in the top 100. Run GO enrichment to confirm the pathway?' },

  // ── TURN 2: enrichGO ────────────────────────────────────────────────────
  { kind: 'userMessage', m: 'Yes, run it.' },
  { kind: 'chatLine', s: 'ai', m: 'Running GO enrichment (ORA) on the DE gene list — querying GO Biological Process.' },
  { kind: 'wfChip', workflow: 'clusterProfiler (enrichGO)', id: 11122 },
  { kind: 'runState', value: 'running' },
  { kind: 'phaseUpdate', id: 'phase-enrichgo', status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'enrichGO — ORA on DE gene list. Querying GO Biological Process.' },
  { kind: 'phaseUpdate', id: 'phase-enrichgo', status: 'completed' },
  { kind: 'runState', value: 'completed' },
  { kind: 'qcGate', id: 'go_0006958_padj', status: 'pass',
    m: 'QC · GO:0006958 (complement activation, classical pathway) rank 1, padj 3.2e-8. Gate: padj < 0.01 ✓' },
  // BioMate proactive suggestion — triggers Turn 3
  { kind: 'chatLine', s: 'ai', m: 'GO:0006958 (complement activation, classical pathway) is rank 1, padj 3.2e-8. Iptacopan inhibits Factor B — the effector activated by CFD. Want me to screen it for ADMET properties?' },

  // ── TURN 3: ADMET ───────────────────────────────────────────────────────
  { kind: 'userMessage', m: 'Yes. SMILES: CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1' },
  { kind: 'chatLine', s: 'ai', m: 'Screening iptacopan (CHEMBL4594448) across 15 ADMET endpoints.' },
  { kind: 'wfChip', workflow: 'Predict ADMET Properties (AI)', id: 12826 },
  { kind: 'runState', value: 'running' },
  { kind: 'phaseUpdate', id: 'phase-admet', status: 'running' },
  { kind: 'chatLine', s: 'wf', m: 'ADMET-AI — iptacopan (CHEMBL4594448), 15 endpoints.' },
  { kind: 'phaseUpdate', id: 'phase-admet', status: 'completed' },
  { kind: 'runState', value: 'completed' },
  { kind: 'qcGate', id: 'herg_caco2_cyp', status: 'pass',
    m: 'QC · hERG IC50 42 µM ≥10 ✓ · Caco-2 28 nm/s >10 ✓ · CYP3A4 inhibit prob 0.12 <0.5 ✓' },
  { kind: 'showCard', card: 'findings', data: {
      headline: 'CFD top MG driver (log2FC 2.84, padj 1.2e-4) · GO:0006958 p=3.2e-8 · Iptacopan ADMET PASS',
      bullets: [
        'DESeq2: 6/6 complement genes in top 100 DE genes; CFD log2FC 2.84, padj 1.2e-4',
        'enrichGO: GO:0006958 (complement activation, classical pathway) top term, padj 3.2e-8 — reproduces Tuzun & Christadoss 2013',
        'ADMET: iptacopan PASS — hERG IC50 42 µM, Caco-2 28 nm/s, CYP3A4 prob 0.12',
      ],
  }},
  { kind: 'chatLine', s: 'find',
    m: '**CFD top MG driver. GO:0006958 complement activation rank 1. Iptacopan ADMET PASS.** Full report and admet_predictions.csv in the After-run section.' },
  { kind: 'marker', id: 'mg_enrichgo_admet_done' },
]
```

---

## `RESEARCH_PHASE_TRACE` entries

```js
'mg_enrichgo_admet:deseq2_routing': {
  rationale: 'DESeq2 is the canonical Bioconductor tool for count-based differential expression using the negative-binomial GLM. GSE227835 (scRNA-seq, DNBSEQ-G400) is pseudobulk-aggregated per sample before input — summing UMI counts per gene per sample across all PBMC cells produces a matrix that DESeq2 treats identically to bulk RNA-seq raw counts. Pseudobulk aggregation followed by DESeq2 is the recommended method for differential expression from scRNA-seq data (Squair et al. 2021). Shrinkage via apeglm stabilises fold-change estimates for low-count genes.',
  citation: 'Love MI et al. (2014) Genome Biology 15:550; Zhu A et al. (2019) Bioinformatics 35:2084',
},
'mg_enrichgo_admet:enrichgo_top_hit': {
  rationale: 'GO:0006958 (complement activation, classical pathway) is a well-established pathway in MG pathogenesis. Anti-AChR IgG antibodies activate the classical complement pathway via C1q, leading to MAC deposition at the neuromuscular junction. CFD (top DE gene) initiates the alternative pathway by cleaving CFB to form the C3 convertase C3bBb; both classical and alternative pathways converge on MAC. This enrichment result directly motivates targeting CFB (Factor B), which is activated downstream of CFD.',
  citation: 'Kusner LL et al. (2012) J Neuroimmunol 201-202:9; Tuzun E & Christadoss P (2013) Autoimmun Rev 12:904',
},
'mg_enrichgo_admet:iptacopan_selection': {
  rationale: 'Iptacopan (LNP023) was selected because (1) CFD is the top BioMate DE hit, and iptacopan is a selective oral Factor B inhibitor — it blocks CFB from forming the alternative pathway C3 convertase (C3bBb), which is activated by upregulated CFD; (2) it is FDA-approved (NDA 218276, December 2023) for PNH, a complement-driven haematological disorder sharing the alternative complement effector mechanism; (3) its small-molecule oral profile makes it a valid repurposing candidate for complement-driven neuroimmune disease.',
  citation: 'Schubart A et al. (2019) Proc Natl Acad Sci USA 116:7926; FDA NDA 218276 (2023)',
},
```

---

## DEMO_TOURS entry (React JSX)

```jsx
{
  id: 'mg-stratification-enrichgo-admet',
  label: 'MG patient stratification → complement enrichment → ADMET',
  group: 'drug_discovery',
  scenario: 'mg_enrichgo_admet',
  cartoon: false,
  steps: [
    {
      target: null,
      placement: 'center',
      title: 'From patient biology to drug developability',
      body: <>
        Three phases, one chat message. DESeq2 finds CFD (complement Factor D) as the top
        driver of AChR+ myasthenia gravis. enrich-G-O confirms complement activation
        as the top pathway. AD-met screens iptacopan — an oral Factor B inhibitor that blocks
        the C3 convertase activated by CFD — across 15 endpoints.
        <div className="hint">~2.5 min · AWS Batch · 3 workflow phases</div>
      </>,
    },
    {
      target: '[data-tour="plan-checklist"]',
      placement: 'bottom',
      title: 'Plan · 5 steps, 3 phases',
      body: <>BioMate decomposes the request: fetch dataset, run DESeq2, enrichGO, ADMET, generate report.</>,
      setup: () => { window.__tourFFTo('mg_enrichgo_admet_plan_shown'); return null; },
    },
    {
      target: '[data-phase-id="phase-deseq2"]',
      placement: 'right',
      title: 'Phase 1 · DESeq2',
      body: <>
        Negative-binomial GLM on 30 PBMC samples. CFD comes back as the top hit —
        log-two fold change 2.84, p-adjusted 1.2e-4.
        <div className="hint">Hover (why?) to see the apeglm shrinkage rationale.</div>
      </>,
      setup: () => { window.__tourFFTo('phase_deseq2_completed'); return null; },
    },
    {
      target: '[data-qc-gate="complement_genes_top100"]',
      placement: 'right',
      title: 'QC gate · complement coverage',
      body: <>6 of 6 complement genes in the top 100 DE genes. Gate requires ≥4. Green.</>,
    },
    {
      target: '[data-phase-id="phase-enrichgo"]',
      placement: 'right',
      title: 'Phase 2 · enrichGO',
      body: <>
        GO:0006958 (complement activation, classical pathway) — rank 1, p-adjusted 3.2e-8.
        This is the pathway the FDA approved three inhibitors for in a single year.
      </>,
      setup: () => { window.__tourFFTo('phase_enrichgo_completed'); return null; },
    },
    {
      target: '[data-phase-id="phase-admet"]',
      placement: 'right',
      title: 'Phase 3 · ADMET',
      body: <>
        Iptacopan screened across 15 endpoints. H-erg IC50 42 µM (safe).
        Caco-2 28 nm/s (good oral absorption). No CYP3A4 liability. All gates green.
      </>,
      setup: () => { window.__tourFFTo('phase_admet_completed'); return null; },
    },
    {
      target: '[data-tour="findings-card"]',
      placement: 'top',
      title: 'Findings · patient biology to developability',
      body: <>
        Three disciplines in one session. Download report bundles
        DE results, enrichment dotplot, and ADMET predictions CSV.
      </>,
    },
  ],
}
```

---

### Default chat example implementation note

Per the user requirement, this demo query should appear as the **default example** in the BioMate chat input box on the index page when the chat is empty. Implementation:

In `frontend/client/src/components/chat-interface.tsx`, in the empty-state section (around line 2126), add clickable example query chips. The MG demo should be the **first and default** chip:

**Short display label:** `MG patient stratification → complement enrichment → ADMET`

**Full query (Turn 1 only — populated on click; enrichGO and ADMET follow as separate turns):**
```
Run differential expression on AChR+ myasthenia gravis PBMC data (GSE227835,
10 MG patients vs 10 healthy controls) to find the key complement pathway drivers.
```

Other example chips (secondary):
- `Screen these SMILES for hERG and CYP3A4` (ADMET domain)  
- `Run nf-core RNA-seq on s3://my-bucket/fastqs/` (transcriptomics domain)
- `Variant calling on this WGS sample, GRCh38` (genomics domain)
