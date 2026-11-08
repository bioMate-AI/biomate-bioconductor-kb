# Vision Baseline: Can an open ≤27B VLM read real BioMate visual outputs?

**Date:** 2026-10-08
**Author:** Yaoyun Zhang (xiaoni5122@gmail.com)
**Scope:** Small, honest baseline (n=8 real images × 3 models). Real images, cited sources, no fabricated model outputs — every answer below is pasted verbatim from the OpenRouter response.

---

## 1. Question

Can an **open, on-prem-deployable (≤27B) multimodal model** READ real BioMate visual outputs well enough to be the "findings-from-plots" eye of the product? We test the on-prem candidate base (`qwen/qwen3.8-27b`), a smaller VL model (`qwen/qwen3-vl-8b-instruct`), and an upper reference (`qwen/qwen3-vl-32b-instruct`).

**Hypothesis to test:** VLMs are decent on natural/clinical-ish images and WEAKEST on scientific plots (volcano/PCA/QC) — the exact thing BioMate needs.

**Verdict preview:** Hypothesis **partially REFUTED.** All three models are **good at _qualitative_ scientific-plot reasoning** (direction of change, which gene is most significant by name, QC pass/fail, "does it plateau", distribution shape, UI run-state). They break on **precise _quantitative_ readout off an axis** (an exact log2 fold-change was misread as +15/+20 when the true value is ~+4) and on **dense character OCR** (8-residue peptide strings got scrambled by the 27B/32B). The weakness is not "scientific plots" as a category — it is *reading numbers off pixels*.

---

## 2. Method

- **API:** OpenRouter chat/completions, images passed as base64 `data:` URLs in message content. Temperature 0.
- **Models:**
  | Model | Params | Type | OpenRouter prompt price |
  |---|---|---|---|
  | `qwen/qwen3.8-27b` | 27B | **reasoning** (emits hidden thinking tokens) | $0.425/M |
  | `qwen/qwen3-vl-8b-instruct` | 8B | instruct VL | $0.117/M |
  | `qwen/qwen3-vl-32b-instruct` | 32B | instruct VL (upper ref) | $0.104/M |
- **Grading:** I built the tasks, so I set the gold answer per task (stated below). Each cell marked **correct / partial / wrong**. Partial = core reading right but one checkable sub-answer wrong.
- **Operational gotcha found:** `qwen3.8-27b` is a *reasoning* model. At `max_tokens=700` it spent the whole budget on hidden reasoning and returned **empty content** on 2/8 images. Re-run at `max_tokens=3000` fixed it. **On-prem serving of this model must budget ≥2.5–3k output tokens or it silently returns nothing.**
- Runner + raw JSON: `scratchpad/vision_runner.py`, `scratchpad/vision_results.json` (session scratchpad).

---

## 3. Task set (image source + question + gold)

