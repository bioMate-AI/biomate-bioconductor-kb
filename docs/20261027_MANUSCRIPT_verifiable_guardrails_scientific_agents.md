# Expert Feedback as Verifiable Guardrails: A Gate-Family Taxonomy and a Dual-Use Rule Substrate for Governed Self-Improvement in Scientific Agents

**Author:** Yaoyun Zhang (BioMate)
**Date:** 2026-10-27
**Status:** `PREPRINT DRAFT — awaiting author final review before submission.` Not for
external distribution. Claims are scoped to what is built and measured vs. proposed;
see §9 Limitations.

---

## Abstract

Domain-expert feedback is the scarcest and highest-value signal available to a
scientific AI agent, yet most systems absorb it as a single undifferentiated
bucket — a prompt append, a preference pair, or a hand-coded filter — which makes
it neither reliably enforced nor measurable. We argue for a different discipline:
**classify each piece of expert feedback by a single *checkability test*** — can a
deterministic program, from a run's parameters and outputs, decide whether the
feedback was honored? — and route it to one of three channels: a **verifiable
guardrail** (hard, enforced), a **weighted preference** (soft, judged), or an
**evidence-gated fact**. The central observation is that a verifiable guardrail
and a training reward are *the same object evaluated at two times*: enforced at
inference, scored at training. We then make the verifiable channel concrete for
science by grouping it into **eight gate families** (threshold, canonical/enum,
motif/substructure, schema/format, set-membership/grounding, relational,
procedural/ordering, provenance), each with a distinct verifier shape, and we show
that bioinformatics and drug-discovery constraints populate these families densely
— a domain advantage over open-ended text, where verifiers are scarce. We describe
a reference implementation in the BioMate platform: a safe, declarative,
non-`eval` rule interpreter whose compiled output serves simultaneously as an
inference gate and a GRPO reward term; a gate-before-score verification layer; a
deterministic edit-pair rule compiler for the preference channel; and a
firewalled, longitudinal evaluation harness. We give a pre-registered evaluation
protocol and a construction recipe for a domain benchmark built from *publicly
codified rule sources* (FastQC/MultiQC thresholds, Lipinski/Veber/PAINS/Brenk
filters, file-format specifications, reference vocabularies) and our own
execution-verified run corpus. Finally, we frame the full loop — feedback →
classify → compile → enforce/reward → evaluate → induce — as a *governed* form of
recursive self-improvement (RSI), in which the verifiable guardrail is
simultaneously the improvement target, the measurement, and the firewall against
the reward-inflation and drift that sink ungoverned self-improvement. The
framework is implemented; the large-scale learning results are future work.

---

## 1. Introduction

A scientific agent that routes experiments, sets parameters, runs pipelines, and
writes up results will be wrong in ways that only a domain expert can catch:
"human genome means GRCh38, not hg19"; "that FDR threshold is too loose for this
assay"; "this QC metric is legitimately low for a low-input protocol — don't fail
it"; "the macrocycle must keep the RGD motif"; "every number in the report needs a
source." This feedback is the product's most valuable input and its scarcest. How
a system *absorbs* it determines whether the system improves or merely accumulates
unenforced advice.

The dominant practice is to treat all feedback the same: append it to a system
prompt, log it as a preference pair, or encode a one-off filter. Each is wrong for
part of the feedback. A hard constraint left as prompt advice is silently ignored
when the context grows; a stylistic preference hard-coded as a blocking filter
manufactures false rejections; a factual correction dropped into a reward model
without provenance becomes unverifiable lore.

We propose a discipline built on one question, the **checkability test**:

> *Can a deterministic program, looking only at a run's parameters and outputs,
> decide whether this piece of feedback was satisfied?*

The answer partitions feedback into three channels (§3). The **verifiable** channel
— the "yes" answers — is where the leverage is, for a reason specific to our
domain: **science is unusually verifiable.** A threshold is crossed or not; a
parameter equals a canonical value or not; an output conforms to a file schema or
not. Where general-purpose assistants must fall back on a learned judge for most
instructions (the "verifier problem"), a bioinformatics agent can turn a large
fraction of expert feedback into *real* gates. Our contributions:

