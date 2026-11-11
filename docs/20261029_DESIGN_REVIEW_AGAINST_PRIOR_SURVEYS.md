# Design review against the existing model surveys

Review date: 29 October 2026. This reconciles the project's previous surveys and architecture specifications with the current implementation. It does not replace the approved design, amend scientific success criteria, or claim completed experiments. Filename dates are not used as a substitute for explicit decisions and superseding evidence.

## Assessment corrected

The intended method is broader than a ChemFM generator with parent selection and retrieval. That description characterises part of the current implementation, not the original design. The architecture specification explicitly centres evidence-weighted knowledge priors, assay calibration, analogue cross-attention, edit effects and fast/slow memory. The subsequent causal-generation plan adds training under constraints, preference learning and independent stopping/evaluation signals. Reusing pretrained components implements our architecture; it does not define away the architectural contribution.

The strongest defensible question is whether provenance- and applicability-aware knowledge, encoded computationally, improves an inherited peptide model's decisions and adaptation beyond retrieval, property rewards and matched search baselines. No positive answer has yet been established by the new integration code.

## Documents reviewed and how they relate

| Document | Relevant contribution | Interpretation now |
|---|---|---|
| `20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md` | PepGLAD, UniMoMo, RADiAnce, cyclic structure methods; distinction between pose generation and co-design | Structural priors remain relevant. Incompatible DockQ tasks cannot justify model selection. |
| `research/guangzhou_all_atom/docs/SURVEY_2026_UPDATE.md` | PepTune, geometric closure mechanisms, cross-domain models, non-natural-residue distillation | A source of component hypotheses, not proof that transferring them improves our task. |
| `20261004_MULTIOBJECTIVE_GENERATIVE_SURVEY.md` | PepALD, GeoCycler, FAR-DPO, CP-Composer, reward/search trade-offs | Close recent prior art must appear in the method comparison and novelty argument. |
| `20261004_DATA_SCARCITY_GENERALIZATION_SURVEY.md` | Structural priors, cross-domain retrieval, few-shot strategies | The design should inherit useful learned representations rather than demand unavailable cyclic-only training data. |
| `20261012_SURVEY_EDITABLE_SEQUENCE_LLM_GENERATION.md` | Editing, infilling, hard/soft guidance and preference learning | Supports edit-conditioned generation; a parent prefix alone is not a complete learned edit interface. |
| `20261015_GENERATION_SYSTEM_SURVEY_AND_ARCHITECTURE.md` | Knowledge first; deterministic constraints outside the generator; neural exploration of free chemical space | Rules should constrain applicable chemistry without freezing the model into a known scaffold. |
| `20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md` | Pretrained molecular/peptide candidates, representation limitations, comparator roles | ChemFM is a causal implementation choice; it is not established as universally strongest. |
| `20261030_REUSE_AUDIT_ALLATOM_AND_PRETRAINED.md` | Code/checkpoint inventory and limitations | Reuse conclusions must be updated with later implementation evidence, not copied as timeless status. |
| `20261030_HYBRID_ARCHITECTURE_PROPOSAL.md`; `20261030_IHLM_ARCHITECTURE_SPEC.md` | M1–M5 knowledge integration and loop architecture | Preserve this intended computational mechanism; do not silently redefine the model as retrieval alone. |
| `20261031_IHLM_BACKBONE_PEPTIDECLM2.md` | Strict-load and tokenizer evidence; analogue cross-attention adapter | Existing reusable implementation, distinct from a proven causal fusion. |
| `20261031_ALLATOM_LLM_PAPER_DESIGN.md`; `20261031_ALLATOM_IMPLEMENTATION_PLAN.md` | Explicit no-scratch decision; causal generator, masks, feedback, stopping and staged evaluation | Current engineering constraints and causal-generation workstream. Earlier scratch-training proposals are not active instructions. |
| `20261031_ALLATOM_KNOWLEDGE_LAYER.md`; `20261031_SURVEY_EXISTING_CYCLIC_PEPTIDE_KNOWLEDGE.md` | Provenance, evidence tiers, applicability and executable knowledge potentials | Quote matching verifies text provenance, not causal truth, calibration or absence of benchmark overlap. |
| `20261031_SURVEY_GENERATION_EVALUATION.md` | Metric definitions, strong simple baselines and independent validation | Preserve the distinction between feasibility, optimisation scores, generalisation and experimental binding. |

## Recent methods and their consequences

The primary records linked below were re-opened in this review. The checks establish the stated mechanism at abstract/repository level; they do not reproduce results or certify released checkpoint compatibility. No numerical performance comparison is made across these works.

