# The benchmarks every "AI for biology" company quotes are measuring the wrong thing

*Opinion. Public task benchmarks — BixBench, BiomniEval1, SGI-Bench — measure one slice of capability well: how often a model returns the right answer to a curated question. They miss every problem that actually breaks agentic AI when it enters a real pharma program. The AstraZeneca Molecular AI team named those problems publicly last week. This post argues that the evaluation framework the industry needs is product-level, not task-level — and shows what BioMate has been building on that thesis for the last year.*

---

## What public benchmarks measure, and what they don't

Walk through the AI-for-biology pitch decks of 2026 and you'll see the same three or four numbers:

- **BixBench** — bioinformatics multiple-choice and execution scores
- **BiomniEval1** — biomedical QA (Biomni's own benchmark)
- **SGI-Bench** — scientific general intelligence
- **MMLU-Genetics / Med** — medical knowledge

Every company puts their best score in their headline.

Here's what those benchmarks measure: *given a fixed question with a known correct answer, how often does the model return it.* That is one slice of capability. It is a useful slice.

Here's what those benchmarks do **not** measure:

- Whether the agent **invents** a tool that doesn't exist.
- Whether the agent **emits parameters** that are type-valid but semantically wrong (`n_steps: 100` when the user said 100 nanoseconds).
- Whether the agent **selects the right workflow** out of a 2,000+ catalog when the question is ambiguous.
- Whether the agent **stabilizes a long-running session** without dragging stale assumptions across turns.
- Whether the agent **closes the loop** when a QC gate fails, or just reports "done" with bad output.
- Whether the agent **leaves a regulatable audit trail** — predictions, simulations, real-world outcomes, sign-offs.
- Whether the agent **knows when it doesn't know** and refuses cleanly.

These are not edge cases.

Two weeks ago, the AstraZeneca Molecular AI team — Jiazhen He, Helen Lai, Lakshidaa Saigiridharan, Gian Marco Ghiandoni, K. Jenei, Umur Gokalp, Ajsa Nukovic, Ola Engkvist, Jon Paul Janet, and Samuel Genheden — published ["Democratising real-world drug discovery through agentic AI"](https://doi.org/10.1016/j.drudis.2026.104605) in *Drug Discovery Today* (doi: 10.1016/j.drudis.2026.104605). They publicly named the engineering problems their **ChatInvent** system hit when it entered real drug discovery production:

**Context explosion. Tool hallucination. Schema mismatch. Memory corruption. Workflow instability.**

Plus six capability pillars the Agent era requires: **tool orchestration, evaluation, traceability, governance, human-in-the-loop, memory.**

None of these show up on BixBench. None show up on BiomniEval1. None show up on MMLU.

That is the gap between *demo-grade* and *production-grade* AI in pharma. And it is not closing by itself.

---

## Why public benchmarks systematically miss the production failures

Three structural reasons.

### 1. Curated questions hide ambiguity

Public benchmark questions are clean. The answer key is fixed. The model either matches or doesn't.

Real pharma queries are dirty. "Compare my compound to FDA-approved drugs" maps to six different workflow chains depending on what the user actually means. "Simulate this protein in solvent" needs a dozen parameter decisions. The benchmark has no representation for *the agent asked for clarification and the user approved* — which is the right answer half the time.

### 2. Task accuracy ignores tool grounding

A model can give a correct-sounding answer while citing a fabricated paper or invoking a non-existent tool. The benchmark grader looks at the final answer string. It does not check whether the citation is real or whether the tool exists.

The most dangerous AI failure in regulated R&D — confidently producing a record that points to a tool that never ran on data that was never produced — is invisible to a string-match grader.

### 3. One-shot scoring hides instability

The model is asked one question, gives one answer, gets one score. There is no turn 8. No workflow that came back failing QC. No regulator asking six weeks later why the dose was 0.1 mg/kg. No standing user correction from session 4 affecting session 27.

The pharma program runs for *months*. The benchmark runs for *seconds*. The cumulative failure modes a real program hits don't fit in a single-shot eval.

---

## What product-level evaluation looks like instead

This is what we've been building at BioMate. Not a single number — a matrix of evaluations, each measuring one dimension of production stability that maps to a real failure mode pharma actually hits.

> 📊 **Figure 1 — BioMate's evaluation matrix mapped to ChatInvent's named problems.** Source: `figures/post_22_eval_matrix.drawio.xml`. Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

### Hallucination — measured with an independent LLM judge

We don't trust the agent to grade itself. A separate model runs hallucination detection on outputs with task-specific rules — e.g., *every gene mentioned must be in the input list or in a retrieved knowledge source.* Measured on `screen_gene` and `gwas_causal`: **0% fabrication rate** (distinct from overconfidence, which we score separately).

### Routing — measured in two stages

- **IR layer** on the raw workflow-search endpoint: MRR 0.847, P@1 0.742, NDCG@3 0.920, Hit@5 0.967.
- **End-to-end routing** with the LLM in the loop: 84% exact match on 120 cases (v5), with explicit per-domain breakdowns so we can see which families need work.

The IR layer measures *retrieval quality*. The routing benchmark measures *retrieval + LLM combined*. The gap between them tells us how often the LLM is being asked to break ties it shouldn't have to.

### Stability — measured cross-session

20 scenarios built against LongMemEval and LoCoMo: recall, correction, baseline, temporal, synthesis, adversarial. **20/20 pass, 100% weighted, +45% versus a GPT-4o no-injection baseline.** Designed to be comparable to public memory literature so the result isn't a vanity metric.

### Schema correctness — measured at the parameter level

115 cases including a 15-case `param_name_disambiguation` category that public benchmarks don't have. Measures whether the parameter the agent emits is *semantically* correct, not just *type-valid*. **PBPK 71.7% → 98.5% (+26.8pp) from a rule-based prereq gate.** That lift came from no model change and no prompt change — just letting deterministic rules do what they're good at.

### Closed-loop stability — measured by remediation convergence

Across ADMET, CYP-DDI, docking, NCA-PK, and cryo-EM auto-loops: **96.4% convergence within 3 user-approved remediation iterations.** The question is not "did the workflow give a right answer one-shot." It's "when QC failed, did the system propose, get approved, and converge to a passing run."

### Traceability + governance — measured by coverage and reconciliation

Not a single number — a capability test. Every model output gets a registry row. Every wet-lab or clinical outcome that comes back gets reconciled to the prediction. We measure *coverage* (what fraction of decisions have a registry row) and *reconciliation latency* (how long between prediction and outcome). This is the evaluation that has no public benchmark and that the industry needs to build collectively.

---

## How this maps to the ChatInvent problems

| ChatInvent problem      | BioMate evaluation                                       | Current result                                |
|-------------------------|----------------------------------------------------------|-----------------------------------------------|
| Context explosion       | Routing v5 + IR baseline                                 | 84% exact / P@1 0.742 / Hit@5 0.967           |
| Tool hallucination      | Independent LLM judge on screen_gene + gwas_causal       | 0% fabrication                                |
| Schema mismatch         | param_prefill + PBPK / ADMET prereq gate                 | PBPK 71.7%→98.5% • param_prefill on 115 cases |
| Workflow instability    | Auto-loop convergence (cross-domain)                     | 96.4% within 3 iterations                     |
| Memory corruption       | LongMemEval / LoCoMo-aligned 20-scenario battery         | 20/20, 100% weighted, +45% vs GPT-4o baseline |
| Tool orchestration      | Routing + chain detection benchmarks                     | Per-domain coverage tracked                   |
| Evaluation              | This matrix itself, published                            | —                                             |
| Traceability            | Prediction registry coverage                             | Capability test (not single-number)           |
| Governance              | Audit-log completeness on HITL-approved actions          | Capability test                               |
| Human-in-the-loop       | Auto-loop approval surface • disambiguation gate         | Behaviour test in E2E suite                   |
| Memory                  | Episode + correction injection (Session 8 P1+P2 live)    | 4/4 E2E passing                                |

Each row is one production failure mode AstraZeneca publicly named. Each row is one BioMate evaluation that has a number or a capability check behind it.

---

## What the AstraZeneca paper got right that nobody else has admitted

Most "AI for pharma" companies disclose successes. The Molecular AI team's ChatInvent paper disclosed *engineering failures* — context blow-up, schema drift, memory corruption — and the architecture they used to address them.

That is the more useful disclosure. It is also the disclosure that makes the gap with public benchmarks visible.

If the evaluation framework you use to demonstrate your AI doesn't include the five problems they named, you are not measuring whether your AI is production-ready. You are measuring something narrower.

---

## What we'd propose to the industry

A few things, in order of how strongly we hold them:

**1. Publish hallucination rates with independent LLM judges.** Every AI-for-biology vendor should publish hallucination rates measured by an independent model — not their own model grading itself — on at least one open task. We do this on `screen_gene` and `gwas_causal`. Others can pick their own. The industry needs comparable hallucination numbers, not vibes.

**2. Publish closed-loop convergence, not one-shot accuracy.** If your product runs workflows, the relevant metric is *what fraction of failed runs the system can remediate to passing within N user-approved iterations* — not whether the first run was right.

**3. Publish memory benchmarks aligned with LongMemEval / LoCoMo.** Memory benchmarks are easy to game with custom datasets. Aligning to public benchmarks (with deliberate adversarial scenarios) raises the bar.

**4. Publish schema correctness, not just intent classification.** A model can route correctly and fill parameters wrong. Measure both. PBPK going from 71.7% to 98.5% from a rule-based gate is the kind of result that doesn't appear if you only measure intent.

**5. Stop quoting benchmarks designed for the model architecture you're selling.** Biomni-R0-32B scores well on BiomniEval1 because BiomniEval1 was built by Biomni. SGI-Bench favors models with deep literature synthesis. Each public benchmark has structural biases; using them as universal scoreboards is misleading.

---

## The honest position

Public benchmarks are not useless. They are necessary but insufficient.

The right evaluation for production agentic AI in pharma is:

- A **matrix** of evals, not a single number
- Covering **hallucination, routing, schema, memory, stability, traceability**
- Including **independent judges**, not self-grading
- Aligned to **named production failure modes** (the ChatInvent five are a good starting list)
- Designed so **gains are real**, not metric-engineered

We've built our matrix and we're publishing the dimensions and the methods. The numbers will keep moving as we improve the system. If you're working on a similar product and would like to compare notes — or push back on our framing — please do.

---

> 🧪 **Bring your own workflow and your own eval.** BioMate is in open trial. We will run it against any benchmark you care about and tell you honestly where it scores: [**biomate.ai**](https://biomate.ai)

---

*With thanks to the AstraZeneca Molecular AI team — Jiazhen He, Helen Lai, Lakshidaa Saigiridharan, Gian Marco Ghiandoni, K. Jenei, Umur Gokalp, Ajsa Nukovic, Ola Engkvist, Jon Paul Janet, and Samuel Genheden — for publishing the production-failure disclosure the industry needed.*

— Yaoyun Wang
Founder & CEO, BioMate AI
Houston, Texas
