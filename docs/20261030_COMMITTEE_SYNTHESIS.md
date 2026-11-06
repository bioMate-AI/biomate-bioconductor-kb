# LLM review committee — synthesis (2026-10-30): novelty and evaluation

Raw material: `docs/committee_raw/20261030/` (reviews, cost log, runner); packet: `docs/20261030_COMMITTEE_PACKET.md` (~17k tokens, our own committed material; no sequences or credentials). Committee output is opinion; every claim below was triaged by the chair against our artifacts or the web.

## 1. Who actually reviewed, and cost
| reviewer | outcome | cost (API-reported) |
|---|---|---|
| Google gemini-3.1-pro-preview | complete review (3,939 output tokens) | USD 0.0906 |
| OpenAI gpt-5.5 | complete review (6,083 output tokens) | USD 0.2796 |
| Anthropic claude-opus-5.5 | **no review**: provider returned `finish_reason=content_filter` / native `refusal` twice with no content and no reported usage; not worked around, no substitute model used (owner specified Opus) | USD 0 reported |
| Moonshot, DeepSeek, Qwen | dropped by owner before any call was sent (one DeepSeek call was killed at the estimate step; balance unchanged) | USD 0 |
Total counted: **USD 0.370** (cap 6.00). Balance 4.339 → 3.961 (drop 0.378 ≈ reported 0.370 + 0.008; the billing lags the reply by minutes). The shared key had already fallen from the earlier 10.60 to 4.34 before this task started (other consumers); the USD 3 reserve limited this task to about USD 1.3 regardless of the USD 6 cap. Only two of the three requested labs reviewed; read the synthesis with that limit.

## 2. Where the two reviewers agree (high-confidence points)
1. **The central comparison (IH-LM vs larger pretrained peptide/chemistry LMs inside the loop) has not been run**; without it the paper has no central result.
2. **Analog lookup is the bar and the likely explanation** for few-label gains (nearest-neighbour AUROC 0.753/0.822/0.869 at k = 5/10/25). Retrieval-only and lab-offset-only ablations (no LM) must exist; if IH-LM cannot beat them, the LM is ornamental.
3. **No benchmark passes the validity gates cleanly**; zero-shot target-generalisation claims are not supportable; report control-adjusted performance and treat the gate failure itself as a finding.
4. **Leave-labs-out is the real generalisation test** (≈0.30 vs ≈0.67 grouped); Regime A is series interpolation, not generalisation; headline regime B and leave-labs-out.
5. **Overclaiming list:** knowledge fusion (KB thin, intervals include 0), "generation" (retrospective cannot show it), stereo resolution (needs chirality-aware baselines and the corrected split protocol), "novel tokenization".
6. **Most defensible novelty candidates:** M2 anchor-based lab offset, M4 signed edit effects under leave-labs-out, the evaluation protocol/gates; **not** the backbone, tokenisation, retrieval, shrinkage.

## 3. Disagreement
- **Gemini:** try to "solve" the typicality failure (M3) to make a powered, valid benchmark; wants prospective wet-lab validation of M4. **GPT:** reframe — the contribution is the gate and control-adjusted scoring, not benchmark cleanliness. **Chair:** our own V3 evidence (four calipers; 98–100 % of positives lost) supports GPT; a wet lab is not available (out of scope).
- **Gemini** says rerun baselines with chirality-aware fingerprints; this is **stale**: L5 is already chirality-aware and L3 is superseded.
- **GPT** wants a *third* comparison arm (external base given the same modules); Gemini does not mention it. **Chair:** adopt — it is the only fair "architecture vs scale" test.

