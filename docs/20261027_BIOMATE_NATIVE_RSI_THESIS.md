# A Platform-Native RSI Formulation for BioMate

**Date:** 2026-10-27
**Author:** Yaoyun Zhang (BioMate)
**Status:** Design thesis. This is **our own** recursive-self-improvement formulation
— not an adoption of DGM / SICA / Harness2 / ScienceBuddy. Those are single-substrate
engines validated on software benchmarks; the four properties below are things our
platform has and they do not, and together they define an RSI loop that is ours.

---

## 0. The claim

Every open-source RSI system we surveyed improves **one substrate** (code, a harness,
or weights) against **one cheap verifier** (unit tests, SWE-bench) with an **iid
held-out** check. BioMate is a lab-coupled, multi-tenant *execution* platform with
(i) four distinct improvable substrates, (ii) a cost-ordered verifier ladder topped by
a physical, non-gameable measurement, (iii) an improvement unit that is a
human-auditable rule rather than an opaque diff, and (iv) failures that are already
classified into gate families that *name the thing to repair*. Our RSI is defined by
exploiting all four. We call it **Substrate-Routed, Verifier-Laddered self-improvement
(SRVL)** — handle negotiable.

The one-line differentiator: **DGM asks "what code change raises the SWE-bench score?"
SRVL asks "which of my four substrates is the bottleneck for this failure *class*, what
is the cheapest verifier that can confirm a fix, and does the fix generalize across
*biology* — not across iid task instances?"**

---

## 1. Pillar A — Multi-substrate RSI with gate-family-routed repair

BioMate has **four** improvable substrates, each already real:

| Substrate | What it is | Component |
|---|---|---|
| **Catalog** | 4,210 workflows / 12,312 tools; composer can *generate + index* new ones | `UnifiedWorkflowSearch`, composer `generate_workflow`, rsi_scorer Axis B (`capability_growth`) |
| **Rule-KB** | expert rules, org edit-pairs, QC profiles, few-shot exemplars | `org_rule_compiler`, `verification_layer`, composite `reward_spec`, `checker_overrides` |
| **Weights** | LoRA / SFT / DPO / GRPO adapters per track | Models module `train`/`adapt`/`optimise`, `trl_trainer`, export-and-verify gate |
| **Harness** | routing, decomposition, the composer/lane-arbiter itself | `pattern_router` (flag-off, dormant), lane arbiter, decomposition SFT |

**The novel move:** the *repair site is selected, not fixed.* Our gate-family taxonomy
(G1–G8) classifies a failure, and each class names which substrate to improve:

| Failure class (gate family) | Diagnosis | Repair substrate |
|---|---|---|
| G5 off-catalog / unroutable intent | capability gap | **Catalog** — generate+index a new workflow |
| G1 threshold miscalibration (false QC alarm) | wrong profile | **Rule-KB** — add/adjust a QC-profile rule |
| G2 canonical/alias error (hg19→hg38) | missing normalization | **Rule-KB** — add an alias rule (deterministic) |
| decomposition / routing error | reasoning gap | **Weights/Harness** — SFT the composer; wire `pattern_router` |
| G6/G7 relational/ordering violation | plan structure | **Harness** — plan-graph constraint |

No surveyed RSI system does **failure-class → repair-site routing**; they improve a
single substrate blindly. Ours is possible *because* the gate families give a typed
diagnosis. (`autofix_benchmark` already labels failure classes — genome_mismatch,
missing_input, param_type, resource — this generalizes that to a repair router.)

## 2. Pillar B — The verifier ladder (cheap → physical, non-gameable)

Code RSI has one cheap verifier. A lab-coupled scientific platform has a **ladder** of
increasing cost and *decreasing gameability*:

```
  L0  Declarative gates (G1–G8)         free, instant, deterministic
  L1  Real execution (AWS Batch)        minutes, $, terminal + S3 evidence (execution grader)
  L2  In-silico physics (docking/FEP)   hours, $$, approximate truth
  L3  Wet-lab assay / expert sign-off   weeks, $$$, PHYSICAL ground truth — cannot be reward-hacked
```

**The novel RSI formulation under this ladder:**
1. **Cost-aware escalation.** A self-improvement proposal is filtered at L0 for free;
   only survivors spend L1 execution; only the best spend L2/L3. The scarce physical
   budget is never wasted on proposals a free gate could kill.
2. **Learned cross-rung calibration.** The loop learns *which cheap-verifier signals
   predict the expensive physical truth* — e.g., which L0/L2 scores correlate with an
   L3 binding/permeability result. This calibration is itself a trainable capability,
   and it is where most of the value is: it lets the system **spend L3 optimally**.
3. **Non-gameability as a feature.** Pure self-play RSI (self-generated rewards) can
   reward-hack its own judge; a physical L3 verifier cannot be gamed by the policy it
   scores. This is a *safety* advantage unique to lab-coupling — at the cost of a slow,
   low-bandwidth top rung (hence hybrid SDL, never-automate-synthesis).

This is directly our peptide program (§5) and has no analog in software-benchmark RSI.

## 3. Pillar C — The improvement unit is an auditable verifiable rule

DGM promotes a **code diff**; self-rewarding LMs promote a **weight delta**. Both are
opaque — unreviewable by a domain expert, a non-starter in regulated science (IND, GMP,
CRO). SRVL's improvement unit is a **declarative verifiable rule** (a composite-reward
component / QC-profile entry): human-readable, expert-approvable, and **dual-use** — the
same artifact is an inference gate (immediate, deterministic, auditable) *and* a GRPO
reward term (trains the weights). Consequences unique to us:

