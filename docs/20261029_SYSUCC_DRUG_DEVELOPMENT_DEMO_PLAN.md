# SYSUCC drug development and model adaptation demo plan

Date: 2026-10-29
Audience: Information-center leadership at Sun Yat-sen University Cancer Center, Guangzhou, with scientific investigators if available.
Timing: Next week, November 2–8; exact meeting length and permitted datasets are pending confirmation. Default run-of-show: 30 minutes.

## Recommended message

Alignment update: see [platform capability review and Claude/GPT comparison protocol](20261029_SYSUCC_PLATFORM_ALIGNMENT_AND_MODEL_COMPARISON.md). The hospital narrative should include existing scientific knowledge, assay-learning, translational pharmacology and reviewed evidence generation, not stop at target identification and molecular design. Catalogue coverage and current case execution remain separate claims.

**院内数据驱动、可持续学习的肿瘤药物研发工作台。**

BioMate connects evidence and target prioritization to small-molecule or cyclic-peptide design, computational evaluation, experimental feedback and evaluated model updates. The hospital retains control over its datasets and deployment boundary. The demonstration should prove this connected research process, not imply clinical efficacy from computational scores.

SYSUCC is not a novice AI customer. Its information center's [June 2025 announcement](https://www.sysucc.org.cn/node/10113) explicitly sought an AI platform foundation. A [July 2025 report hosted by Sun Yat-sen University](https://www.sysu.edu.cn/news/info/2171/1390811.htm) describes an existing DeepSeek-based oncology assistant and internal-data model development. These are dated public facts, not confirmation of today's configuration or the director's current procurement priorities. The practical positioning is a complementary drug-research execution and learning layer, not another general clinical chatbot or a replacement for their AI platform.

## One project with two appropriate modality branches

Use one oncology research workspace, a shared evidence library and consistent provenance. Small molecules and peptides should branch according to target biology; do not force them through one target, one scoring scale or one universal model.

