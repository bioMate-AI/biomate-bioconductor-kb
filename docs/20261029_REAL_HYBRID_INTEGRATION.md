# Real-model stage-1 integration (not yet executed)

`model.py` implements ChemFM sampling and masked-policy DPO; `adapters.py`
bridges retrieval and the existing U2/U3 components; `run_stage1.py` wires the
registered verifiers and round loop. Every round uses one shared retrieved
chemical prefix, and failed completions stay in the proposal denominator.
Optimizer and preference-gate state are saved with LoRA deltas. Retrieval uses
chemical seed selection, not natural-language prompts or untrained control codes.

**This is newly implemented, unvalidated integration code.** No local model
execution or tests have been performed. Spot tests plus a real-model smoke are
required. U1's standalone 19-test pass is not an integration pass.

Before study execution, commit an integration amendment describing the precise
current-top-10 monitor adapter (no duplicate pooling), one-time LR multiplication
by two under the existing KL/weight gate, initial frozen-base reference, shared
prefix fraction 0.5, 64 proposals/round, two preference pairs, rank 8, LR 1e-4,
beta 0.1, preference margin 0.02, and selected seeds/arms. Freeze A6 margins too.
The CLI deliberately refuses study mode without matching manifest hashes and
real-model M1 evidence. Non-primary knowledge levels remain audit-gated.

Spot smoke example, from `allatom_paper` with an already staged ChemFM model:

```
python3.11 -m pytest -q hybrid/test_adapters.py test_orchestrator_ia.py
python3.11 -m hybrid.run_stage1 --mode smoke --model-dir /w/chemfm \
  --out /w/out/m1-f2-s0 --family F2 --seed 0 --budget 60 \
  --max-seconds 1200 --ann /w/code/cyclic_llm/stratification/data/annotations.csv.gz
```

The smoke writes a diagnostic, not an automatic M1 pass certificate. Review
completion yield, actual nonzero finite optimizer updates, LoRA reload,
independence and controls before issuing that certificate. A smoke whose
sampling does not produce 16 valid members per round may correctly make zero
updates and must not pass M1.

Provision only Spot, with an independent shutdown deadline, one writer per S3
prefix, continuous log/checkpoint sync, original failure exit status preserved,
and a reconciled budget reservation before launch. The stage-1 run cap is four
hours per arm; a short diagnostic is explicitly not the registered pilot.
Stage 2 is not authorized. The F1 gate remains INCONCLUSIVE irrespective of
optimization performance. No manuscript outcome can be filled from this code.

Knowledge scope: the implemented main L0 arm has hard rules, online chemical-parent retrieval and preference feedback. It does not implement trained natural-language knowledge conditioning. The ten provisional literature statements may support a separate scoped context design, but ChemFM cannot ingest that text through its atom vocabulary, and untrained control codes do not establish knowledge conditioning. L1/L2 remain blocked by missing reviewed audit/pins. The completed method study cannot claim a validated knowledge-augmentation benefit from L0.

Audit correction: token logits are now divided by the same recorded temperature in sampling and DPO; soft potentials and masks are then applied identically. The requested token cap is explicit in the hybrid sampler. The diagnostic called KL is now the exact next-token categorical KL, averaged over the visited, pair-selected contexts; it is not sequence-distribution KL and not an unbiased rollout average. The prior signed sampled log-ratio implementation was never executed as study evidence. Checkpoints contain optimizer, updater, CPU/CUDA RNG and sampling-config state; each new round resets its independent seed from the registered (seed,round) schedule. Bitwise GPU reproducibility still requires same software/hardware and deterministic kernels. A6 is opened and its actual SHA256 and margins checked, rather than trusting a nonempty hash string.


## Takeover validation status, 29 October

The isolated Spot CPU QA is pending its complete rerun. Earlier attempts stopped
at environment or packaging imports; they do not constitute test passes. The
corrected bundle includes the package initialization dependencies and synthetic
conditional-parent tests. No local tests or model compute were run.

A prospective conditional-parent knowledge adapter is now implemented in
`hybrid/knowledge_parent.py` and connected to the generator. It checks immutable
source hashes and quote offsets, explicit scientific scope, reviewed action
permission, and source/compound/scaffold/target exclusions before choosing a
chemical parent. Its off/on/inapplicable-provenance control arms record evidence
IDs and prefix hashes. Its fixtures are synthetic. There is no qualified frozen
real-evidence catalogue or measured knowledge benefit; L1/L2 remain blocked.

The remote A6 aggregation processed 160 evaluation/control files and produced
`docs/20261029_TRACK_E_A6_PROPOSED.json` (SHA-256
`2d1a637061c75da926775dbe51689ceccb7b42f2f31795822ff22760ea0c0f03`).
This is a proposed summary, not a freeze. Independent review found that the
copy-seed shuffled-control interval fails the registered requirement to contain
zero; a negative interval must not be reinterpreted as a pass. Remaining review
also requires tuning-phase and shuffled-control stop/call/budget-fraction
accounting, planted/copy-seed trajectory and plateau evidence, and the registered
wider bootstrap-versus-t interval calculation instead of the helper's t-only
calculation. These control and analysis gaps block study freeze. Actual real-model
M1 validation and reconciled remaining Spot budget are also outstanding. Do not
launch the registered study or claim method-study completion from this summary.
