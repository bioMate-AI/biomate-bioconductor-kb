# SYSUCC demo cases: standalone open LLMs vs BioMate deterministic services

Run: 2026-10-30T22:55:07Z → 2026-10-31T01:56:11Z (UTC). Raw data: [`docs/qa/20261030-open-llm-comparison.json`](qa/20261030-open-llm-comparison.json). Harness: [`scripts/compare_open_llm_sysucc.py`](../scripts/compare_open_llm_sysucc.py).

**Illustrative, not statistically established.** Each cell is at most 3 repeats on one synthetic fixture per task. Fixtures are synthetic software fixtures, not hospital or experimental data.

<!-- analyst:start -->
## Analyst interpretation (written 2026-10-30 after auditing this run)

### Bottom line

On these small, clean synthetic tasks, standalone open models, DeepSeek included, are **already good at reading and comparing files**. BioMate's current deterministic services **tie** them on candidate selection and report extraction. BioMate's demonstrated advantage in this run is narrower:

1. **Deterministic data-quality gates (T4).** BioMate rejected all three planted errors and produced the exact safe-row set. Bare models caught the mg/mL unit problem in only 9 of 15 runs and never produced the exact safe-row set (0/15).
2. **Reliability.** None of the 16 truncated runs or the wrong-route numeric answers below can happen in a deterministic service.
3. **Grounding.** Every grounded run was fully correct (24/24). On the same six tasks, bare runs were fully correct 59/72 times. Almost all of that difference is T4.

The case where a standalone model is weakest, numeric NCA (T2), is exactly the case **BioMate did not execute here**: its NCA is an R/PKNCA workflow that was not run. No BioMate claim is made for T2.

### Pooled results (bare = 4 models × 3 repeats; BioMate scored against the current post-fix code)

| Task | Bare: fully-correct runs | DeepSeek, reasoning forced on | BioMate deterministic | Grounded: fully-correct runs | Verdict for BioMate |
|---|---|---|---|---|---|
| T1a two-file selection | 12/12 | 3/3 | 1/1 (7/7 fields) | 4/4 | tie |
| T1b incomplete candidate D | 12/12 | 3/3 | 1/1 (was 8/10 pre-fix) | 4/4 | tie |
| T2a NCA, mg/L | 2/12 | 1/3 | not executed | not run | **not measured** |
| T2b NCA, ng/mL unit trap | 8/12 | 2/3 | not executed | not run | **not measured** |
| T3a report extraction | 11/12 | 3/3 | 1/1 (was 8/15 pre-fix) | 4/4 | tie |
| T3b predicted-only text | 12/12 | 3/3 | 1/1 | 4/4 | tie |
| T4 planted data errors | 0/12 (8/12 caught all three errors) | 0/3 (1/3 caught all three) | 1/1 (was 2/5 pre-fix) | 4/4 | **BioMate wins** |
| T5 corrected resubmission | 12/12 | 3/3 | 1/1 | 4/4 | tie |

### Most persuasive bare-model failures (exact values)

1. **Same DeepSeek slug, three different wrong half-lives (T2a).** The data halve exactly every 4 h. When OpenRouter routed `deepseek/deepseek-v4-pro-0813` to the provider Ionstream, it answered without reasoning (0 reasoning tokens, about 1 s) and returned `"t_half_h": 3.0, "auc_inf": 4.38012`, then `"t_half_h": 6.0, "auc_inf": 5.1353`, then `"t_half_h": 2.0, "auc_inf": 4.0451`, all at temperature 0. The reference is 4 h and 5.7708 mg·h/L. With reasoning on, from other providers, the same model was exact. **A DeepSeek deployment's thinking configuration decides which behaviour the hospital gets.**
2. **No answer at all on NCA (T2).** Qwen3.8-Max used its full 16,000-token budget on reasoning and returned no content in 6 of 6 NCA runs, taking about 340–360 s each. Kimi K3 did the same in 3 of 3 T2a runs. Overall, 16 of 144 calls were truncated this way.
3. **An mg/mL IC50 accepted as safe to ingest (T4).** Qwen3.8-Max runs 2 and 3 returned `"rows_safe_to_ingest": [2, 4, 7]`, where line 4 is `P3,CCCN,IC50,0.004,mg/mL`. DeepSeek run 1 returned `[2, 4, 5, 7]`. A reasoning-forced DeepSeek run returned `[1, 2, 4, 5, 7]`, which includes the CSV header line. BioMate rejected line 4 with `unsupported unit 'mg/mL' for IC50`.
4. **Conflicting identity half-resolved (T4).** Every bare run that answered flagged P4 (ethanol vs benzene). However, 9 of 11 answering runs still marked the ethanol row (line 5) as safe to ingest, silently picking one structure. BioMate rejected both rows: `compound_id 'P4' is given conflicting structures in this file (CCO, c1ccccc1 …) Row rejected.` Treat this as a judgement-call field: a reviewer could accept line 5 once the identity is resolved.
5. **Truncation on a trivial extraction.** One GLM-5.2 run spent 16,000 reasoning tokens on the 12-line study report and returned nothing. The other GLM runs did it in 302 and 834 tokens.

