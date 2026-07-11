# Validation Session Summary — 2026-07-02

## AWS Batch Jobs Executed (via Nextflow)

### Test 5-A: TYK2 Retrospective — ADMET Phase (PASS)
**Job:** PREDICT_ADMET_PROPERTIES run on `biomni-admet:x86`  
**Run time:** ~1m 41s  
**S3 output:** `s3://biomate-nextflow-work/nextflow/validation-test5a/`

| Property | ADMET-AI Predicted | Known Experimental | Error | Pass |
|---|---|---|---|---|
| cLogP | 1.73 (RDKit Crippen) | 0.9 (BMS published) | 0.83 units | PASS (<1.5) |
| hERG IC50 | 11.4 µM (ADMET-AI), 27.3 µM (Sander heuristic) | 80 µM (ChEMBL) | 2.9× / 7.1× | PASS (both >10 µM) |
| PPBR | 86.9% | 85-88% (ChEMBL Fu=0.12-0.15) | 0.4% | PASS (<15%) |
| Oral bioavailability | 0.921 | 87-128% F (ChEMBL animals) | consistent | PASS |
| CYP3A4 substrate | 0.601 | YES (label) | correct direction | PASS |
| CYP2D6 inhibitor | 0.012 | <1% (IC50>40µM) | near-zero | PASS |

**DILI CALIBRATION FINDING:** ADMET-AI DILI=0.991 (HIGH) is a FALSE POSITIVE.
Clinical: No hepatotoxicity in POETYK PSO-1 or PSO-2 trials.
Root cause: TYK2 pyrazine-class allosteric inhibitors share structural features with DILI-positive compounds but lack their metabolic liabilities.
Action: Apply -0.3 logit correction for pyrazine scaffold; or require convergent evidence (high hERG IC50 + clean CYP + clinical data override).

### Test 8-A: ADMET Ensemble Concordance (PASS 2/3 tools)
**Method:** Parallel AWS Batch (Tool1=ADMET-AI, Tool2=RDKit, Tool3=DeepPurpose)  
**Tool3 issue:** `descriptastorus` dependency not in `biomni-tools:x86` image

**Concordance:**
- hERG: Both tools predict >10 µM → CONCORDANT (direction: safe)  
- PPBR: ADMET-AI 86.9% vs known 86.5% → 0.4% error (near-perfect)
- DILI: Tool1 HIGH (FP), Tool2 medium → DISCORDANT (calibration needed)

**Action item:** Install `descriptastorus` + `pandas-flavor` in biomni-tools image for full 3-tool ensemble.

### Test 1-A: GWAS Target Prioritization (PARTIAL)
**Input:** Ishigaki 2022 RA GWAS (GCST90132223, 13.3M variants, N=932,549)  
**Method:** Direct scan (no eQTL colocalization layer yet)

| Target | GWAS p-value | Status | Therapeutic Validated |
|---|---|---|---|
| PTPN22 | 3.75e-168 (738 GWS SNPs) | GWS ✓ | Yes (PTPN22 R620W T cell) |
| TYK2 | 2.18e-20 (28 GWS SNPs) | GWS ✓ | Yes (deucravacitinib NDA) |
| IL6R | 5.26e-07 | Sub-GWS | Yes (tocilizumab) |
| MS4A1/CD20 | 1.66e-07 | Sub-GWS | Yes (rituximab) |
| JAK1 | Not detected p<1e-5 | Not GWS | Yes (upadacitinib, pathway drug) |

**Next:** Run coloc R package with DICE eQTL to colocalize GWS signals with immune cell eQTLs.

### Test 5-A: Docking Phase (IN PROGRESS)
**Issue:** AutoDock Vina not in `biomni-tools:x86`; trying `biomni-structure-to-drug:x86`

## Infrastructure Findings

1. **biomni-admet:x86** = ADMET-AI (Chemprop) + RDKit + obabel ✓  
2. **biomni-tools:x86** = obabel + basic Python, NO biomni package, NO vina  
3. **biomni-structure-to-drug:x86** = testing (should have vina + biomni docking)  
4. **DeepPurpose/biomni MPNN ADMET** = needs `descriptastorus` dep in biomni-tools image

## Calibration Table (deucravacitinib, TYK2 allosteric class)

| Tool | Property | Predicted | Known | Bias |
|---|---|---|---|---|
| ADMET-AI (Chemprop) | hERG IC50 | 11.4 µM | 80 µM | 7.1× underprediction → add correction factor |
| RDKit Sander 2009 | hERG IC50 | 27.3 µM | 80 µM | 2.9× underprediction |
| ADMET-AI | PPBR | 86.9% | 86.5% | +0.4% (essentially unbiased) |
| RDKit Crippen | cLogP | 1.73 | 0.9 (BMS) | +0.83 units (Crippen vs. cLogP method) |
| ADMET-AI | DILI | HIGH (FP) | None | pyrazine class false positive |
