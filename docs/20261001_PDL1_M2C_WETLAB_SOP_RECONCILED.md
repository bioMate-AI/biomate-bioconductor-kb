# PD-L1 + M2c Cyclic-Peptide Wet-Lab SOP (reconciled) — Build → Test → Learn

**Version 2026-10-01.** Single executable wet-lab SOP for the **PD-L1 + PepGLAD-M2c** cyclic-peptide closed
loop (direction confirmed 2026-10-01). **Reconciles** the drafted IL-17A/permeability-first protocol
(`biomate-audit-fix/docs/20260826_WETLAB_PROCESSING_PROTOCOL_BILINGUAL.md`) with the PD-L1 RFQ + DBTL data-spec,
applying the review fixes. English authoritative; a Chinese CRO order block follows (§8).
**Companions:** `20260930_FIRSTINCLASS_TARGET_PEPTIDE_COLLAB_PROTOCOL.md` (§Appendix A = pre-registered success
criteria) · `20261001_GENSCRIPT_RFQ_PDL1_ROUND1.md` · `20261001_CRO_DBTL_LOOP_DATA_SPEC.md`.
Cost/vendor figures carried from the drafted cost model: `[PUB]` published, `[EST]` industry estimate.

## 0 · What changed vs the drafted protocol (the reconciliation)
| Item | Drafted (IL-17A, perm-first) | **This SOP (PD-L1, binding-first, M2c)** |
|---|---|---|
| Target | IL-17A (autoimmune) | **PD-L1** (catalog protein swap) |
| Round-1 peptides | permeability-optimized (1–3 N-methyl, D-aa) | **binding-first *plain* L-peptides** (N-methylation is a *later* round) |
| Purity / QC | >90%, HPLC+MS | **≥95%**, HPLC+MS+COA **+ net peptide content + counter-ion (acetate)** |
| Permeability | PAMPA on ALL round 1 | **deferred to confirmed binders** (not perm-optimized yet) |
| Binder success bar | KD ≤ 1 µM | **KD ≤ 10 µM** (realistic de-novo first bar; flat interface) |
| Loop retrains | the permeability *scorer* | **the M2c *generator* (DPO) + recalibrate predictors** |

## 1 · DESIGN (dry) — already done for round 1
M2c/BoltzGen → screened panel. **Freeze predictions per peptide** (iptm, MM-GBSA ΔG, permeability, cyclization,
aggregation) *before* the wet lab — the learning signal is predicted-vs-measured. Round-1 panel = the 10 PASS
(`results/pdl1_round1_CRO_order_SCREENED.csv`), rush-6 prioritized.

## 2 · BUILD — synthesis (SPPS)
- **Spec:** head-to-tail (backbone amide/lactam) cyclic, **no free termini/no cap**; **canonical L-aa only**
  (round 1); **≥95%**; **5 mg**; **acetate** (TFA→acetate exchange). Flag low-cyclization-yield sequences up
  front; add a turn-inducer if needed.
- **QC returned per peptide:** COA + RP-HPLC chromatogram + ESI-MS spectrum **(standard)** **+ net peptide
  content (AAA/nitrogen) + counter-ion content + solubility (water/PBS/DMSO)** *(add-ons — net content is
  required to set accurate SPR molar concentrations)*. Lyophilized, −20 °C desiccated.
- **Vendors:** **GenScript** (US-based entity; peptide synthesis in Zhenjiang CN → budget customs/shipping) or
  **GL Biochem (Shanghai)** — lowest price (~$8–12/aa >90%, amide cyclization ~$400–800) `[EST]`, email quote <24 h.
  US-only option if IP/logistics require domestic: CPC Scientific / Bachem / AnaSpec.
- **Cost drivers `[PUB]`:** cyclization $900–1,000; N-methyl $495/res US (~$100–300 CN); backbone the rest. Round-1
  plain L-peptides avoid the N-methyl/D-aa surcharges → cheapest round.

## 3 · TEST
### 3a Binding (primary this round) — SPR/BLI vs PD-L1
- **Assay:** SPR (Biacore 8K+) or BLI (Octet) — affinity **ranking → kinetics**. *(Adaptyv can't run supplied
  synthetic peptides — exclude.)*
- **Target protein:** catalog **recombinant human PD-L1 ECD/IgV, His-tagged or biotinylated, 100–200 µg**
  (~$500–1,000, commodity — covers the whole campaign; ng–µg per run).
- **Return per peptide:** ka, kd, **KD**, Rmax, Chi², **raw sensorgrams** — **for ALL incl. non-binders**.
### 3b Permeability (deferred — only on confirmed binders)
- **PAMPA** on confirmed binders (~$50–150/cmpd `[EST]`; Cyprotex/Eurofins) → **Caco-2** on PAMPA leaders
  (efflux/P-gp, ~$250–500/cmpd). Not run on non-binders. (The permeability flywheel re-engages once we have hits.)