1. The **three-channel framework** and the **dual-use identity**: a verifiable
   rule is one object used as an inference gate and as a training reward (§3).
2. A **gate-family taxonomy** (G1–G8) that makes the verifiable channel concrete
   and authorable for scientific agents, with a verifier shape per family (§4).
3. A **reference implementation** — a safe declarative rule interpreter, a
   gate-before-score verification layer, a deterministic edit-pair compiler, and a
   firewalled evaluation harness — with an honest built-vs-proposed accounting (§5).
4. A **pre-registered evaluation protocol** and a **benchmark-construction recipe**
   from public rule sources plus our execution-verified run corpus (§6).
5. The framing of the whole loop as **governed RSI**, with the guardrail as the
   firewall (§7).

## 2. Related work

**Verifiable-reward RL.** RLVR trains policies against deterministic,
reproducible verifiers rather than learned reward models, which avoids reward
hacking and alignment drift but is limited to tasks with a checkable answer —
math, code, structured output. The instruction-following line is the closest
public analog to our framework: **IFEval** (Zhou et al., 2023) scores ~541 prompts
against 25 programmatically verifiable instruction templates; **IFBench** (Pyatkin
et al., 2025) generalizes to 58 new verifiable constraints with verification
functions and studies generalization to *unseen* constraint types; its **IF-RLVR**
toolkit adds constraints + verifiers + RL code. **AutoIF** (Dong et al., 2024)
uses execution feedback to self-generate instruction-following data. Recent work
pushes verifiable constraints toward expert rubrics and the scientific domain
("ComplexConstraints and Beyond: Expert Rubrics for RLVR," 2026; "SciMIF:
Multimodal Instruction Following in Scientific Domains," 2026). Our taxonomy is the
domain-specialization of this line: the gate families are the scientific analog of
IFBench's constraint types, and generalization to unseen gate families/domains is
the axis IFBench's "unseen constraints" axis anticipates.

**Preference/constitutional alignment.** RLHF and Constitutional AI / RLAIF (Bai
et al., 2022) scale a small set of principles into a large preference signal via a
model judge. This is the correct mechanism for our *soft* channel (§3b), where no
deterministic verifier exists, and it is complementary to — not a substitute for —
the verifiable channel.

**Guardrail frameworks.** Production guardrail systems (NeMo Guardrails, Llama
Guard, Guardrails AI) enforce format/safety constraints at inference. They are
enforcement engines without the training-time dual use or the evaluation-and-
induction loop we emphasize.

**Self-improving / self-evolving agents and RSI.** From the Gödel machine
(Schmidhuber, 2003) through scaffolding self-improvers — STOP (Zelikman et al.,
2024), Promptbreeder (Fernando et al., 2024) — and weight-level self-rewarding
language models (Yuan et al., 2024), to reflection/skill-library agents (Reflexion,
Shinn et al., 2023; Voyager, Wang et al., 2023) and 2025 surveys of self-evolving
agents, the recurring risk is reward inflation and drift when the improvement
signal is not verifiable. Process-reward verification (Lightman et al., 2023) and
RLVR are the antidotes. Our framework positions the verifiable guardrail as the
substrate that makes the self-improvement loop safe to close (§7).

## 3. Framework: three channels and the dual-use identity

Apply the checkability test to each piece of feedback:

- **Verifiable → guardrail.** A deterministic verifier decides pass/fail from the
  run. Enforced at inference ("gate before score": reject off-spec output *before*
  any quality scoring, so a polished-but-non-compliant answer never wins) and,
  because it is a reproducible scalar, reused as a **training reward term**.
- **Soft judgment → weighted preference.** No deterministic verifier (style, prose
  ordering, tone, figure aesthetics). Injected as weighted context; evaluated by
  expert acceptance and `chosen ≻ rejected` pairs (RLHF/RLAIF).
- **Fact → evidence-gated knowledge.** A claim about the world. Stored under a
  **hard-evidence invariant** (no claim without a real source); the invariant is
  itself a guardrail on the knowledge channel.

**Dual-use identity.** The key economy of the framework: a verifiable rule is *one*
artifact with two uses separated only in time.

```
   expert rule ──compile──▶ scorer(run) → {pass/fail, score ∈ [-1,1]}
                               │                    │
                       inference time         training time
                        (GATE: block/           (REWARD: GRPO
                         flag/auto-fix)           term)
```

Authoring a rule once yields both enforcement and a learning signal, chosen by the
checkability test, not re-specified per layer.

## 4. A gate-family taxonomy for scientific agents

The verifiable channel is not monolithic. It decomposes into eight families, each
with a distinct verifier shape. Grouping matters because (i) an expert rule maps to
exactly one family, so classification becomes a choice from a small menu rather than
free-text interpretation; and (ii) it exposes precisely which families a given
reward interpreter covers.

| # | Gate family | Checks | Science / drug-dev examples | Verifier shape |
|---|---|---|---|---|
| G1 | **Threshold** | measured value vs cutoff with an operator | FDR < 0.05; hERG IC50 ≥ 10 µM; mapping ≥ 80%; coverage ≥ 30×; MW ≤ 500; TPSA ≤ 140 | numeric compare `{field, op, value}` |
| G2 | **Canonical / enum** | param equals a controlled-vocab value (post alias-normalization) | genome = GRCh38; strandedness = reverse (dUTP); aligner ∈ {STAR, salmon}; organism alias → canonical | exact-match / set-membership on the param |
| G3 | **Motif / substructure** | required pattern present, banned one absent | keep RGD motif; no PAINS/toxicophore; valid SMILES; required cyclization cysteines; no N-glyc sequon | regex / substring; chemistry → RDKit SMARTS |
| G4 | **Schema / format** | output conforms to a structure | valid VCF/BAM/FASTQ; JSON valid; required report sections; units present | schema/format validator |
| G5 | **Set-membership / grounding** | selection is one of the *provided* candidates | routed workflow ∈ DB; gene ∈ HGNC; accession resolves; off-catalog → reject | membership against a provided set |
| G6 | **Relational** | fields agree with each other | paired-end ⇒ 2 FASTQs; `single_end` flag matches file count; samplesheet rows match inputs; dose units match value | multi-field predicate |
| G7 | **Procedural / ordering** | steps occur in a required order | QC before alignment; dedup before variant-call; normalize before DE | DAG/order check over the plan |
| G8 | **Provenance / evidence** | every claim/number traces to a real source | citation integrity; inputs are real HDAs; no fabricated PMID | provenance check |

Anything outside G1–G8 is, by construction, the soft-preference channel or the
fact channel. The taxonomy's value is twofold: it is the **authoring menu** for
experts and the **coverage checklist** for any reward/gate engine. In our
experience the densest, highest-value scientific expertise lives in **G1
(threshold), G6 (relational), and G7 (ordering)** — exactly the QC and protocol
knowledge that distinguishes a correct pipeline from a plausible one.

## 5. Reference implementation (BioMate)

We implement the framework in a production bioinformatics platform. The accounting
below separates **[built]**, **[built as X, not yet Y]**, and **[proposed]** to
avoid overclaiming.

**Declarative, non-`eval` rule interpreter [built].** A fixed component vocabulary
— `contains_any`, `contains_all`, `banned`, `regex`, `numeric`, `length_target`,
`json_valid` — each compiled to a `scorer(str) → float ∈ [-1,1]` with a weight, no
arbitrary code, so a rule spec is safe to accept from a user or a project. The
weighted sum is a **composite reward** usable directly as a GRPO `reward_funcs`
callback (TRL GRPOTrainer). Unit tests confirm the interpreter's correctness
(e.g., a spec requiring {dose, mg} and a numeric value, banning "as an AI",
scores a compliant completion +1.5 and a non-compliant one −1.5; `json_valid`,
`regex`, `contains_any` behave as specified). This is the dual-use artifact of §3
realized at the training end.

**Gate-before-score verification layer [built].** Inference-time primitives —
majority-vote/self-consistency, verified-sample (pass@k oracle), consensus, and
**grounded-pick** (a selection must be one of the provided candidates, else reject)
— that any task path wraps its model call with. The platform's QC auto-loop is, in
effect, a running RLVR verifier: it accepts/retries/pivots a run against QC gates.
Grounded-pick is the G5 gate at the harness boundary.

**Edit-pair rule compiler for the soft channel [built].** For regulatory writing,
a deterministic compiler mines expert `chosen` vs `rejected` edit pairs and extracts
preferred citations, banned phrases, and preferred phrases into a per-organization
rule block injected as retrieval context — the soft channel learned from
corrections, no LLM required. Chat-level expert rules enter the prompt as explicit
composer instructions.

**Firewalled, longitudinal evaluation [built].** An evaluation harness with an RSI
scorer designed for held-out, longitudinal, firewalled validation — the guard
against a system inflating its own reward (§7).

**Coverage of the taxonomy by the current interpreter.** Built cleanly: **G3, G4**
(regex/contains/banned/json_valid). Partial: **G2, G5** (text-level matching and
grounded-pick exist; structured param-equality and reward-wired grounding are
gaps). **Not yet covered: G1, G6, G7** — the current `numeric` component only tests
digit-presence, not a thresholded comparison; there is no cross-field predicate and
no order check. Extending the declarative interpreter with `numeric_threshold`, a
relational predicate, and an ordering check — all safe and non-`eval` — is the
concrete engineering step, and it closes exactly the three highest-value families.

**Autonomous rule induction [proposed].** The one missing arc for full RSI (§7):
the system proposing candidate rules from its own run outcomes, each quarantined
until it clears the held-out firewall, then promoted to a gate/reward. Everything
downstream of the proposal already exists.

## 6. Datasets and evaluation

**Is there a public dataset for this?** To our knowledge, and per a targeted
literature search, **no packaged benchmark of bioinformatics expert constraints
with labeled run outcomes exists.** What exists publicly is (a) the *methodology
template* — IFEval / IFBench / IF-RLVR (verifiable constraint + verification
function + RLVR training) and its scientific extensions — and (b) the *raw rule
material*, because most scientific gate rules are already publicly codified:

- **G1/G4 thresholds & formats:** FastQC pass/warn/fail criteria and MultiQC
  reporting; nf-core pipeline QC defaults; the SAM/BAM/VCF/FASTQ format
  specifications.
- **G3 medicinal-chemistry filters:** Lipinski Rule-of-5 (2001), Veber (2002),
  PAINS SMARTS (Baell & Holloway, 2010), Brenk (2008), REOS — shipped as RDKit
  catalogs; Therapeutics Data Commons for ADMET thresholds.
- **G2/G5 vocabularies:** Ensembl/GENCODE genome builds, HGNC gene symbols, NCBI
  Taxonomy — controlled vocabularies with resolvers.
- **G7 ordering / G8 provenance:** nf-core module graphs and Galaxy workflow DAGs;
  ICH/FDA/EMA citation token sets.

**Can we generate a benchmark from public inspiration + our resources? Yes — and it
is roughly half-built.** We adopt the IFBench template (each item = a constraint + a
deterministic verification function, scored for satisfaction and for generalization
to unseen constraints) and instantiate it per gate family using the public rule
sources above as the *constraint source* and our execution-verified corpus as the
*output pool*:

- `protocol_thresholds` (20 cases): protocol-specific QC thresholds with
  `expected_naive_action` vs `expected_biomate_action` and a `VALID/DEFECTIVE`
  expert label — a ready G1/G2 benchmark testing whether protocol-aware gates cut
  false alarms vs universal thresholds.
- `autofix_benchmark` (20 cases): deliberately broken workflows (genome_mismatch →
  G2, missing_input → G6, param_type_error → G4, resource_failure) with error logs
  and expected fixes — a violation→fix set spanning multiple families.
- `qc_governance`, `license_gating`, `param_prefill`, `model_selection`,
  `ind_gold_standard`, `audit_trail_fair` — additional labeled constraint/decision
  data already in the evaluation suite.
- **~1,092 validated real-execution runs** with terminal + S3 artifact evidence,
  graded by an execution grader — the labeled output pool against which gates are
  scored for precision/recall.

**Pre-registered evaluation protocol** (metrics per channel, to avoid conflating
them):

- *Verifiable gates (G1–G8):* precision/recall of each gate on a held-out labeled
  run set — a gate that fires on compliant runs (low precision) is worse than no
  gate. Report per-family, and a **held-out-family** generalization split (train on
  G1/G3/G4, test on unseen G6/G7) mirroring IFBench's unseen-constraint axis.
- *Soft preferences:* expert acceptance rate and edit distance, rule-on vs rule-off;
  `chosen ≻ rejected` win rate.
- *Facts:* fraction of served claims with a resolvable source (evidence invariant)
  and KB agreement.
- *Meta (anti-inflation):* every learned/induced rule validated on data it was not
  derived from, longitudinally, behind the firewall (§7).

What we can report **today** is interpreter correctness (unit-level) and the
existence of the labeled substrate; the large-scale gate precision/recall and any
GRPO learning curve are **future work** (§9).

## 7. Relation to governed recursive self-improvement

The framework's loop is, structurally, recursive self-improvement:

```
   expert feedback ──▶ classify ──▶ compile (gate / preference / fact)
         ▲                                        │
         │                                        ▼
   held-out firewall ◀── evaluate ◀── enforce (gate) + train (reward)
         │                                        │
         └──────────── induce new rules ◀─────────┘   ← the autonomous arc
```

With a human supplying the top arrow, it is human-in-the-loop improvement. Replace
that arrow with the system **inducing** candidate rules from its own run outcomes
and it becomes autonomous RSI. The decisive design point is that **the verifiable
guardrail is simultaneously the improvement target, the measurement instrument, and
the firewall.** Ungoverned self-improvement inflates its own reward and drifts
(the central failure mode across the self-evolving-agents literature); a
verifiable gate cannot be gamed by the policy it scores, and a held-out firewall
prevents an induced rule from being promoted on the data that suggested it. BioMate
already has every layer except the induction arc (§5), and that arc is low-risk to
add *because* the gates and firewall that contain it already exist. This is why a
QC auto-loop being literally "verifiable rewards" is strategic, not incidental: it
is the substrate on which safe RSI can run.

## 8. Discussion

The framework inverts a common assumption. Rather than asking an ever-larger model
to internalize expert judgment implicitly, it externalizes the checkable part of
that judgment into deterministic artifacts that are cheap to run, reproducible,
auditable, and — crucially — reusable as both enforcement and training signal. The
scientific domain is where this pays off most, because its constraints are
unusually checkable. The soft and factual channels remain, handled by their proper
mechanisms (preference learning; evidence-gated retrieval), so the framework does
not pretend everything is verifiable — it routes each thing to the mechanism that
fits it.

## 9. Limitations

- **No large-scale empirical result yet.** This paper contributes a framework,
  taxonomy, reference implementation, and pre-registered protocol. Interpreter
  correctness is unit-tested; gate precision/recall at scale and GRPO learning
  results are future work.
- **The verifier problem persists for soft tasks.** Open-ended narrative quality has
  no deterministic verifier; it stays in the preference channel with its known
  limitations.
- **Domain verifiers needed for parts of G3/G4.** SMILES validity, PAINS matching,
  and file-schema validation require domain checkers (RDKit, format validators)
  beyond the text-level interpreter; these are integration work, not research.
- **Induction is unproven here.** The autonomous arc (§5, §7) is designed but not
  yet wired or evaluated; its safety rests on the firewall, whose adequacy must be
  measured, not assumed.
- **Benchmark labels inherit expert bias.** The `VALID/DEFECTIVE` and expected-fix
  labels are expert annotations; inter-annotator agreement should be reported in the
  benchmarked version.

## 10. Conclusion

Expert feedback becomes durable capability only when it is classified by
checkability and routed accordingly: hard constraints into verifiable guardrails
that double as training rewards, soft judgment into weighted preference, facts into
evidence-gated knowledge. For scientific agents the verifiable channel is unusually
rich, and grouping it into eight gate families makes it authorable and auditable. A
reference implementation exists; a benchmark can be assembled from public rule
sources and an execution-verified corpus; and the resulting loop is a governed form
of recursive self-improvement in which the guardrail is the firewall. The remaining
work is to measure the gates at scale and to wire the induction arc behind that
firewall.

---

## References

*(Author/title/year are given for verifiability; where a canonical arXiv/venue URL
is known it is included. To be completed to house style in the submission version.)*

1. Zhou et al. **Instruction-Following Evaluation for Large Language Models (IFEval).** 2023. arXiv:2311.07911.
2. Pyatkin, Malik, Graf, Ivison, Huang, Dasigi, Lambert, Hajishirzi. **Generalizing Verifiable Instruction Following (IFBench / IF-RLVR).** NeurIPS 2025 Datasets & Benchmarks. https://proceedings.neurips.cc/paper_files/paper/2025/file/46499a0622ecf568b72d17b61e45dbd5-Paper-Datasets_and_Benchmarks_Track.pdf
3. Dong et al. **Self-play with Execution Feedback (AutoIF).** 2024. arXiv:2406.13542.
4. **ComplexConstraints and Beyond: Expert Rubrics for RLVR.** 2026. arXiv:2606.09118.
5. **SciMIF: Understanding Multimodal Instruction Following in Scientific Domains.** 2026. arXiv:2608.25973.
6. Bai et al. **Constitutional AI: Harmlessness from AI Feedback (RLAIF).** 2022. arXiv:2212.08073.
7. Yuan et al. **Self-Rewarding Language Models.** 2024. arXiv:2401.10020.
8. Zelikman et al. **Self-Taught Optimizer (STOP): Recursively Self-Improving Code Generation.** 2024. arXiv:2310.02304.
9. Fernando et al. **Promptbreeder: Self-Referential Self-Improvement via Prompt Evolution.** 2024. arXiv:2309.16797.
10. Shinn et al. **Reflexion: Language Agents with Verbal Reinforcement Learning.** 2023. arXiv:2303.11366.
11. Wang et al. **Voyager: An Open-Ended Embodied Agent with Large Language Models.** 2023. arXiv:2305.16291.
12. Lightman et al. **Let's Verify Step by Step (Process Reward).** 2023. arXiv:2305.20050.
13. Schmidhuber. **Gödel Machines: Self-Referential Universal Problem Solvers.** 2003.
14. **A Survey of Self-Evolving Agents.** 2025. arXiv:2507.21046.
15. Baell & Holloway. **New Substructure Filters for Removal of Pan Assay Interference Compounds (PAINS).** J. Med. Chem., 2010.
16. Lipinski et al. **Experimental and computational approaches to estimate solubility and permeability (Rule of 5).** Adv. Drug Deliv. Rev., 2001.
17. Veber et al. **Molecular properties that influence oral bioavailability.** J. Med. Chem., 2002.
18. Ewels et al. **MultiQC: summarize analysis results for multiple tools and samples.** Bioinformatics, 2016.
19. Ewels et al. **The nf-core framework for community-curated bioinformatics pipelines.** Nat. Biotechnol., 2020.
20. Huang et al. **Therapeutics Data Commons (TDC).** 2021.

---

### Internal cross-references (not for the external version)
- Companion design note: `docs/20261027_EXPERT_FEEDBACK_RULES_GUARDRAILS_RSI.md`
- Reference implementation: `backend/lib/galaxy/ai/ml_training/trl_trainer.py` (composite reward), `backend/lib/galaxy/ai/verification_layer.py` (gate-before-score), `backend/lib/galaxy/ai/drug_discovery/org_rule_compiler.py` (edit-pair compiler), `frontend/server/chat-context.ts` (composer instructions).
- Benchmark substrate: `evaluation/datasets/{protocol_thresholds,autofix_benchmark,qc_governance,license_gating,param_prefill,model_selection,ind_gold_standard,audit_trail_fair}`.
