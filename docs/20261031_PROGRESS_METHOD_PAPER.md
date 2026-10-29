# Progress file for the IH-LM method paper (project management lives here, not in the manuscript)

Manuscript: `docs/20261031_MANUSCRIPT_ALLATOM_METHOD_DRAFT.md` ("IH-LM" is a working name). Companion papers: evaluation and controls (`docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md`, "paper 1"); knowledge base (`docs/20261031_MANUSCRIPT_KB_SECTION_FOR_METHOD_PAPER.md` is the section file; the standalone draft is `docs/20261031_MANUSCRIPT_KNOWLEDGE_BASE_DRAFT.md`). Verification script: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/qa/verify_method_draft.py` (pure text and JSON reads, about one second; outputs `verify_method_draft_output.txt` and `method_draft_unchecked_numbers.txt` beside it). Last run: 102 checks (54 value, 29 text, 19 structure), 0 failed; 181 numeric tokens in Sections 3-5 not covered by any check (design constants, hyperparameters, document-derived numbers and small counts in prose; each is listed with its context and reason class).

## 1. Registry: manuscript table or cell -> filling result file -> owner

Empty cells in the manuscript are shown as "—". Owner names are workstreams (E evaluation, U1 rule automaton, U2/U3 monitor and preference updater, I-A orchestrator, I-B retrieval, K/K2/K3/K4 knowledge streams, M3 stage-1 integration, M6 arm G, M7 audits).

| id | manuscript item | fills from | owner |
|---|---|---|---|
| R1 | Table 7 (baselines, MDE, pass probability) | `track_e/results/` (tuned.json, eval files) and the baseline amendment in `docs/20261031_ALLATOM_TRACK_E_PREREG.md` | E |
| R2 | Section 5.2 per-source verifier values (replacement outcome is filled: VOID) | `track_e/verifier_quality_v2.json`, `track_e/bw_eval_v2B.json` | E |
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
| R14 | Gold-set counts: manuscript quotes the committed version (107 entries at `7ecf14af2`: T1 60, T2 36, internal 11; SHA-256 `29368807…6951`); update if the set is extended | `knowledge/knowledge_kb_v1.json`, `direction_check_results.json` | K |
| R15 | Table 13 (calibrated gate acceptance values) | gate calibration results | gate-calibration fork |
| R16 | Cost statement (if wanted in a methods note) | cost logs | all |
| R17 | Reference checks: ChemFM paper (arXiv:2410.21422; only the model card was opened), Boltz-2, BoltzGen, UniMoMo, CycPeptMPDB, REINVENT 4, retrieval-augmented generation, DeepDelta | primary sources | writer |

## 2. Removed or softened for lack of an opened primary source

EvalStop (arXiv:2606.04145; abstract-level extract only) removed; the PeptideCLM-2 margin of +0.036 AUROC over an RDKit baseline (extract-level) removed; the statement about ChemFM's pretraining corpus (search-snippet level) removed; retrieval-augmented molecule generation, DeepDelta and the LLM-plus-nearest-neighbour design paper (unverified) removed from the text.

## 3. Open items

1. Patent stage (K4): pilot not run; counts omitted. The abstract and Section 3.3 describe the stage as part of the construction pipeline.
2. Physics held-out verifier: below its floor (-0.0083). The one registered replacement test (Boltzmann-weighted polar SASA, A3) was VOID (528 of 1,116 B peptides, 5 of 9 sources; result file `track_e/bw_eval_v2B.json`, commit `8776ef02f`), so family F1 has no admissible held-out verifier and the stage-1 gate is INCONCLUSIVE by design; manuscript Sections 4.2, 4.7, 5.2 (Table 4) and 7 state this. No further replacement is allowed by the registration.
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

## 8. Correction history of the knowledge-layer counts (moved from the manuscript)

1. Commit `9fbac3e71`: 48 entries (38 T1, 10 T2; 19 sources; 21 weight-eligible).
2. Commit `21680221b`: 107 entries (65 T1, 31 T2, 11 internal; SHA-256 `b6c8988545bc…`); an earlier manuscript revision quoted 65 and 31.
3. Commit `7ecf14af2` (tier audit): 13 tier changes by one provenance rule, giving T1 60, T2 36, internal 11; total 107, all quotations verified, weight-eligible unchanged at 32 (14 T1, 18 T2); SHA-256 `29368807246824222aa8ea860ff69adce1393ef9976a5c8fbb6091c5d0fe6951`; direction check unchanged (17 agree, 7 mixed, 0 disagree, 83 not testable). Tier rule: T1 = the quoted statement reports a result or method from the source's own experiment, simulation or data analysis; T2 = a review's summary of others' work, a restatement of a result cited to another paper, a textbook rule, authors' background or a project goal; default T2 when the stored text cannot show that the number is the source's own.

## 9. Log of manuscript updates

- Replacement test for the physics held-out verifier recorded as VOID (528 of 1,116 peptides, 5 of 9 sources; descriptive Spearman 0.2245, cluster interval 0.163 to 0.418, selection-biased, not a pass); consequences stated in Sections 4.2, 4.7, 5.2 and 7. The 4D-descriptor reference values (0.200, 0.211, 0.016 on 440 peptides) are in the amendment text and were not added to the manuscript.
- Baseline tuning bug: buggy tuning files were deleted before any baseline number was read, and the edit-operator and SELFIES genetic algorithms have a stall guard; this does not affect any result, so nothing was added to the baselines paragraph.
- Amendment A4 (commit `a3add2b3f`): verifier scale changed from percentiles against natural peptides to z-scores against 1,500 random rule-satisfying library draws; metric SD-AUC; margin m_f = 0.10 x (best-baseline SD-AUC minus random-library SD-AUC) per family from baseline evaluation seeds, committed before any hybrid run; baselines re-tuned. Manuscript Sections abstract, 4.1, 4.3, 4.4, 4.6, 4.7 and Tables 7 to 9 updated; the saturation observation (tuned baselines 0.979 to 0.986, random library 0.886 to 0.944 at B = 1,000, tuning seeds) is one factual sentence in Section 4.1. The +0.03 margin and the 'normalised AUC-top-10' wording are gone from the manuscript; the verification script now fails if they return.
- Decision to confirm with the evaluation owner: in Section 4.6 the pass-probability table is stated for true gains of one and two margins (delta = m_f and 2 m_f), because the earlier delta values 0.03 and 0.05 were in percentile units; if the baseline amendment (A5) fixes different delta values, change Section 4.6 and the Table 7 header.
- Table 7 now has columns for the margin m_f and for the paired SD; Table 5/6/8 unchanged. The controls table keeps the planted-optimum control on its own [0, 1] score; the shuffled-reward control is judged in SD-AUC.
- Verification script: 111 checks (57 value, 34 text, 20 structure), 0 failed; 184 numeric tokens in Sections 3 to 5 not covered.