| # | Image source (real, cited) | Kind | Question (checkable) | Gold |
|---|---|---|---|---|
| T1 | `reference/claude_design/tutorials_v2_final/assets/live/_raw/deseq_dex_vs_untreated_volcano.png` (airway DESeq2, real tutorial asset) | sci plot | plot type+axes; bi/uni-directional; most-significant labeled gene + its log2FC; #significant | Volcano; X=log2FC, Y=−log10(p); **bidirectional**; **ENSG00000152583.12** (top, −log10p≈120) at log2FC **≈+4**; **1242** significant |
| T2 | `.../deseq_dex_vs_untreated_PCA.png` (same run) | sci plot | PC1 variance %; the two condition groups; does PC1 separate them, L vs R | PC1 **39%**; **untreated** vs **dexamethasone**; PC1 separates: untreated **left**, dex **right** |
| T3 | `reference/claude_design/webpage_design_v2/images/blog-ra-deseq2-volcano.png` (GSE89408 RA, BioMate DESeq2) | sci/clinical | gene most UP in non-responders; two genes DOWN; are top up-genes inflammatory | Up: **CXCL13** (top); Down: **PTPRC, CD45**; up-set = inflammatory (MMP3, IL6, CD68, STAT3, CXCL9, TNF) |
| T4 | `research/anti-virus/runs/manuscript_figures_v1/plan_a/FigA8_population_coverage_curve.png` (real run figure) | sci plot | coverage at 4 peptides; does 4→5 help; does Chile curve reach World 42.6% line | **≈36%**; **plateaued** (no gain 4→5); **No**, stays below 42.6% |
| T5 | `research/.../manuscript_figures_v1/plan_a/FigA4_multiqc_summary.png` (MultiQC, 2 panels) | QC dist | (a) low or high affinity holds the mass; (b) is length 8–12 uniform | (a) **LOW** (0.0–0.3); (b) **UNIFORM**, ≈0.20 each |
| T6 | `docs/20260817_data_ui_screenshots/21_report_qc.png` (real BioMate app screenshot) | natural/UI | workflow name; top-right status badge; QC-report message | "Bulk RNA-seq Differential Expression Analysis"; **FAILED**; "All quality gates passed / within acceptable ranges" |
| T7 | `/Users/kky/Desktop/business/bioconductor_screenshot/task_decomposition_example.jpg` (**user-supplied** cyclic-peptide report, Chinese) | natural/table | top-5 shortlisted peptides (rows 1–5); 3 components of the rank-sum | **VLNPALGN, VINPALGN, VLRPILGN, VLNPILGN, VINPILGN**; rank-sum of **CyclicMPNN score + avg permeability + developability penalty** |
| T8 | `research/anti-virus/runs/publication_20260528.../multiqc_full_gp/multiqc_plots/png/binding_affinity_distribution.png` (real MultiQC) | sci dist | score of tallest peak; count beyond 0.3; overall shape | Peak **≈0.22–0.25**; beyond 0.3 **≈0**; right-skewed/**bimodal** (minor peak ≈0.03, dominant ≈0.22), mass at low scores |

Mix: **5 scientific plots, 1 QC figure, 2 natural/UI (one the user's own screenshot).** No image was generated for this test — all are real repo/run assets or the user's screenshot. (An on-disk `umap_perturbation.png` was a `MOCK_PNG` placeholder and excluded; `i00-1-runs-dashboard.png` was a 404 page and excluded.)

---

## 4. Per-model results

Legend: ✅ correct · 🟡 partial · ❌ wrong

| Task | qwen3.8-27b | qwen3-vl-8b | qwen3-vl-32b |
|---|:---:|:---:|:---:|
| T1 volcano (airway) | ✅ | 🟡 | 🟡 |
| T2 PCA (airway) | ✅ | ✅ | ✅ |
| T3 volcano (RA, named genes) | ✅ | ✅ | ✅ |
| T4 coverage curve | ✅ | 🟡 | ✅ |
| T5 MultiQC (2-panel) | ✅ | ✅ | ✅ |
| T6 QC-report UI screenshot | ✅ | ✅ | ✅ |
| T7 peptide shortlist (user img) | 🟡 | ✅ | 🟡 |
| T8 affinity distribution | ✅ | ✅ | ✅ |
| **Correct / Partial / Wrong** | **7 / 1 / 0** | **6 / 2 / 0** | **6 / 2 / 0** |
| **Score (partial=0.5)** | **7.5 / 8** | **7.0 / 8** | **7.0 / 8** |

**No hard-wrong answers from any model** on this set — all failures were a single sub-field (a magnitude or a trend), never a misread of the whole plot.

---

## 5. Where they fail (failure analysis — the honest part)

### Failure A — precise numeric readout off an axis (the real scientific-plot weakness)
- **T1:** The most-significant gene (ENSG00000152583.12) sits at **log2FC ≈ +4**. The 27B read **"+3 to +4" (correct)**. The **8B said "≈ 20"** and the **32B said "≈ +15"** — both grossly wrong; they appear to have reported the x-axis *extent* / a far-right outlier instead of the labeled point's coordinate.
- **T4:** The 8B read the flat 4→5 segment as **"increases from ~35% to ~37%"** — i.e. it could not resolve a plateau from a small rise. The 27B and 32B both called it a plateau correctly.
- **Takeaway:** qualitative shape = reliable; *a number pulled off a pixel axis* = unreliable, especially for the smaller model. This is exactly the readout a findings sentence like "GENE X up 4-fold" depends on.

### Failure B — dense character OCR (8-residue peptide strings)
- **T7:** gold row-3 = **VLRPILGN**. The **8B got all 5 sequences exactly right.** The **27B scrambled #3 → VLRLPIGN**; the **32B scrambled #3 → VLRLPILGN and #4 → VLNPIPLGN** (inserted/duplicated residues). The ranking-basis (3 Chinese-labeled score components) was read correctly by **all three**.
- **Takeaway:** counter-intuitively the *small* VL model was the best OCR of dense monospace strings; the reasoning model "normalized" the string and corrupted it. Don't trust any of them for verbatim sequence/ID transcription — pull those from the underlying file.

### What did NOT fail (refutes the blanket hypothesis)
- **Direction / significance-by-name:** both volcanoes read correctly — bidirectional, top gene named, up vs down genes named (T1, T3). CXCL13-as-top-hit nailed by all three.
- **PCA separation** (T2), **QC pass/fail + uniform-vs-skewed** (T5), **distribution shape** (T8): all correct across all models.
- **UI state reading** (T6): all three nailed the FAILED-run-with-passing-QC-gates tension verbatim — the "natural image" was the easiest, as predicted.

---

## 6. Cost (OpenRouter, measured)

| Model | Cost / 8 images | ≈ per image |
|---|---|---|
| qwen/qwen3.8-27b (reasoning) | **$0.01510** | ~$0.0019 (reasoning tokens dominate) |
| qwen/qwen3-vl-8b-instruct | **$0.00191** | ~$0.00024 |
| qwen/qwen3-vl-32b-instruct | **$0.00149** | ~$0.00019 |
| **Total (final run)** | **$0.01851** | |

Add ~**$0.0036** wasted on the two empty 27B calls (700-token budget exhausted on reasoning) before the re-run → **grand total ≈ $0.022** for the whole baseline. The reasoning model is ~8–10× the cost of the instruct VLs per image because its hidden reasoning tokens are billed as completions.

---

## 7. Verdict

**Is an open ≤27B VLM usable off-the-shelf for BioMate findings-from-plots?**

**Yes for qualitative findings; no for precise quantitative readout — use it, but feed it the numbers.**

1. **Usable off-the-shelf, today, for:** direction of change, "which labeled gene/point is the standout," QC gate pass/fail, "uniform vs skewed," "plateau vs still rising (coarse)," distribution shape, and reading run-state/UI panels. On this n=8 set that is where ~90% of the value sits and all three models scored there. Cost is negligible (**<$0.0003/image for the 8B**). The 8B-instruct is the surprise value pick — competitive with the 32B and the best at OCR.

2. **NOT usable off-the-shelf for:** exact magnitudes read off an axis (fold-change, exact coverage %, coordinate values) and verbatim transcription of dense IDs/sequences. These are the two things that corrupt a "findings" sentence quantitatively.

3. **Recommended architecture (don't fine-tune first — route first):** BioMate almost always *has the underlying numbers* (the DESeq2 results table, the MultiQC JSON, the coverage CSV). The right design is **hybrid: the VLM narrates the plot qualitatively, but every number in the finding is pulled from the source table, not from the pixels.** This removes Failure A and Failure B entirely at zero training cost.

4. **If/when fine-tuning is warranted,** target the *narrow* gap, not "science plots" broadly: (a) **axis-value regression** — reading a labeled point's (x,y) coordinate against tick labels; (b) **plateau/slope discrimination** on line plots; (c) **dense monospace OCR** for IDs/sequences. A small SFT set of BioMate volcano/PCA/coverage plots with coordinate-labeled questions would plausibly close Failure A. The base to fine-tune is `qwen3.8-27b` (most accurate, got the volcano FC right) — but note its reasoning-token cost and the **≥3k output-token serving requirement** or it returns empty.

**Bottom line:** the open ≤27B VLM is good enough to be BioMate's plot-reading eye for *qualitative* findings right now; the quantitative gap is best closed by grounding numbers in the source data (architecture), with fine-tuning held in reserve for the narrow axis-readout / OCR failure modes.

---

### Appendix — representative verbatim model answers (no fabrication)

**T1 (volcano) — the quantitative split:**
- 27B: "ENSG00000152583.12 (highest Y… −log10 p ≈ 115–120); its log2FC is roughly **+3 to +4**… 1242 genes significant." ✅
- 8B: "ENSG00000152583.12; log2 fold change **≈ 20**." ❌ (magnitude)
- 32B: "ENSG00000152583.12, with a log2 fold change of approximately **+15**." ❌ (magnitude)

**T7 (peptide OCR) — small model wins:**
- 8B: "1. VLNPALGN 2. VINPALGN 3. **VLRPILGN** 4. VLNPILGN 5. VINPILGN" ✅ (all exact)
- 27B: "3. **VLRLPIGN**" 🟡 (scrambled) · 32B: "3. **VLRLPILGN** 4. **VLNPIPLGN**" 🟡 (scrambled)

**T4 (coverage) — plateau discrimination:**
- 8B: "(2) **Increases** (from ~35% to ~37%)" 🟡 (misread flat segment)
- 27B/32B: "**Plateaued** — no meaningful gain." ✅

Raw outputs for all 24 cells: `scratchpad/vision_results.json`.