| Prior work | Mechanism confirmed in the primary record | Consequence for our design |
|---|---|---|
| [PepTune](https://arxiv.org/abs/2412.17780) | Peptide-SMILES discrete diffusion with multi-objective Monte Carlo Tree Guidance | Strong guided-generation comparator. Reward-guided multi-objective peptide design alone is not a new claim. Its denoising architecture is not directly interchangeable with a causal LM. |
| [PepALD](https://arxiv.org/abs/2606.14510) | Chemically grounded HELM-monomer latent generation, ring-closure prediction and preference alignment | Relevant recent representation/alignment precedent. Evaluate separately from an open atom-SMILES causal architecture. Availability and exact reuse feasibility still require repository inspection. |
| [GeoCycler](https://arxiv.org/abs/2605.23407) | Training-time alignment to cyclization constraints with chemically gated geometric rewards and replay stabilisation | Constraint-conditioned training already has direct cyclic-peptide precedent. Our knowledge applicability and evidence mechanism must carry the distinction. |
| [FAR-DPO](https://arxiv.org/abs/2608.19808) | Feasibility-aware within-target preference construction and group-robust optimisation | Feasibility plus DPO is insufficient as a novelty claim. Compare how evidence, source shifts and preference reliability enter our learning rule. |
| [RADiAnce](https://arxiv.org/abs/2510.10480) | Retrieval of known interfaces in a shared contrastive latent space, conditioning cross-domain diffusion | Structural retrieval is already model-internal prior art. A generic retrieval module cannot be presented as the central novelty. |
| [PepINVENT](https://github.com/MolecularAI/PepINVENT) | Public peptide RL/MPO implementation with non-natural chemistry support | Prior exclusion from an encoder comparison does not justify excluding it from a generator comparison. It needs a concrete baseline/reuse assessment. |

The earlier surveys also identify RFpeptides/HighFold-style cyclic geometry, UniMoMo/PepGLAD latent structure models and Boltz-family structural evaluation. They remain relevant to a structural branch or evaluation tier. Their coordinates, latent representations and tasks differ from SMILES token modelling; combining them requires explicit interfaces and evidence, not merely listing them in an architecture diagram.

## The computational knowledge design to retain

1. **Evidence representation:** a structured record with source, assay/outcome, chemical scope, uncertainty, supported edit or feature, and supporting/counter-evidence. Exact quote verification is one provenance check, not sufficient scientific qualification.
2. **Executable prior:** translate applicable evidence into feature potentials, edit-effect priors, retrieval memory or valid token/chemical constraints. Literature prose need not be fed literally to the causal LM.
3. **Learned use:** the original M1–M5 design specifies evidence-weighted residual prediction, source offsets, analogue cross-attention and edit heads. Its fast symbolic updates and slow neural adaptation are distinct mechanisms, each requiring its own ablation.
4. **Generation and learning:** causal atom-SMILES generation must preserve stereochemistry and topology; the current constrained/preference path should consume explicit knowledge interfaces and log which evidence affects each decision. Atom-level chemical representation does not by itself imply coordinate generation or explicit hydrogen modelling.
5. **Evaluation:** compare the same inherited model with knowledge off, applicable evidence, mismatched evidence and retrieval alone. Separate gains from source calibration, analogue access, hard feasibility, search budget and neural adaptation. Add relevant recent generative baselines within matching task and budget definitions.

## Corrections to carry forward

- The backbone report supersedes the earlier survey's PeptideCLM-2 small architecture shorthand: loaded checkpoint configuration is 14 blocks and width 512, not 6 blocks and width 384. The older reuse audit's 'not run' statement is superseded by documented loading/tokenizer checks. Those historical checks do not validate today's changes.
- PeptideCLM-2 is an encoder/MLM and an inherited representation; its use does not make it a pretrained causal decoder. The original analogue cross-attention implementation is a reusable integration pattern, not a completed ChemFM fusion.
- ChemFM's current wiring does not establish that it is the best surveyed backbone. Retain it as the current controlled implementation while assessing feasible peptide-specific generative comparators.
- The old scratch-pretraining plan is superseded by the owner's reuse/fine-tune decision. Corpus exclusions, stereo sensitivity and training-data composition controls remain applicable to adapters.
- Earlier recommendations to replace fingerprint models on the basis of published headline scores must not override later matched-task null results. Published AUC, regression R2, closure pass rates and DockQ are not interchangeable.
- Recent extraction output is not automatically eligible numerical knowledge. The audited literature/patent outputs and structural priors retain their quality gates.

## Implementation consequence

Finish the current integrity and integration checks as infrastructure. They do not settle the architecture question or justify changing the intended method to match what happens to run today. Before a headline study, publish a module-by-module implementation/ablation map linking the original M1–M5 specification, the causal-generation path and each admitted knowledge source. Resolve disconnected components explicitly and retain the relevant recent baselines. Scientific success still depends on those comparisons; this review makes no Nature-readiness claim.