- **Expert-in-the-loop promotion.** An induced rule can be shown to a domain expert and
  approved/rejected before it governs or trains anything — the regulated-science trust
  requirement that opaque self-modification cannot meet.
- **Two improvements per artifact.** One accepted rule upgrades both inference behavior
  and the training signal, with no separate engineering.
- **Reversible, attributable.** A rule is a row with provenance; a bad one is deleted,
  not surgically un-trained.

## 4. Pillar D — A biology-structured leakage firewall

Our `rsi_scorer.py` already makes the leakage firewall its one non-negotiable rule
(burned once: decomposition_v2, 0.73→0.016). The novel extension: the held-out split is
along **biologically meaningful axes**, not iid task instances — because "the model
improved" must mean *it generalizes in the dimension that matters*:

- **held-out target** (leave-one-target-out — the cyclic cross-target bound, BoltzGen LOTO),
- **held-out scaffold/chemistry** (not just new molecules of a seen series — the circularity trap, feature⊂target),
- **held-out assay / modality**,
- **held-out org** (a rule promoted to the shared catalog must help an org whose edit-pairs were *not* used — federated generalization),
- **degree/annotation-depth null** (score vs a connectivity-matched null, not raw gold).

Code RSI holds out task instances; we hold out *biology*. This is the structural
anti-circularity discipline that keeps SRVL honest where our domain's correlations are
treacherous (the renal ρ=0.27 charge artifact is the cautionary tale).

## 5. Worked instance — the peptide closed loop IS SRVL

The computational-peptide-generation → wet-lab/expert-feedback loop is the flagship
instance, and it exercises all four pillars:
- **Substrate routing (A):** a binding miss → retrain the scorer (Weights); an
  unsynthesizable proposal → add a medchem rule (Rule-KB); an unreachable motif → grow
  the design catalog.
- **Verifier ladder (B):** generate → L0 medchem/PAINS gates → L1 cofold/execution →
  L2 docking/FEP → L3 synthesis + assay. The loop learns the L2→L3 calibration (our
  standing PK/permeability gap is exactly this calibration problem).
- **Auditable rule unit (C):** "keep RGD; ClogP ≤ X for this series" is an expert-approved
  rule that both gates generation and shapes the REINVENT4/GRPO reward.
- **Biology firewall (D):** improvement must show on a **held-out target** and a
  **held-out scaffold**, or it scores zero — the discipline that separates real
  capability gain from fitting the compounds we happened to make.

**Honest status:** this is an RSI *design*, instantiated against real components, not a
measured RSI *result* — the loop is currently synthetic-only and the L2→L3 calibration
is unproven. Claiming a measured RSI gain today would be the exact leakage inflation (D)
forbids. SRVL is the thesis we build and measure toward.

## 6. What is built vs proposed

| Piece | State |
|---|---|
| Gate families G1–G8 + composite reward (L0, dual-use rule) | **built** (G1/G3/G4/G6/G7 components; G2/G5 partial) |
| Execution grader L1 (terminal + S3) | **built** |
| In-silico L2 (docking/FEP) | **built** (GROMACS/Batch) |
| Wet-lab L3 + SDL | **hybrid, in program** (αvβ6/GRPR) |
| Four substrates each individually improvable | **built** (catalog gen, org_rule_compiler, Models module, pattern_router) |
| rsi_scorer + leakage firewall | **built** (iid + capability + self-improve axes) |
| **Substrate-routing repair selector (Pillar A)** | **proposed** — the new control piece |
| **Cross-rung L0–L3 calibration learner (Pillar B)** | **proposed** — the high-value piece |
| **Biology-axis firewall splits (Pillar D)** | **partially built** (LOTO exists; scaffold/assay/org splits to formalize) |
| Autonomous rule induction behind the firewall | **proposed** (the arc that closes SRVL) |

The engine pieces exist and are dormant/scattered; SRVL is the **controller + the two
proposed learners + the biology firewall** that make them one governed loop. That is our
contribution, and it is not a copy of anything surveyed.

## 7. Why this is defensible as ours (contrast table)

| | DGM / SICA | Harness2 | ScienceBuddy | **SRVL (ours)** |
|---|---|---|---|---|
| Substrate improved | code | harness | harness + weights | **4, routed by failure class** |
| Verifier | unit tests | self-probe | Val + GRPO | **L0–L3 ladder, physical top** |
| Improvement unit | code diff | harness variant | harness + weights | **auditable dual-use rule** |
| Held-out | iid instances | iid | iid | **biology axes (target/scaffold/assay/org)** |
| Regulated-science fit | no (opaque) | no | no | **yes (expert-approvable rules)** |
| Lab coupling | no | no | no | **yes (wet-lab L3)** |

---

## 8. Next steps
1. Specify the **substrate-routing repair selector** (gate-family → repair-site policy)
   as a concrete module over the existing autofix/gate diagnostics.
2. Formalize the **L0–L3 calibration learner** against the peptide program (the L2→L3
   permeability/PK gap is the first target).
3. Add the **biology-axis firewall splits** to `rsi_scorer.py` (scaffold/assay/org).
4. Elevate this thesis to the center of the manuscript (§7 reframed around SRVL;
   DGM/Harness2/ScienceBuddy become related work we extend, not adopt).

Cross-refs: `docs/20261027_MANUSCRIPT_verifiable_guardrails_scientific_agents.md`,
`docs/20261027_EXPERT_FEEDBACK_RULES_GUARDRAILS_RSI.md`,
`docs/20261021_HARNESS2_SCIENCEBUDDY_RSI_HANDOFF.md`, `evaluation/scorers/rsi_scorer.py`.