## 4. Claim triage (chair verification)
Status: **VERIFIED** = source page opened this session; **VERIFIED-SNIPPET** = confirmed from a search result of the primary venue only; **VERIFIED-ARTIFACT** = matches our committed file; **UNVERIFIED**.
| # | claim (source) | status | evidence |
|---|---|---|---|
| 1 | LLM-guided nearest-neighbour (LLMNN) exists; LLM agents ignore feedback under permuted labels; classical methods beat LLM agents (Gemini, GPT-implied) | VERIFIED-SNIPPET | Gupta, Hartford, Liu, *Findings of EMNLP 2025*, arXiv 2509.21403 (search listing, aclanthology/arXiv pages) |
| 2 | Retrieval-augmented molecular property prediction exists (MolRAG; MolE-RAG) (Gemini, GPT) | VERIFIED-SNIPPET | MolRAG ACL 2025 long.755; MolE-RAG arXiv 2606.05693 (snippet: structure-based retrieval up to 20-pt ROC-AUC gain — detail unverified) |
| 3 | Matched-molecular-pair / edit-effect modelling is established (GPT) | VERIFIED-SNIPPET | ACNet, arXiv 2302.07541: >400K MMPs, 190 targets, 16 models; ECFP outperforms deep models on most subsets; DeepAC conditional transformer on small data (RSC Digital Discovery listing) |
| 4 | Scaffold splits lower generalisation vs random on CycPeptMPDB; benchmark of 13 methods (Gemini/GPT-implied) | VERIFIED | Liu, Li, Verma, Lee, *J Cheminformatics* 2025 (PubMed 40877984); does not address lab/source effects or stereochemistry (per fetched summary) |
| 5 | DUD-E / LIT-PCBA are matched-decoy benchmarks with known bias (both) | VERIFIED earlier (survey/manuscript writer opened the sources); not reopened here |
| 5b | MUV, DEKOIS, "CleanSplit" citations (GPT, Gemini) | UNVERIFIED | exact citations not opened; GPT marked DEKOIS/CleanSplit itself as unverified |
| 6 | "No prior paper compares a cyclic-peptide hybrid vs larger peptide LMs inside the same retrospective feedback loop" (GPT) | UNVERIFIED | absence claim; our surveys found none within limited search; peptide-LM comparisons not exhaustively searched |
| 7 | Benchmark gate numbers quoted: C1 0.665 (M2), 0.476 (M); C2 0.690, C3 0.676 (M2); C3 0.315 (M); I: C3 0.584 [0.533, 0.636] (Gemini, GPT) | VERIFIED-ARTIFACT | `docs/20261030_RETRO_RECOVERY_RESULTS_V3.md` table |
| 8 | L5: fp_A 236.1 vs fuse_z_A 244.1, Δ8.0 [-14.7, 48.0]; kn_B Δ23.8 [-4.0, 54.0] (GPT) | VERIFIED-ARTIFACT | `results/l5_aggregate.json` |
| 9 | Regime A leakage 22.9 % identical fingerprint, 60.7 % same stereo-free scaffold (both) | VERIFIED-ARTIFACT | audit log A1 |
| 10 | PepBenchmark (arXiv 2604.10531) — *added by chair*: standardised peptide benchmark, 29 canonical + 6 non-canonical datasets in 7 groups; abstract does not state cyclic content, splits or leakage controls | VERIFIED (existence); content UNVERIFIED | prior-art risk for our benchmark claim (b) unresolved until full text is read |
| 11 | Inter-laboratory variability as a ceiling — *added by chair*: arXiv 2605.11764 (Klamt, Nejdl, Tang; PROTAC activity): cross-lab variance bounded at 0.124 AUROC, LOTO AUROC plateau ≈0.67 across 8 architectures and ESM-2 up to 3B; no anchor compounds, lab offsets or lab-held-out splits | VERIFIED (fetched summary; treat as summary-level) | closest framing of "lab effect as ceiling"; anchor-calibrated offset not found in it |
| 12 | *Chair-found:* secondary hit definition, scaffold-shifted regime, descriptor-knowledge arm: Δ +25.0 [3.9, 54.5], `lower_gt0=True` at the aggregator's 99 % level | VERIFIED-ARTIFACT | `l5_aggregate.json` SENSITIVITY block; not the pre-registered primary definition and not both regimes, so **no claim**; flag for WS2 |
| 13 | Gemini: "M4 must be proven prospectively in a wet lab" | NOT ACTIONABLE | no wet lab; keep as an explicit limitation |
| 14 | GPT: "do not claim novel stereo-aware tokenisation" | AGREE | matches survey risk table (high) |