### Where BioMate failed, tied, or was not measured

- **Ties (T1a, T1b, T3a, T5).** The bare models were already at or near 100%. There is no accuracy advantage to show on these tasks with clean, tiny inputs.
- **T3b is a tie (corrected).** The first pass scored BioMate 1/2 because the harness adapter read only the measured fields. The fixed `WetLabReportIngester` keeps the value in `predicted_values.t_half_h` as `{value: 8.0, unit: h, source: predicted_computational, confidence: LOW}` and records no measured values. That is the correct behaviour. After the adapter was fixed to read `predicted_values`, re-scoring with no new LLM calls gave 2/2. Every bare model also labelled it "predicted", so this task is a tie.
- **Pre-fix BioMate was worse than the bare models.** A dry run against the code as it stood at about 22:45Z, before the other agents' fixes landed (not stored in the JSON), showed these failures:
  - T1b 0.80: D ranked first with `combined_score: 1` and no warning.
  - T3a 0.53: species defaulted to human; Cmax and AUC dropped; `glp_certified: true`; `Micronucleus: negative.` not extracted.
  - T3b 0/2: predicted text stored as `measured_wetlab`, confidence HIGH.
  - T4 0.40: negative IC50 accepted and persisted; identity conflict not flagged.

  All LLM calls and all grounded prompts used the post-fix code. The source hashes were unchanged from 23:16Z to the end of the LLM calls at 23:37Z, with `assay_ingestion.py` at `6861696e…`. By the final re-score, `assay_ingestion.py` had changed again to `2cc7589c…`, and the BioMate scores were identical. The JSON records both: `rescored.llm_run_local_source_hashes` and `local_source_hashes`. **Do not show the hospital BioMate results from older builds.**
- **T1 "selection" is ranking, not criteria.** The assay service has no user-threshold parameter (for example, IC50 ≤ 10 nM). It matched the reference because its combined score orders B first and now demotes incomplete compounds. Arbitrary user criteria are not yet a service capability.
- **T2 not measured.** The obvious place for BioMate to win, deterministic PKNCA, needs the indexed R workflow to run against these references before any claim is made.

### Scorer disclosures

- After the first pass, two T4 rules were corrected and applied equally to all configurations:
  - "must be > 0 … got -0.005" now counts as detecting the negative value.
  - Coverage notes ("P1 is incompletely evaluated: missing safety") are not counted as false data-error claims.
  - No LLM run's score changed. The BioMate T4 score went from 0.6 to 1.0. Both the original and the re-scored scores are kept in the JSON (`score_before_rescore`).
- Prompts fully specify the NCA method and the selection thresholds, so this measures execution fidelity, not method choice.
- Grounded runs saw *correct* post-fix BioMate outputs. Whether a model would catch *wrong* tool output was not tested.

### Spend

144 scored calls, plus 4 pilot calls ($0.31), plus HTTP-402 in-flight-budget rejections, which were not billed and were re-issued. Provider-reported total ≈ **$3.39**. By model: Kimi K3 $1.14, Qwen3.8-Max $0.90, DeepSeek $0.72, GLM-5.2 $0.32 (pilot excluded).
<!-- analyst:end -->

# Generated results

## Configurations

