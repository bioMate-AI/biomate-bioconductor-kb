# Expert Feedback → Rules → Guardrails → Evaluation, and its relation to RSI

**Date:** 2026-10-27
**Author:** Yaoyun Zhang (with Claude)
**Status:** Design note + landscape survey. Answers the question: *"Expert
feedback/instructions are really useful. How do we handle them? Do they need to be
translated into guardrails? How do we evaluate them? Isn't this relevant to RSI
(recursive self-improvement)?"*

---

## 0. TL;DR

1. **Do not treat expert feedback as one thing.** Classify each piece by *"can a
   program decide, from a run's outputs, whether this was honored?"*
   - **Yes, hard** → a **guardrail / verifiable gate** (deterministic, enforced,
     "gate before score").
   - **Yes-ish, soft** → a **weighted context/preference** injected into the model
     (not pass/fail).
   - **No (it's a fact)** → an **evidence-gated knowledge entry** (every claim
     carries a source).
2. **Only the hard ones become guardrails.** Forcing a judgment call into a hard
   gate manufactures false positives; leaving a checkable constraint as "advice"
   lets it be ignored.
3. **Evaluation falls out of the classification.** Verifiable rules evaluate
   themselves (violation / false-positive rate on held-out labeled runs);
   preferences evaluate by expert acceptance / preference pairs; knowledge
   evaluates by the evidence invariant.
4. **Yes — this is exactly RSI, in its *governed* form.** The loop *expert
   feedback → compiled rule → verifiable gate → reward → updated behavior* is a
   recursive self-improvement loop. The verifiable gate is the thing that makes
   the loop safe to close: it is both the improvement signal and the firewall
   against reward-hacking/drift. BioMate already has every layer **except** the
   autonomous rule-*induction* step; adding that, behind the existing held-out
   firewall, is the RSI upgrade.

---

## 1. The three channels of expert feedback

A domain expert's feedback is heterogeneous. Three worked examples from our own
domains:

| Expert says… | Nature | Channel |
|---|---|---|
| "Human genome means GRCh38, FDR < 0.05, never include PAINS, the macrocycle must keep the RGD motif, never emit 'as an AI'." | **Hard constraint** — checkable from params/outputs | **Guardrail / gate** |
| "Put findings first, ≤ 200 words, 300-dpi figures, cite ICH over FDA where both apply." | **Preference** — no pass/fail | **Weighted context / soft reward** |
| "hERG is safe at ≥ 10 µM; αvβ6 binds the RGD motif; this cell line is CAL-33." | **Domain fact** | **Evidence-gated KB** |

The single discriminating question is the **checkability test**:

> *Can a deterministic program, looking only at the run's parameters and outputs,
> decide whether this rule was satisfied?*

- **Yes** → it can be a **gate** (and therefore a **verifiable reward** — the two
  are the same object used at two times: enforcement at inference, reward at
  training).
- **No** → it is a **preference** (reaches the model as weighted context, judged
  by a human/judge) or a **fact** (enters the KB under provenance).