### 3c Function (optional) — PD-1/PD-L1 competition (ELISA/HTRF) → % blockade / IC50 on binders.

## 4 · LEARN — loop closure (the moat)
Results CSV (+ raw traces) → auto-ingest → **(a) DPO-retrain the M2c generator** on measured binders > non-binders
/ tighter-KD > weaker / synthesizable > failed; **(b) recalibrate the predictors** (measured KD vs iptm/ΔG;
measured cyclization/purity vs predicted feasibility) → propose round 2. **Reuse the existing DBTL scaffolding**
(`cyclic_peptide_dbtl.py` + `dbtl_controller.py` BO policy; S3 scorers) — extend its ingest to drive the M2c
generator retrain, not only the permeability scorer.

## 5 · Pre-registered success criteria *(define "validated" before the data)*
| Gate | Round-1 success | Stretch |
|---|---|---|
| **Build** | ≥70% delivered ≥95% purity, MS ±1 Da, cyclization confirmed | ≥90% |
| **Binding** | **≥1 peptide, specific dose-dependent KD ≤ 10 µM** (1:1 fit, acceptable Chi²) | ≤1 µM / multiple |
| **Function** (opt) | ≥50% PD-1/PD-L1 blockade at ≤10 µM | IC50 ≤ 1 µM |
| **Learn** | 100% of outcomes (incl. failures + non-binders) ingested + **M2c retrained** + predicted-vs-measured calibration computed | measurable DockQ/ranking lift round-2 |
**Binding gate = drug-progress; Learn gate = platform-progress.** Round 1 succeeds on the **Learn gate even with
0 binders** (the proprietary assay data is the moat regardless). Honest: PD-L1 is a hard flat interface → µM is a
real first-round "it binds"; native peptide-71 ~7 nM is the aspiration, not the bar.

## 6 · Data-return format (what closes the loop)
One structured table (CSV/Excel) + raw files: **every peptide, every step, failures + non-binders included, no
pre-filter.** Per peptide: synth made/cyclized + **failure mode** · purity · measured mass · net content ·
solubility · SPR ka/kd/KD/Chi²/binder-call. Raw: HPLC chromatograms, MS spectra, SPR sensorgrams (exportable data).

## 7 · Cost & timeline (round-1 lean)
~**$15–25k** (synthesis 70–80% of it; plain L-peptides = cheapest). Binding adds the SPR line + ~$0.5–1k protein.
Timeline: synthesis ~2–4 wk (incl. shipping if CN) → SPR ~8+ days → **binding readout ~4–6 wk**; rush subset
(rush-6) faster. PAMPA/Caco-2 only after binders → no round-1 time cost.

## 8 · CRO 订单规格（中文，供在华 CRO 如吉尔生化/金斯瑞）
- **合成：** 10 条**首尾环化**多肽（骨架酰胺，C 端↔N 端，**无游离末端、不加帽**）；仅**天然 L-型氨基酸**（第一轮）；
  纯度 **≥95%**；每条 **5 mg**；**乙酸盐**（做 TFA→乙酸盐置换）。对预计环化收率低的序列请提前标注并建议改造。
- **到货质控（每条）：** COA + RP-HPLC 图谱 + ESI-MS 谱（标准）**＋ 净肽含量（氨基酸分析/氮含量）＋ 反离子含量
  ＋ 溶解性（水/PBS/DMSO）**。冻干，−20 ℃ 干燥保存。
- **结合测定：** SPR(Biacore)/BLI(Octet) 对**重组人 PD-L1**，先亲和力排序再动力学；**返回全部 10 条**（含不结合者）
  的 ka/kd/**KD**/Rmax/Chi² **及原始 sensorgram**。PD-L1 蛋白目录级 100–200 µg 即可覆盖整批。
- **交付格式：** 一张结构化结果表 + 原始谱图；**每条、每步、含失败与不结合者，不要预先筛除**——阴性与失败也是训练数据。
- **报价：** 分别给（A）仅合成、（B）合成+SPR 打包、（C）优先 6 条加急 的价格与到货周期（含运输/清关门到门时间）。

## 9 · Note on Track A (biospecimen) — separate SOP, one required fix
The PBMC→single-cell multi-omic track (drafted §A) is the **patient-stratification** data side — **orthogonal to
this peptide loop**, keep it as its own SOP. **Required fix before use:** add **batch-control design**
(randomize donors across 10x runs + a bridging/control sample or cell-hashing multiplex per batch) — the program's
#1 failure mode is batch confounding (~21–24× leakage in prior runs); the drafted SOP omits it.

## Change log
- 2026-10-01 — Created: reconciled the drafted IL-17A/perm-first wet-lab SOP to the PD-L1 + M2c binding-first
  direction; folded in RFQ QC add-ons + DBTL data-return format + pre-registered success criteria; deferred
  PAMPA to confirmed binders; loop now retrains the M2c generator; flagged Track A batch-control gap.
