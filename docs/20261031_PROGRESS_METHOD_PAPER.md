# Progress file for the IH-LM method paper (project management lives here, not in the manuscript)

Manuscript: `docs/20261031_MANUSCRIPT_ALLATOM_METHOD_DRAFT.md` ("IH-LM" is a working name). Companion papers: evaluation and controls (`docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md`, "paper 1"); knowledge base (`docs/20261031_MANUSCRIPT_KB_SECTION_FOR_METHOD_PAPER.md` is the section file; the standalone draft is `docs/20261031_MANUSCRIPT_KNOWLEDGE_BASE_DRAFT.md`). Verification script: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/qa/verify_method_draft.py` (pure text and JSON reads, about one second; outputs `verify_method_draft_output.txt` and `method_draft_unchecked_numbers.txt` beside it). Last run: 102 checks (54 value, 29 text, 19 structure), 0 failed; 181 numeric tokens in Sections 3-5 not covered by any check (design constants, hyperparameters, document-derived numbers and small counts in prose; each is listed with its context and reason class).

## 1. Registry: manuscript table or cell -> filling result file -> owner

Empty cells in the manuscript are shown as "—". Owner names are workstreams (E evaluation, U1 rule automaton, U2/U3 monitor and preference updater, I-A orchestrator, I-B retrieval, K/K2/K3/K4 knowledge streams, M3 stage-1 integration, M6 arm G, M7 audits).

| id | manuscript item | fills from | owner |
|---|---|---|---|
| R1 | Table 7 (baselines, MDE, pass probability) | `track_e/results/` (tuned.json, eval files) and the baseline amendment in `docs/20261031_ALLATOM_TRACK_E_PREREG.md` | E |
| R2 | Section 5.1 per-source verifier values; physics held-out replacement outcome | `track_e/verifier_quality_v2.json`, result of the post hoc replacement test (A3, `track_e/bw_eval.py`) | E |
| R3 | Table 5 (golden set, agreement, overhead, masked sampling, 200-step fine-tune) and backbone content (N-methyl, D, macrocycle) | `allatom_paper/rules/` results | U1 |
| R4 | Table 6 (fine-tuning corpus composition and counts) | corpus decision document | U1 |
| R5 | Section 3.4.3 smoke on the 1-billion-parameter model | `allatom_paper/feedback/results/smoke_v3.json` | U2/U3 |
| R6 | Table 8 (stage-1 comparison), Figure 1 (budget curves), monitor on the real loop | stage-1 results document | M3 |
| R7 | Table 9 (ablations) | stage-1 results document | M3 |
| R8 | REINVENT-style RL and language-model-as-operator baselines (Section 4.3) | baseline results | E, M3 |
| R9 | Table 10 (arm G) | arm-G results document | M6 |
| R10 | Table 11 (audits) | audit results document | M7 |
| R11 | Table 12 (robustness on group version 1) | robustness table | E |
| R12 | Section 3.3.3 counts: imports (parse and join rates), scaled-extraction precision and recall, coverage matrix | `docs/20261031_ALLATOM_KNOWLEDGE_*`, KB-paper | K2, K3 |
| R13 | Patent stage counts (Section 3.3.3(d)) | `docs/20261031_ALLATOM_PATENT_KNOWLEDGE.md` (does not exist yet; no counts in the manuscript until it does) | K4 |
| R14 | Gold-set counts: manuscript quotes the committed version (107 entries at `21680221b`, SHA-256 `b6c8988545bc…`); update if the set is extended | `knowledge/knowledge_kb_v1.json`, `direction_check_results.json` | K |
| R15 | Table 13 (calibrated gate acceptance values) | gate calibration results | gate-calibration fork |
| R16 | Cost statement (if wanted in a methods note) | cost logs | all |
| R17 | Reference checks: ChemFM paper (arXiv:2410.21422; only the model card was opened), Boltz-2, BoltzGen, UniMoMo, CycPeptMPDB, REINVENT 4, retrieval-augmented generation, DeepDelta | primary sources | writer |

## 2. Removed or softened for lack of an opened primary source

EvalStop (arXiv:2606.04145; abstract-level extract only) removed; the PeptideCLM-2 margin of +0.036 AUROC over an RDKit baseline (extract-level) removed; the statement about ChemFM's pretraining corpus (search-snippet level) removed; retrieval-augmented molecule generation, DeepDelta and the LLM-plus-nearest-neighbour design paper (unverified) removed from the text.

## 3. Open items

1. Patent stage (K4): pilot not run; counts omitted. The abstract and Section 3.3 describe the stage as part of the construction pipeline.
2. Physics held-out verifier: below its floor (-0.0083). A time-boxed replacement test was specified (A3). If it fails, family F1 has no admissible held-out verifier and the stage-1 gate is INCONCLUSIVE by design (Section 4.7 states the rule).
3. Held-out permeability verifier ranks its largest laboratory essentially not at all (n-weighted -0.0046); the pass-probability table includes lambda_H in {0.229, 0.10, 0}.
4. REINVENT-style RL and language-model-as-operator baselines need the generator interface.
5. Gold-set statements were written by an AI assistant from opened sources and have not been independently judged against their quotations.
6. The gate calibration may not meet its acceptance criteria; Section 4.9 reports whatever is measured.
7. The literature-prior arm uses 15 weight-eligible rules that agreed in both train laboratories; one of them (LIT-BRO5-001) has a molecular-weight term, which the arm must zero (size terms receive weight zero). Confirm in the loader before the ablation is run.
8. Reference list: CycPeptMPDB, Boltz-2, BoltzGen and UniMoMo have no formal reference in the manuscript (names only); add once their primary sources are opened. The ChemFM paper (arXiv:2410.21422) is cited for the checkpoint but only the model card was opened.

## 4. Decisions on record

Groups version 2 (Townsend and Kelly always train; snake draft of the remaining 18 sources); no from-scratch pretraining; hard rules only as the primary decoder configuration (no mined soft rule validated on the two-laboratory train group); GO requires a win in every family on held-out verifiers plus controls that can fail; stage-1 stop rule; owner instruction to focus the paper on two contributions (rule-compiled decoding; knowledge augmentation) and to cite the evaluation protocol and the knowledge-layer construction from the companion papers while keeping this paper self-contained.

## 5. Risks

Weak held-out verifiers (attenuation of any held-out gain); two-laboratory train group; enumeration advantage built into constraint-yield metrics; overlap of the initialisation checkpoint and encoder with public sources; low power with two objective families (cluster inference unavailable); cost overrun risk on GPU stages.

## 6. Commit references (moved from the manuscript)

Design `19ab71692`; evaluation protocol A1, A2 `09dc0eb84`, A3 `d33594b6f` and `4faa4cfe0`; verifier harness `d61d63ff2`, `7fa31928e`; verifier quality `eb8ed0124`; contracts `3eb00a825`; orchestrator `5f27e50c2`; source groups version 2 `020b56e99` (membership SHA-256 `be8a9945f5042b97afa177d85c23f80b9343c933722c54f02188bd75b276db1c`); retrieval and group-A mining `13c526d45755`; gold knowledge set `9fbac3e71`; generation pilot frozen configurations `e30bde958`, `b1c98f20e` and results `db50a4d30`.

## 7. Spend (estimates reconstructed from timestamps where no cost log exists)

Generation pilot about USD 6.8 against a USD 4 cap (idle-instance overrun about USD 6.0 from instances waiting for an uncommitted configuration; ChemFM stages about USD 0.83); orchestrator tests about USD 0.01; retrieval stream about USD 0.20; other streams to be added from their cost logs.