This is the same split the RL literature now draws between **RLVR**
(reinforcement learning with *verifiable* rewards — rule/verifier-computed,
reproducible, resistant to reward-hacking) and **RLHF/scalar-RM** (learned
judge, needed when no reference exists) — see the 2025 state-of-RL summary
([Turing Post](https://www.turingpost.com/p/stateofrl2025),
[RLVR framework](https://www.emergentmind.com/topics/verifiable-rewards-rlvr)).
The open hard problem there is identical to ours: *verifiers cover math, code and
structured output cleanly; open-ended tasks still need a judge* ("the verifier
problem" — [Mitra 2026](https://subhadipmitra.com/blog/2026/rlvr-beyond-math-code/)).
Our advantage is that **bioinformatics is unusually verifiable**: a threshold
crossed, a param equal to a canonical value, a QC metric, a file schema — most
expert constraints in our domain *are* checkable, so most of them can be real
gates, not just advice.

### 1.1 The verifiable channel is not one thing — group it into gate families

"Checkable" splits into a small number of **gate families**, each with a distinct
verifier shape. Grouping them matters for two reasons: (i) an expert's rule maps
cleanly to one family, so authoring/classification can be a dropdown, not free
text; and (ii) it exposes exactly which families our composite-reward interpreter
(`trl_trainer._composite_component`) already covers and which are gaps.

| # | Gate family | What it checks | Bioinformatics / drug-dev examples | Verifier mechanism | Composite-reward coverage |
|---|---|---|---|---|---|
| G1 | **Threshold** | a measured value vs a cutoff with an operator | FDR < 0.05; hERG IC50 ≥ 10 µM; mapping rate ≥ 80%; coverage ≥ 30×; MW ≤ 500; TPSA ≤ 140; dup < 20% | numeric compare `{field, op, value}` | **GAP** — current `numeric` only tests *digit-presence*, not a comparison; needs a real `numeric_threshold` component |
| G2 | **Canonical / enum value** | a param equals a value from a controlled vocab (after alias normalization) | genome = GRCh38; strandedness = reverse (dUTP); aligner ∈ {STAR, salmon}; organism alias → canonical | exact-match / set-membership on the **param** | partial — `contains_any` matches on text, but structured param-equality is a gap |
| G3 | **Motif / substructure presence–absence** | a required pattern present, a banned one absent | keep RGD motif; no PAINS / toxicophore; valid SMILES; required cysteine pair for cyclization; no N-glyc sequon | `regex` / `contains_all` / `banned`; chemistry needs an RDKit-backed checker | **built** for text patterns; chemistry validity (SMILES/PAINS) is a **domain-verifier gap** |
| G4 | **Schema / format validity** | output conforms to a structure | valid VCF / BAM / FASTQ; JSON valid; required report sections; units present | schema/format validator | `json_valid` **built**; file-schema validators are a **gap** |
| G5 | **Set-membership / grounding** | a selection is one of the *provided* candidates | routed workflow exists in DB; gene symbol ∈ HGNC; accession resolves; off-catalog = reject | `grounded_pick` (already in `verification_layer.py`) | **built as a gate**, not yet wired as a reward term |
| G6 | **Relational / cross-field consistency** | fields agree with each other | paired-end ⇒ 2 FASTQs; `single_end` flag matches file count; samplesheet rows match inputs; dose units match the value | multi-field predicate | **GAP** — no component |
| G7 | **Procedural / ordering** | steps occur in a required order | QC before alignment; dedup before variant-call; normalize before DE | DAG/order check over the run plan | **GAP** — no component |
| G8 | **Provenance / evidence** | every claim/number traces to a real source; inputs are real HDAs; no fabricated PMID | citation-integrity; hard-evidence invariant; "inputs are Galaxy HDAs" | provenance check | **built as an invariant**, not yet a reward term |

Everything that does **not** land in G1–G8 is, by construction, the **soft /
preference** channel (style, ordering of prose, tone, figure aesthetics) — judged
by acceptance, not a verifier (§3b) — or the **fact** channel (§3c).

**The payoff of grouping:** the composite reward today cleanly covers **G3 and G4**
(regex / contains / banned / json_valid), partly **G2 and G5**, and is **missing the
three highest-value bioinformatics families — G1 (threshold), G6 (relational),
G7 (ordering)**. Those three are where most QC and protocol expertise actually
lives. Extending the declarative interpreter with `numeric_threshold`, a
cross-field predicate, and an order check — all safe, non-`eval` — is the concrete
next step, and it is the same schema the §5 unification calls for.

---

## 2. Do they need to be translated into guardrails? — Only the hard ones

**Translate → guardrail** iff the rule passes the checkability test. Mechanism:
a **declarative, non-`eval` interpreter** that compiles a rule into a scorer.
We already built exactly this on the training side
(`backend/lib/galaxy/ai/ml_training/trl_trainer.py::_composite_component`): a
fixed set of safe component kinds — `contains_all`, `contains_any`, `banned`,
`regex`, `numeric`, `length_target`, `json_valid` — each compiled to a
`scorer(str)->float` with a weight, no arbitrary code, so a `reward_spec` is safe
to accept from a user or a project rule. The same compiler output is usable in
two places:

- **Inference time** → a **gate**: block / flag / auto-fix the run when the
  component fails (this is "gate before score" — reject off-spec output *before*
  any quality scoring, so a polished-but-non-compliant answer never wins).
- **Training time** → a **verifiable reward**: the component's score is a GRPO
  reward term (the composite reward, now live in `trl_trainer`).

**Do NOT translate → guardrail** when the rule is a judgment call. Those go to:
- **Soft context**: compiled to a per-scope RAG block and injected into the
  prompt. We already do this for regulatory writing
  (`backend/lib/galaxy/ai/drug_discovery/org_rule_compiler.py`): it reads the
  expert's *edit pairs* (`chosen` vs `rejected`), extracts `preferred_citations`
  / `banned_phrases` / `preferred_phrases` deterministically, and writes a
  per-org YAML block that `_build_rag_context` injects. And for chat, the
  Instructions-page rules are injected as "Composer instructions for this chat"
  (`frontend/server/chat-context.ts`).
- **Evidence-gated KB**: facts enter a provenance-tiered store; the **hard-
  evidence invariant** (no claim without a real source) is itself a guardrail on
  the *knowledge* channel.

The practical rule of thumb: **a rule that fires on a good run, or never fires,
is a bad rule** — and the only way to know that is to measure it, which is §3.

---

## 3. How to evaluate expert feedback

Evaluation method is determined by channel — you cannot evaluate a preference the
way you evaluate a gate.

### 3a. Guardrails (verifiable) — evaluate by violation/false-positive rate
A gate is self-evaluating: it returns pass/fail on every run. Hold out a **labeled
set** of runs known to satisfy / violate, and measure the gate's **precision /
recall** (how often it correctly fires, how often it fires on a compliant run).
This is exactly the posture of our autofix / execution scorecard
(`evaluation/datasets/autofix_benchmark/`) and the QC auto-loop, which
`backend/lib/galaxy/ai/verification_layer.py` names outright as *"our QC auto-loop
already is 'verifiable rewards'"*. A gate with poor precision (fires on good runs)
is worse than no gate — it trains the system to satisfy a wrong constraint.

### 3b. Preferences (soft) — evaluate by acceptance / preference pairs
No ground truth, so the **expert's own edits are the eval signal**:
`chosen ≻ rejected` pairs (the DPO/`org_rule_compiler` mechanism). Metric: does
expert **acceptance rate** go up, and **edit distance** go down, with the rule on
vs off? This is the RLHF/RLAIF side of the house — and where **Constitutional AI /
RLAIF** (principles → model-generated feedback → preference training; Bai et al.
2022) is the canonical pattern for scaling a small set of expert principles into a
large preference signal without a human labeling every sample.

### 3c. Knowledge — evaluate by the evidence invariant + KB agreement
A fact is "good" iff (i) it traces to a real source (provenance check — a
guardrail on the KB) and (ii) the served answer agrees with the KB. Our
citation-integrity requirement is this evaluator.

### 3d. The meta-metric that protects all three: **held-out, longitudinal, firewalled**
Any rule learned/accepted on data must be validated on data it was **not** derived
from. This is non-negotiable for self-improvement (§4): without a firewall, a
system that writes its own rules will inflate its own reward. Our evaluation stack
already carries an **RSI scorer with a longitudinal + firewall design** for exactly
this. The failure mode is documented in the literature as **"memory reward
inflation"** in self-improving agents
([arXiv 2608.00017](https://arxiv.org/pdf/2608.00017)) and as reward-hacking that a
good harness drives *down* over an autonomous run (AIDE2: reward hacking 55% → 32%
across an 8-day self-improvement run, gains transferring to held-out benchmarks —
reported in [arXiv 2603.25681](https://arxiv.org/pdf/2603.25681)).

---

## 4. Why this *is* RSI — and what BioMate is missing

**Recursive self-improvement (RSI)** is a system that improves its own future
performance, then uses the improved version to improve further. Formal root:
Schmidhuber's **Gödel machine** (2003) — rewrite your own code once you can *prove*
the rewrite raises future utility. With LLMs the idea became practical at the
**scaffolding** level: an improver program applied to itself — **STOP /
Self-Taught Optimizer** (Zelikman et al. 2024), **Promptbreeder** (Fernando et al.
2024) — and at the **weights** level via **self-rewarding language models** (the
model is its own judge; iterating on its own scores improves answers *and* the
scorer). The 2025 surveys catalogue these by *which layer gets rewritten* —
runtime logic, workflow graph, tool set, or weights
([Self-Evolving Agents survey, arXiv 2507.21046](https://arxiv.org/html/2507.21046v4);
[Agentic Reasoning survey, arXiv 2601.12538](https://arxiv.org/pdf/2601.12538);
[awesome-RSI list](https://github.com/natnew/awesome-recursive-self-improvement)).

**The expert-feedback loop is RSI with a human in the loop:**

```
   expert feedback ──▶ classify ──▶ compile (rule / preference / fact)
         ▲                                        │
         │                                        ▼
   held-out firewall ◀── evaluate ◀── enforce (gate) + train (reward)
         │                                        │
         └──────────── induce new rules ◀─────────┘   ← the autonomous arc
```

- Replace the human at the top with the system **inducing rules from its own run
  outcomes** and you have *autonomous* RSI. That is precisely **rule induction**
  (the cyclic-peptide session's `rule_induction.py` + `experience_kb.py` +
  `acceptance_gate.py` prototypes) and the self-evolving/self-rewarding line in the
  survey.
- **The guardrail/verifiable-reward is the thing that makes the loop safe to
  close.** RSI without a verifiable signal drifts and reward-hacks (the central
  risk in every survey). A verifiable gate is simultaneously (a) the improvement
  target, (b) the measurement, and (c) the firewall. This is why our QC auto-loop
  being "verifiable rewards" is strategically central, not incidental: **it is the
  substrate on which safe RSI can run.**

**What BioMate already has (the loop is 80% built, scattered across layers):**

| RSI layer | BioMate component | State |
|---|---|---|
| Expert feedback → soft rules | `org_rule_compiler.py` (edit-pair mining → per-org RAG block) | built |
| Chat-level rules injection | `chat-context.ts` "Composer instructions" + Instructions-page | built |
| Hard rule → gate | `verification_layer.py` (gate-before-score, grounded_pick, verified_sample) + QC auto-loop | built |
| Hard rule → trainable reward | `trl_trainer.py` composite reward (declarative, safe interpreter) | built (this session) |
| Memory of outcomes | `backend/lib/galaxy/ai/memory/agentic_memory.py` | built |
| Held-out / firewall eval | evaluation RSI scorer (longitudinal + firewall) | built |
| **Autonomous rule induction** | cyclic `rule_induction.py` (prototype, other worktree) | **NOT wired into production** |

**The one missing piece is the autonomous arc:** the system proposing its own
candidate rules from run outcomes, each proposal **quarantined** until it clears
the held-out firewall, then promoted to a gate/preference. Everything downstream of
that proposal (compile → enforce → reward → evaluate) already exists. This is the
concrete RSI upgrade, and it is low-risk *because* the firewall and the verifiable
gates are already there to contain it.

---

## 5. Recommendation

1. **Unify the three scattered rule channels behind one `reward_spec`/rule schema.**
   The composite-reward component vocabulary (`contains_all`/`banned`/`regex`/
   `numeric`/…) is already a safe, declarative rule language. Make the
   Instructions-page rules, `org_rule_compiler` output, and the GRPO `reward_spec`
   all emit/consume **the same schema**, so one expert rule simultaneously yields a
   gate (inference), a reward term (training), and a context line (soft) — chosen by
   the checkability test, not re-authored per layer.
2. **Classify at authoring time.** When an expert enters a rule on the
   Instructions page, run the checkability test and tag it `gate` / `preference` /
   `fact`. Store the tag; it determines enforcement *and* evaluation.
3. **Always evaluate on a firewalled held-out set** before a rule is promoted —
   especially any rule the system induces itself. Reuse the RSI scorer.
4. **Wire rule-induction last, behind the firewall.** This is the step that turns
   the human-in-the-loop improvement loop into governed RSI. Do it only once 1–3
   are in place, because they are its safety rails.

---

## 6. Open items / cross-refs

- **Pending (separate thread):** the Models e2e A5/A6 failures — retrain submit
  returns `[Errno 13] Permission denied: '/data'` on dev (worker lacks write on
  `/data`); fix is a writable output path or `/data` permissions, then re-run
  `scripts/e2e_models_tracks.sh`.
- Related internal docs: `docs/20261027_ML_DL_ALGORITHM_CAPABILITY_STATUS.md`
  (ML/DL capability matrix, composite reward), the cyclic-peptide KB survey
  (experience_kb / acceptance_gate / rule_induction / RLVR reward), and
  `docs/20261020_*` ScienceBuddy dig (self-improve listed as a product gap).

### Sources
- [State of Reinforcement Learning 2025: RLVR, GRPO, RLHF — Turing Post](https://www.turingpost.com/p/stateofrl2025)
- [Verifiable Rewards (RLVR) Framework — Emergent Mind](https://www.emergentmind.com/topics/verifiable-rewards-rlvr)
- [RLVR Beyond Math and Code: The Verifier Problem Nobody Has Solved — Mitra 2026](https://subhadipmitra.com/blog/2026/rlvr-beyond-math-code/)
- [A Survey of Self-Evolving Agents — arXiv 2507.21046](https://arxiv.org/html/2507.21046v4)
- [A Survey of Agentic Reasoning Toward Recursively Self-Improving Agents — arXiv 2601.12538](https://arxiv.org/pdf/2601.12538)
- [Self-Improvement of LLMs: Technical Overview and Future Outlook — arXiv 2603.25681](https://arxiv.org/pdf/2603.25681)
- [Memory Reward Inflation in Self-Improving LLM Agents — arXiv 2608.00017](https://arxiv.org/pdf/2608.00017)
- [awesome-recursive-self-improvement — GitHub](https://github.com/natnew/awesome-recursive-self-improvement)
- Foundational, by name: Schmidhuber (Gödel machine, 2003); Zelikman et al. STOP / Self-Taught Optimizer (2024); Fernando et al. Promptbreeder (2024); self-rewarding language models (2024); Bai et al. Constitutional AI / RLAIF (2022).