- **bare** — open model via OpenRouter chat completions, prompt + inline file text only, no tools and **no code execution**. This is the *standalone open model* configuration; a code-enabled agent built on the same model might do better, and was not tested.
- **biomate** — BioMate's current local Python services on the same inputs, no LLM. These services are being fixed concurrently; results reflect the source hashes in the JSON.
- **grounded** — the same open model given the raw files *plus* BioMate's service outputs (platform ablation). Not run for T2 (no BioMate output). Repeats: bare 3, grounded 1 per model per task.

Models: `deepseek/deepseek-v4-pro-0813`, `qwen/qwen3.8-max-0902`, `z-ai/glm-5.2`, `moonshotai/kimi-k3`. Settings: temperature 0, max_tokens 16000, provider-default reasoning, JSON requested in the prompt.

Spend: 144 LLM calls, 78,257 prompt + 519,452 completion tokens (incl. 463,664 reasoning), provider-reported cost $3.076.

## Scores (mean field-level fraction; fully-correct runs / scored runs)

| Task | BioMate det. | bare DeepSeek V4-pro (0813) | bare Qwen3.8-Max (0902) | bare GLM-5.2 | bare Kimi K3 | bare_reasoning DeepSeek V4-pro (0813) | grounded DeepSeek V4-pro (0813) | grounded Qwen3.8-Max (0902) | grounded GLM-5.2 | grounded Kimi K3 |
|---|---|---|---|---|---|---|---|---|---|---|
| T1a_two_file_selection | 1.00 (1/1) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |
| T1b_incomplete_candidate | 1.00 (1/1) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |
| T2a_nca_mg_per_L | not_executed_locally | 0.19 (0/3) | 0.00 (0/3) | 0.67 (2/3) | 0.00 (0/3) | 0.33 (1/3) | — | — | — | — |
| T2b_nca_unit_trap_ng_per_mL | not_executed_locally | 0.67 (2/3) | 0.00 (0/3) | 1.00 (3/3) | 1.00 (3/3) | 0.67 (2/3) | — | — | — | — |
| T3a_report_extraction | 1.00 (1/1) | 1.00 (3/3) | 1.00 (3/3) | 0.69 (2/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |
| T3b_predicted_not_measured | 1.00 (1/1) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |
| T4_planted_data_errors | 1.00 (1/1) | 0.73 (0/3) | 0.47 (0/3) | 0.80 (0/3) | 0.80 (0/3) | 0.67 (0/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |
| T5_corrected_resubmission | 1.00 (1/1) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (3/3) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) | 1.00 (1/1) |

Cells: mean field fraction (fully-correct runs / scored runs). Unparseable or truncated output (e.g. reasoning exhausted the 16k-token budget) scores 0 and is counted, not dropped.

Field denominators per run: T1a_two_file_selection = 7, T1b_incomplete_candidate = 10, T2a_nca_mg_per_L = 7, T2b_nca_unit_trap_ng_per_mL = 7, T3a_report_extraction = 15, T3b_predicted_not_measured = 2, T4_planted_data_errors = 5, T5_corrected_resubmission = 12.

## Per-task verdict (rule-based)

Rule: compare BioMate deterministic field fraction with the pooled bare-model mean; difference > +0.10 = BioMate wins, < −0.10 = BioMate loses, otherwise tie. Same rule for grounded vs bare.

| Task | BioMate det. | bare pooled mean | best bare model | BioMate vs bare | DeepSeek reasoning-forced mean | grounded pooled mean | grounded vs bare |
|---|---|---|---|---|---|---|---|
| T1a_two_file_selection | 1.0 | 1.0 | Qwen3.8-Max (0902) 1.00 | tie | 1.0 | 1.0 | tie |
| T1b_incomplete_candidate | 1.0 | 1.0 | Qwen3.8-Max (0902) 1.00 | tie | 1.0 | 1.0 | tie |
| T2a_nca_mg_per_L | not_executed_locally | 0.214 | GLM-5.2 0.67 | n/a | 0.333 | None | n/a |
| T2b_nca_unit_trap_ng_per_mL | not_executed_locally | 0.667 | Kimi K3 1.00 | n/a | 0.667 | None | n/a |
| T3a_report_extraction | 1.0 | 0.922 | Qwen3.8-Max (0902) 1.00 | tie | 1.0 | 1.0 | tie |
| T3b_predicted_not_measured | 1.0 | 1.0 | Qwen3.8-Max (0902) 1.00 | tie | 1.0 | 1.0 | tie |
| T4_planted_data_errors | 1.0 | 0.7 | Kimi K3 0.80 | BioMate wins | 0.667 | 1.0 | grounded wins |
| T5_corrected_resubmission | 1.0 | 1.0 | Qwen3.8-Max (0902) 1.00 | tie | 1.0 | 1.0 | tie |

## Provider routing and reasoning (per run)

OpenRouter chooses a provider per request unless pinned. `prov(reasoning tokens)` per repeat:

| Config | Task | Model | runs |
|---|---|---|---|
| bare | T1a_two_file_selection | GLM-5.2 | Parasail(164), Parasail(163), Parasail(256) |
| bare | T1a_two_file_selection | DeepSeek V4-pro (0813) | CoreWeave(351), CoreWeave(325), CoreWeave(314) |
| bare | T1a_two_file_selection | Kimi K3 | InferenceNet(317), InferenceNet(309), InferenceNet(309) |
| bare | T1a_two_file_selection | Qwen3.8-Max (0902) | Alibaba(633), Alibaba(535), Alibaba(413) |
| bare | T1b_incomplete_candidate | DeepSeek V4-pro (0813) | Wafer(788), Wafer(763), Wafer(435) |
| bare | T1b_incomplete_candidate | GLM-5.2 | CoreWeave(348), CoreWeave(393), CoreWeave(500) |
| bare | T1b_incomplete_candidate | Kimi K3 | InferenceNet(439), InferenceNet(350), InferenceNet(571) |
| bare | T1b_incomplete_candidate | Qwen3.8-Max (0902) | Alibaba(860), Alibaba(661), Alibaba(709) |
| bare | T2a_nca_mg_per_L | DeepSeek V4-pro (0813) | Ionstream(0), Ionstream(0), Ionstream(0) |
| bare | T2a_nca_mg_per_L | GLM-5.2 | CoreWeave(16000, truncated), CoreWeave(3272), CoreWeave(12097) |
| bare | T2a_nca_mg_per_L | Kimi K3 | InferenceNet(16001, truncated), InferenceNet(16000, truncated), InferenceNet(16002, truncated) |
| bare | T2a_nca_mg_per_L | Qwen3.8-Max (0902) | Alibaba(16000, truncated), Alibaba(16000, truncated), Alibaba(16000, truncated) |
| bare | T2b_nca_unit_trap_ng_per_mL | DeepSeek V4-pro (0813) | CoreWeave(9404), CoreWeave(16000, truncated), CoreWeave(4676) |
| bare | T2b_nca_unit_trap_ng_per_mL | Qwen3.8-Max (0902) | Alibaba(16000, truncated), Alibaba(16000, truncated), Alibaba(16000, truncated) |
| bare | T2b_nca_unit_trap_ng_per_mL | GLM-5.2 | Parasail(6853), Parasail(7022), Parasail(3995) |
| bare | T2b_nca_unit_trap_ng_per_mL | Kimi K3 | Wafer(12000), Wafer(0), Wafer(0) |
| bare | T3a_report_extraction | DeepSeek V4-pro (0813) | AtlasCloud(798), AtlasCloud(3092), AtlasCloud(882) |
| bare | T3a_report_extraction | Qwen3.8-Max (0902) | Alibaba(1335), Alibaba(1477), Alibaba(1837) |
| bare | T3a_report_extraction | GLM-5.2 | CoreWeave(302), CoreWeave(834), CoreWeave(16000, truncated) |
| bare | T3a_report_extraction | Kimi K3 | InferenceNet(743), InferenceNet(418), InferenceNet(546) |
| bare | T3b_predicted_not_measured | DeepSeek V4-pro (0813) | Wafer(60), Wafer(60), Wafer(55) |
| bare | T3b_predicted_not_measured | Qwen3.8-Max (0902) | Alibaba(84), Alibaba(98), Alibaba(107) |
| bare | T3b_predicted_not_measured | GLM-5.2 | CoreWeave(322), CoreWeave(271), CoreWeave(266) |
| bare | T3b_predicted_not_measured | Kimi K3 | Wafer(54), Wafer(54), Wafer(54) |
| bare | T4_planted_data_errors | DeepSeek V4-pro (0813) | CoreWeave(11655), CoreWeave(12154), CoreWeave(8019) |
| bare | T4_planted_data_errors | Qwen3.8-Max (0902) | Alibaba(16000, truncated), Alibaba(2460), Alibaba(4405) |
| bare | T4_planted_data_errors | GLM-5.2 | CoreWeave(283), CoreWeave(513), CoreWeave(272) |
| bare | T4_planted_data_errors | Kimi K3 | InferenceNet(1297), InferenceNet(1298), InferenceNet(1748) |
| bare | T5_corrected_resubmission | DeepSeek V4-pro (0813) | AtlasCloud(392), Together(577), AtlasCloud(971) |
| bare | T5_corrected_resubmission | Qwen3.8-Max (0902) | Alibaba(1060), Alibaba(948), Alibaba(562) |
| bare | T5_corrected_resubmission | GLM-5.2 | CoreWeave(1063), CoreWeave(301), CoreWeave(267) |
| bare | T5_corrected_resubmission | Kimi K3 | Wafer(252), Wafer(273), Wafer(800) |
| bare_reasoning | T1a_two_file_selection | DeepSeek V4-pro (0813) | CoreWeave(468), CoreWeave(301), CoreWeave(301) |
| bare_reasoning | T1b_incomplete_candidate | DeepSeek V4-pro (0813) | Wafer(575), Wafer(684), Wafer(739) |
| bare_reasoning | T2a_nca_mg_per_L | DeepSeek V4-pro (0813) | Ionstream(16003, truncated), Ionstream(16004, truncated), Ionstream(5446) |
| bare_reasoning | T2b_nca_unit_trap_ng_per_mL | DeepSeek V4-pro (0813) | CoreWeave(16000, truncated), CoreWeave(5983), CoreWeave(5119) |
| bare_reasoning | T3a_report_extraction | DeepSeek V4-pro (0813) | AtlasCloud(2453), AtlasCloud(1295), AtlasCloud(1103) |
| bare_reasoning | T4_planted_data_errors | DeepSeek V4-pro (0813) | CoreWeave(8110), CoreWeave(5039), CoreWeave(7805) |
| bare_reasoning | T5_corrected_resubmission | DeepSeek V4-pro (0813) | StreamLake(802), AtlasCloud(824), AtlasCloud(1077) |
| bare_reasoning | T3b_predicted_not_measured | DeepSeek V4-pro (0813) | Wafer(109), Wafer(52), Wafer(109) |
| grounded | T1a_two_file_selection | DeepSeek V4-pro (0813) | Alibaba(352) |
| grounded | T1a_two_file_selection | GLM-5.2 | CoreWeave(308) |
| grounded | T1a_two_file_selection | Kimi K3 | InferenceNet(368) |
| grounded | T1a_two_file_selection | Qwen3.8-Max (0902) | Alibaba(748) |
| grounded | T1b_incomplete_candidate | DeepSeek V4-pro (0813) | DekaLLM(0) |
| grounded | T1b_incomplete_candidate | GLM-5.2 | CoreWeave(470) |
| grounded | T1b_incomplete_candidate | Kimi K3 | Wafer(343) |
| grounded | T1b_incomplete_candidate | Qwen3.8-Max (0902) | Alibaba(528) |
| grounded | T3a_report_extraction | GLM-5.2 | CoreWeave(496) |
| grounded | T3a_report_extraction | Kimi K3 | InferenceNet(1145) |
| grounded | T3a_report_extraction | Qwen3.8-Max (0902) | Alibaba(3303) |
| grounded | T3a_report_extraction | DeepSeek V4-pro (0813) | AtlasCloud(7603) |
| grounded | T3b_predicted_not_measured | DeepSeek V4-pro (0813) | Novita(123) |
| grounded | T3b_predicted_not_measured | Qwen3.8-Max (0902) | Alibaba(327) |
| grounded | T3b_predicted_not_measured | GLM-5.2 | CoreWeave(42) |
| grounded | T3b_predicted_not_measured | Kimi K3 | Sail Research(121) |
| grounded | T4_planted_data_errors | DeepSeek V4-pro (0813) | Wafer(1212) |
| grounded | T4_planted_data_errors | GLM-5.2 | CoreWeave(470) |
| grounded | T4_planted_data_errors | Kimi K3 | Wafer(1561) |
| grounded | T4_planted_data_errors | Qwen3.8-Max (0902) | Alibaba(1992) |
| grounded | T5_corrected_resubmission | DeepSeek V4-pro (0813) | GMICloud(0) |
| grounded | T5_corrected_resubmission | GLM-5.2 | Parasail(259) |
| grounded | T5_corrected_resubmission | Kimi K3 | InferenceNet(921) |
| grounded | T5_corrected_resubmission | Qwen3.8-Max (0902) | Alibaba(1024) |

## Field failures (exact model values)

**T2a_nca_mg_per_L** — reference: `{"lambda_z_per_h": 0.1732867951399863, "t_half_h": 4.000000000000001, "c0": 0.999999460862766, "auc_0_24": 5.680611579487947, "auc_inf": 5.7707800195435075, "auc_pct_extrap": 1.5625000389928732, "cl_L_per_h": 0.1732867994644343, "vz_L": 1.0000000249554386}`

- bare DeepSeek V4-pro (0813) run1 [Ionstream, reasoning=0]: failed lambda_z_per_h, t_half_h, auc_0_24, auc_inf, cl_L_per_h; returned `{"auc_inf": 4.38012, "auc_0_24": 4.3125, "cl_L_per_h": 0.228304, "lambda_z_per_h": 0.231049, "t_half_h": 3.0}`
- bare DeepSeek V4-pro (0813) run2 [Ionstream, reasoning=0]: failed lambda_z_per_h, t_half_h, auc_0_24, auc_inf, cl_L_per_h, vz_L; returned `{"auc_inf": 5.1353, "auc_0_24": 5.0, "cl_L_per_h": 0.1947, "lambda_z_per_h": 0.1155, "vz_L": 1.686, "t_half_h": 6.0}`
- bare DeepSeek V4-pro (0813) run3 [Ionstream, reasoning=0]: failed lambda_z_per_h, t_half_h, auc_0_24, auc_inf, cl_L_per_h, vz_L; returned `{"auc_inf": 4.0451, "auc_0_24": 4.0, "cl_L_per_h": 0.2472, "lambda_z_per_h": 0.3466, "vz_L": 0.7133, "t_half_h": 2.0}`
- bare GLM-5.2 run1 [CoreWeave, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Kimi K3 run1 [InferenceNet, reasoning=16001]: no answer — no parseable JSON (finish_reason=length)
- bare Kimi K3 run2 [InferenceNet, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Kimi K3 run3 [InferenceNet, reasoning=16002]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run1 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run2 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run3 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare_reasoning DeepSeek V4-pro (0813) run1 [Ionstream, reasoning=16003]: no answer — no parseable JSON (finish_reason=length)
- bare_reasoning DeepSeek V4-pro (0813) run2 [Ionstream, reasoning=16004]: no answer — no parseable JSON (finish_reason=length)

**T2b_nca_unit_trap_ng_per_mL** — reference: `{"lambda_z_per_h": 0.1732867951399863, "t_half_h": 4.000000000000001, "c0": 999.999460862765, "auc_0_24": 5680.611579487948, "auc_inf": 5770.780019543508, "auc_pct_extrap": 1.5625000389928774, "cl_L_per_h": 0.17328679946443426, "vz_L": 1.0000000249554386}`

- bare DeepSeek V4-pro (0813) run2 [CoreWeave, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run1 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run2 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run3 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare_reasoning DeepSeek V4-pro (0813) run1 [CoreWeave, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)

**T3a_report_extraction** — reference: `{"species": "rat", "t_half": 8, "cmax": 250, "auc_inf": 1500, "herg_ic50_uM": 5, "fu_plasma": 0.035, "noael_mg_kg_day": 25, "ames": "negative", "chromosomal_aberration": "negative", "micronucleus": "negative", "glp_status": "not stated / non-GLP (never GLP)"}`

- bare GLM-5.2 run3 [CoreWeave, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)

**T4_planted_data_errors** — reference: `{"negative_value": ["P2", 3], "unit_problem": ["P3", 4], "identity_conflict": ["P4", [5, 6]], "clean_rows": {"2": "P1", "7": "P5"}, "rows_safe_to_ingest": [2, 7]}`

- bare DeepSeek V4-pro (0813) run1 [CoreWeave, reasoning=11655]: failed detected.unit_problem, rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 4, 5, 7]}`
- bare DeepSeek V4-pro (0813) run2 [CoreWeave, reasoning=12154]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare DeepSeek V4-pro (0813) run3 [CoreWeave, reasoning=8019]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare Qwen3.8-Max (0902) run1 [Alibaba, reasoning=16000]: no answer — no parseable JSON (finish_reason=length)
- bare Qwen3.8-Max (0902) run2 [Alibaba, reasoning=2460]: failed detected.unit_problem, rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [5, "P4", "identity_conflict"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 4, 7]}`
- bare Qwen3.8-Max (0902) run3 [Alibaba, reasoning=4405]: failed detected.unit_problem, rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [5, "P4", "identity_conflict"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 4, 7]}`
- bare GLM-5.2 run1 [CoreWeave, reasoning=283]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare GLM-5.2 run2 [CoreWeave, reasoning=513]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare GLM-5.2 run3 [CoreWeave, reasoning=272]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare Kimi K3 run1 [InferenceNet, reasoning=1297]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare Kimi K3 run2 [InferenceNet, reasoning=1298]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare Kimi K3 run3 [InferenceNet, reasoning=1748]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare_reasoning DeepSeek V4-pro (0813) run1 [CoreWeave, reasoning=8110]: failed rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [4, "P3", "unit_problem"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 5, 7]}`
- bare_reasoning DeepSeek V4-pro (0813) run2 [CoreWeave, reasoning=5039]: failed detected.unit_problem, rows_safe_to_ingest_exact; returned `{"issues": [[3, "P2", "negative_value"], [6, "P4", "identity_conflict"]], "rows_safe_to_ingest": [2, 4, 5, 7]}`

## BioMate deterministic path: failed fields

- **T1a_two_file_selection**: all fields passed
- **T1b_incomplete_candidate**: all fields passed
- **T2a_nca_mg_per_L**: not_executed_locally — BioMate's NCA capability is the indexed R/PKNCA Nextflow workflow (backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca). No local Python BioMate NCA service exists; R is not installed locally and no substitute calculation is attributed to BioMate.
- **T2b_nca_unit_trap_ng_per_mL**: not_executed_locally — BioMate's NCA capability is the indexed R/PKNCA Nextflow workflow (backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca). No local Python BioMate NCA service exists; R is not installed locally and no substitute calculation is attributed to BioMate.
- **T3a_report_extraction**: all fields passed
- **T3b_predicted_not_measured**: all fields passed
- **T4_planted_data_errors**: all fields passed
- **T5_corrected_resubmission**: all fields passed

## Caveats

- Small n (≤3 repeats × 1 fixture per task); results are illustrative and could change with different fixtures, prompts or providers. Temperature 0 was requested; OpenRouter providers may still be nondeterministic, and some reasoning models may ignore temperature.
- The bare LLMs had no code execution. Hand arithmetic on logs/regressions (T2) is the hardest part for them; a code-interpreter agent would likely close much of that gap.
- BioMate's NCA is an R/PKNCA workflow that was not executed here; BioMate has no T2 score.
- Provider routing matters: OpenRouter picks a provider per request, and some serve a slug without thinking. `bare_reasoning` re-runs DeepSeek with reasoning forced on (providers honouring the parameter only). A hospital's own DeepSeek deployment settings determine which behaviour it gets.
- 16k completion-token cap: runs that spent it all on reasoning returned no answer and score 0. A larger budget might let those models finish, at higher cost and latency.
- BioMate's assay service ranks compounds and has no explicit criteria filter; its top-ranked compound is scored as its recommendation (same interpretation as `scripts/test_sysucc_usecases.py`).
- BioMate results depend on fixes in progress to `assay_ingestion.py`, `auto_retrain.py` and the report-ingestion code; rerun the harness after those land. Source hashes are in the JSON.
- Prompts fully specify the NCA method and the selection criteria, so this measures execution fidelity, not method choice.