## 5. Consolidated evaluation issues (ranked) and disposition
1. Central L7 comparison not run → **WS2: run the minimal fair bake-off now** (arms below).
2. Fair comparison needs three contrasts: (i) same base plain vs +modules; (ii) IH-LM full vs external plain; (iii) **external base + the same modules** (equal information) → WS1/WS2.
3. Analog-distance strata for H4b (stereosibling removed, close, medium, remote) and gain-over-NN within each → WS3.
4. Contamination table per external checkpoint (corpus, date, known CycPeptMPDB/ChEMBL overlap; exact/stereo-stripped/scaffold scan; contamination-controlled subset) → WS1/WS2.
5. Primary endpoints and multiplicity: one primary endpoint per aim, cluster bootstrap at the highest dependency unit (source / target family / scaffold series), BH for secondary, nested dev/test seeds for rung selection (partly in L7h: selection on seeds 0–4, report 5–9) → WS2/WS6 + prereg amendment.
6. Non-inferiority: 90 % ratio is arbitrary; add an absolute-loss threshold and report both → WS2 amendment.
7. Cluster-based power (effective n = sources / families / series, not compounds) → WS2/WS3.
8. Regime A labelled "series interpolation"; headline regime B and leave-labs-out → WS6/WS2.
9. Stereo claims only against chirality-aware GBM with the corrected single-split protocol; add paired order accuracy and cliff detection → WS1/WS3.
10. Do not claim "knowledge helps" (KB thin; L5 intervals include 0); examine the chair-found secondary-definition signal (row 12) as exploratory only → WS2/WS5/WS6.

## 6. Action items by workstream
- **WS2 (loop):** add arms `retrieval-only (NN)`, `retrieval + lab offset, no LM`, `K_phys only`, `source-ID only`; run the minimal bake-off at k = 5 and 25 and leave-labs-out (NN, chirality-aware GBM, descriptor GBM, IH-LM plain, IH-LM full, ≥1 external LM plain, shuffled-label and data-matched one-shot controls); register primary endpoints, BH policy, absolute-loss margin; investigate row 12.
- **WS1 (model):** external-base-plus-modules arm; per-checkpoint contamination table; keep P1 gates.
- **WS3 (benchmark):** analog-distance strata; report validity-gate failure and control-adjusted scores as a result; read PepBenchmark full text.
- **WS6 (manuscript):** headline regime B/leave-labs-out; frame the gate audit as a contribution; limitations (retrospective only, no wet lab, two of three committee labs); add LLMNN, ACNet, Liu et al., PepBenchmark, arXiv 2605.11764 to related work after primary-source reading.
- **T1/T2/WS7:** T1 fusion and WS7 anchors are exactly the "NN + lab offset" decisive experiment; prioritise them over any further model building.
- **Claim auditor:** add the chair-found row 12 and the stale items (Gemini's "rerun with chirality" is already done).

## 7. How to strengthen novelty (chair's proposal)
1. Make the **lab/assay offset with anchors plus analog retrieval** the centrepiece: both reviewers rate M2 the strongest module, and the closest published framing we found (inter-lab ceiling, arXiv 2605.11764) quantifies the problem without proposing anchor calibration.
2. Make M4 about **signed edit effects that transfer across labs** (N-methyl addition +0.25 within source), not molecule scoring; ACNet shows MMP modelling exists, so the novelty is peptide-specific signed edits under leave-labs-out.
3. Present the **validity-gate audit** (no-target/typicality controls, control-adjusted scoring, the leave-one-out artifact) as a methods contribution, after checking PepBenchmark.
4. Pair the comparison with the **three-contrast design** (§5.2) so "architecture vs scale" is testable.
5. State plainly what the work cannot show: generation, wet-lab hit rates, target biology.

## 8. Limits of this committee
Two of three requested labs reviewed (Anthropic refused); reviewers saw only the packet; both reviewers marked citations [UNVERIFIED] where unsure and we kept that; the chair verified only a subset of claims (table §4); the secondary-definition signal (row 12) was found by the chair and not by either reviewer.