**Small-molecule anchor.** Prefer a well-characterized kinase/reference-ligand case for a reliable scientific control. EGFR/erlotinib is appropriate if the existing workflow passes rehearsal. [PDB 1M17](https://www.rcsb.org/structure/1M17) is human EGFR with erlotinib and reports no mutations: it must not be presented as a T790M structure. The existing ABL/imatinib fixture is a backup, but [1IEP](https://www.rcsb.org/structure/1IEP) is mouse c-Abl, not an unqualified human BCR–ABL fusion structure. Species, construct, pocket and mutation status belong in the input record.

**Peptide scientific showcase.** Preserve continuity with the existing SYSUCC collaboration concept: direct therapeutic αvβ6 antagonism and/or PD-L1 cyclic peptides. Choose one as the main peptide example after rehearsal. These are research proposals, not validated BioMate therapeutics. The existing BCL-XL fixture can test mechanics but is not interchangeable with the proposed αvβ6/PD-L1 program, and its supplied reference sequence is not already cyclized. Specify cyclization positions, bond type, stereochemistry and noncanonical residues explicitly.

Target nomination should show disease evidence, actual experimental data if authorized, contradictory evidence and selection criteria. Do not claim that an Open Targets score proves novelty, causal validation or superiority over existing target-ranking systems. A familiar positive control demonstrates execution fidelity; the new-candidate branch demonstrates the research opportunity.

## Thirty minute run of show

| Time | On screen | What the audience should learn |
| --- | --- | --- |
| 0–3 min | Chinese-language oncology project, two explicitly cited input files and their origins; simple data/inference/external-search boundary | A hospital research team can work with its own assets without losing their identity or control. |
| 3–7 min | Live target shortlist with sources, conflicting evidence and editable criteria | BioMate prioritizes candidates transparently rather than inventing a definitive target. |
| 7–13 min | Small-molecule branch: explicit target structure/pocket, reference control, candidate evaluation coverage, ADMET and docking outputs, evidence-linked comparison | Real outputs feed the next step. Missing evaluations stay missing; docking is not measured affinity or clinical efficacy. |
| 13–18 min | Peptide branch: target/interface, exact chemistry constraints, authentic completed sequence/structure outputs and candidate tradeoffs | BioMate supports a different therapeutic modality, with chemistry and prediction limits visible. |
| 18–25 min | New assay CSV; dataset validation; base and adapted model versions; same untouched holdout; updated predictions and next-round proposal | Hospital data can improve an institution-specific model through an evaluated, controlled learning process. A bad update need not be promoted. |
| 25–30 min | Reviewer handoff, source/run/model links, denied unauthorized access, concise report and bounded pilot proposal | This can become an institutional research capability, not a one-off chatbot demonstration. |

Show a genuine completed run for slow stages, labelled with its time and run ID. Live actions should include file citation, changing a criterion, launching a bounded task, inspecting results and ingesting feedback. Do not make the meeting wait for docking, GPU generation or fine-tuning. A recorded authentic replay is a fallback, not a fabricated live run. Use exact observed durations in rehearsal material; do not promise a universal turnaround time.

Include a short exposure/response extension using an existing NCA, population-PK, exposure-response or xenograft workflow, selected to match available inputs. Replace some detailed candidate-screen browsing rather than extend the meeting. Finish with a source-linked evidence/gap summary. This makes the later-development capability visible without claiming autonomous clinical dosing or regulatory approval.

## The model adaptation demonstration

The most persuasive moment is a new experimental batch producing a new model version and a changed candidate proposal, while both model versions are judged on the same untouched data.

1. Open the baseline model and its task, input schema, training dataset, evaluation dataset and artifact.
2. Import a second assay batch. Validate compound/sequence identity, endpoint, units, censoring, assay conditions and provenance. Do not mix patient outcomes, docking scores and biochemical IC50 values as if they were the same label.
3. Exclude the fixed holdout from both training batches and all tuning. Deduplicate and use chemistry-aware grouping, with a time or scaffold split appropriate to the task.
4. Train an explicitly separate candidate version. Show a small real training job only if it is rehearsed and finishes comfortably; keep an authentic completed run available.
5. Compare the original and updated model on the same holdout, displaying sample counts, errors or classification metrics, applicability and uncertainty. Show negative results honestly. Missing metrics must not count as a pass.
6. Promote only after the agreed evaluation passes and a reviewer approves. Re-score the candidate list and generate the next proposed experiment. Keep the prior version usable for rollback.

Keep three different mechanisms clearly labelled:

- **Predictor retraining:** a real small-molecule property/potency predictor trained on assay rows. Useful and demo-friendly, but not foundation-model continued pretraining.
- **Generator weight adaptation:** actual optimizer steps and a new peptide generator checkpoint, such as the existing research DPO path. Show an authentic completed training artifact and controls. A property-oracle result does not establish binding improvement, cross-target transfer or patient benefit.
- **Instruction/retrieval adaptation:** corrections become rules or examples used at inference. This is useful institutional customization, but is not a weight update.

Use authorized internal assay data only after scope and handling approval. Until then use a prominently labelled public experimental dataset or synthetic interface fixture. Synthetic feedback can demonstrate data flow, not biological improvement. Do not upload hospital data into the current public dev environment to make the demo more realistic.

## Readiness gaps requiring attention before rehearsal acceptance

| Finding | Evidence | Required action |
| --- | --- | --- |
| A configured training gate passes if its metric is absent. | `backend/lib/galaxy/ai/ml_training/training_job.py:_evaluate_gate` | Fail closed on absent/nonfinite configured metrics and test failed updates are not promoted. |
| Requested scaffold splitting is not implemented in the sklearn path; a random split is used. | `ml_training/chemprop_trainer.py:_train_sklearn`; also inspect Ludwig splitting | Implement and test the promised split, or use an explicit independently protected holdout and label the demonstrated method accurately. Never display a scaffold label for a random split. |
| Generic Chemprop training is a skeleton, and regulatory post_train_lora simulates completion. | `ml_training/chemprop_trainer.py:_train_chemprop`; `drug_discovery/regulatory_training_worker.py:_do_post_train_lora` | Remove these from the demo's selectable success path until real execution is wired; never substitute a stub for weight training. |
| Generic custom-model persistence/versioning needs verification across restart. | `custom_model_registry.py` under `ai/`, training/serving handoff | Demonstrate loading the exact new artifact after restart and retaining the old version. A row replacement or in-memory wrapper is not durable version history. |
| Current demonstration scripts narrate unsupported scores or rankings. | `frontend/e2e/demo-01-drug-discovery.demo.ts`, `demo-05-autoloop-qc.demo.ts` | Remove predetermined favorable scores; require expected output coverage and rank only candidates actually evaluated with comparable methods/pockets. |
| Five-phase cyclic-design catalogue entries do not establish an executable complete chain in this checkout. | Peptide route and workflow inventory; cofold implementation | Resolve catalogue ID → source → deployed image → successful output. Missing workflow source is a blocker to a live full-chain claim. |
| Cofold has placeholder receptor defaults and optional structure/confidence outputs. | `structural_biology/cyclic_peptide_cofold/main.nf` | Require the actual receptor and peptide chemistry plus nonempty validated outputs in the rehearsal. Its L-backbone approximation is not chemistry-exact ncAA/D-residue/N-methyl modeling. |
| Recent target tool succeeded but final chat denied execution. | `docs/qa/20261029-scientific-chat-live-final.json` | Complete the artifact-precedence/streaming correction and require final visible text to match actual target-score pairs and tool outcomes. Structural test success alone is insufficient. |
| Audit logs and some project events are best-effort; on-prem resolver egress remains a deployment concern. | `frontend/server/audit-service.ts`; on-prem readiness audit | Show real provenance and access tests, but do not claim immutable complete compliance records or zero egress without validation. |

The genuine peptide research optimizer/checkpoint code is distinct from the generic stub. Existing permeability-adaptation controls are useful supporting material, after underlying artifacts are checked. The October 25 correction in `20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md` explicitly retracts binding/FEP validation claims; do not revive them in the demo.

## Parallel preparation and freeze gates

**Drug-chain stream:** establish one successful small-molecule control, one correctly specified peptide run and output-to-input binding across every shown step. Fix silent test skips and unsupported rankings.

**Learning stream:** close the missing-metric and split-contract bugs; verify real checkpoint creation, fixed-holdout comparison, ownership, durable reload and explicit promotion/rollback. Rehearse both passing and rejected updates.

**Hospital-platform stream:** produce one deployment-boundary diagram, verify researcher/reviewer access and download controls, check external-service calls and prepare the pilot's connector/SSO/HPC requirements. Present integrations not yet built as scoped pilot work.

**Presentation stream:** concise Chinese narrative, clean authentic artifacts and screenshots, explicit live/replay labels, one-page pilot proposal and backup recordings. Keep internal business-development applications and unconfirmed partnerships out of hospital-facing materials.

Freeze the cases and claims at least 48 hours before the meeting. Require two full rehearsals against the exact build, with a clinical/scientific reviewer checking the outputs and an IT reviewer checking access/data boundaries. No speculative long GPU run should be the last unverified dependency on demo day.

## Desired meeting outcome

Seek agreement on one hospital research program, one permitted dataset, a scientific investigator and an information-center owner for a bounded pilot. Define success in terms of reproducible completed tasks, scientific fidelity, access/data controls and measured model-update performance. Do not make a short pilot depend on proving a new drug or clinical benefit.
