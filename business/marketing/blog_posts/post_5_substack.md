# Drug development needs three things, not one: prediction, simulation, and real-world validation

*Most "AI for drug discovery" pitches sell you prediction. Some sell simulation. Almost none connect either back to what actually happened in the lab or the clinic. That gap is the real reason R&D productivity keeps falling.*

---

## The story everyone forgot

In 2017, Merrimack Pharmaceuticals had 426 employees, an FDA-approved cancer drug, and a pipeline built on quantitative systems biology.

By 2019, the company was gone.

Three Phase 2/3 trials failed in a row — MM-302, MM-121, MM-310. Each failure looked like bad luck. Together, they told a different story: **the same modeling playbook had blind spots, and nobody was tracking them across programs.**

The science wasn't wrong. The drug they got approved (Onivyde) is still on the market. What was missing wasn't smarter models. It was the **loop** that connects what the models predicted to what biology actually did — at a level of detail that lets you fix the model before the next program inherits the same blind spot.

Twelve years later, that loop still doesn't exist in most pharma R&D. And AI-first biotechs are making predictions at 100× the rate Merrimack ever did, with no audit trail.

---

## The three pieces, and why you need all of them

Think of a drug program as a series of decisions. Each decision needs three things, not one:

### 1. Prediction — what the model says will happen

> "This compound's hERG IC50 is 8.3 µM."
> "This patient subgroup will respond at 30%."
> "Steady-state Cmax at 100 mg QD will be 1.2 µM."

A prediction is a **point estimate**. Useful, but dangerous on its own — because it hides how confident you should be.

### 2. Simulation — what happens if the prediction is wrong

> "What if the hERG IC50 is actually 1 µM, not 8?"
> "What if response in humans is half of what the animal model showed?"
> "What if PK variability across patients is 3× higher than expected?"

Simulation **stress-tests the decision**. It tells you whether you're standing on solid ground or on a knife-edge that one bad parameter will tip.

### 3. Real-world validation — what actually happened

> "Measured hERG IC50: 1.4 µM. Off by 6×."
> "Observed response: 12%. Predicted 30%."
> "Observed Cmax: 2.6 µM. Predicted 1.2 µM. Geomean ratio 2.17."

Validation is **the reality column** next to every prediction. It's the only thing that tells you whether your model and your simulation are working — or whether they've been confidently wrong for the last six programs.

---

### Figure 1 — The triangle

> 📊 **Source:** `figures/post_5_triangle.drawio.xml` (open in [diagrams.net](https://app.diagrams.net) → export PNG at 1200×700)

ASCII fallback:

```
  ┌──────────────┐    ┌──────────────┐    ┌─────────────────────┐
  │  PREDICTION  │──▶ │  SIMULATION  │──▶ │ REAL-WORLD          │
  │  model says  │    │ what if 2×?  │    │ VALIDATION          │
  │              │    │              │    │ what actually        │
  │              │    │              │    │ happened            │
  └──────────────┘    └──────────────┘    └──────────┬──────────┘
         ▲                                            │
         │                                            ▼
         │              ┌──────────────────────────────────────┐
         └──────────────│  Closed loop:                        │
                        │  • Models improve                    │
                        │  • Decisions get audit trail         │
                        │  • Programs compound learning        │
                        └──────────────────────────────────────┘
```

**Prediction without validation is guesswork.**
**Simulation without validation is theater.**
**Validation without prediction-tracking is anecdote.**

Only the three together create a system that gets *better* over time instead of just *faster at being wrong*.

---

## What this looks like in practice — four concrete benefits

### Benefit 1 — Fewer failed trials, less wasted capital

A Phase 2 trial costs $20–100M. A Phase 3 trial costs $200M–1B.

When the simulation shows your decision is a knife-edge — for example, the patient stratification only works if the response biomarker has <15% measurement noise, and validation history says noise is closer to 30% — you don't run the trial. You go back and fix the biomarker.

That's not a hypothetical. It's exactly the kind of signal that was sitting in Merrimack's data and nobody connected.

### Benefit 2 — Faster, more confident decisions

In modern drug discovery you make hundreds of decisions per year: which hit to advance, which assay to trust, which dose to escalate to.

When every decision carries **prediction + simulation + validation history**, the easy calls become obvious (high-confidence prediction, robust to perturbation, validated pattern in past programs) and the hard calls get flagged for human review.

You move faster on the easy ones. You stop wasting senior time on calls the system can already make. You stop *missing* the hard calls that today drown in the noise of "everything looks fine."

### Benefit 3 — Compounding learning across programs

Today, every program learns from itself. The lessons die when the team disbands.

With a registry of predictions + outcomes across programs, **systematic model errors become visible**:

- "Our ADMET model underpredicts hERG by 5–10× for compounds with this scaffold."
- "Our PBPK gut model overpredicts oral bioavailability for BCS Class IV compounds."
- "Our patient stratification feature doesn't generalize across East Asian ancestry."

Fix it once, every future program benefits. That's how R&D productivity actually compounds.

### Benefit 4 — Regulatory and audit defensibility

Every model-driven decision in a regulated program will eventually be questioned: by the FDA, by an internal QA audit, by a partner doing due diligence.

When the answer is *"the AI recommended it"*, you have a problem.
When the answer is *"prediction X by model v2.1 [citations]; simulation showed robustness to 2× error in parameter Y; validation record N=43 programs, mean deviation Z%"* — you have an answer a regulator can evaluate.

---

### Figure 2 — Where the benefits stack

> 📊 **Source:** `figures/post_5_benefits_stack.drawio.xml` (open in [diagrams.net](https://app.diagrams.net) → export PNG at 1200×800)

---

## Why nobody has built this

The components aren't novel. A database. An ID per prediction. A column for the matching outcome. Some analytics on top.

It's plumbing, not AGI.

The reason it doesn't exist is that **predictions and outcomes live in different software, owned by different teams, with different schemas**:

| Where it lives          | What it holds                  |
|-------------------------|--------------------------------|
| Chemistry IT            | ADMET predictions              |
| Clinical pharmacology   | PBPK simulations               |
| Comp chem               | Docking scores, FEP            |
| Clinical operations     | Trial outcomes                 |
| Lab ELN / CRO portal    | Wet-lab measurements           |

No single team owns the loop. No vendor sells it end-to-end. Every program reinvents a slice and throws it away.

---

## Why the orchestration layer is the natural home

There's one place in the modern drug-development stack that *does* see all of these, by construction: **the agent running the workflows in the first place.**

- The agent picks the ADMET workflow → the prediction is captured automatically.
- The agent runs the PBPK simulation → the simulation outputs land in the same registry.
- The wet-lab result comes back through the same workspace → validation joins the same record.

This is what we mean when we say BioMate is an orchestration + intelligence layer, not a model vendor. The models will keep getting better — from us, from competitors, from open source.

**What's structurally missing is the connective tissue** that turns prediction into simulation, simulation into decision, decision into outcome, and the whole loop into compounded learning across programs.

> 🧪 **Try the loop yourself.** BioMate is now in open trial — bring an ADMET hit series, an RNA-seq batch, or a PBPK study and see what the closed loop looks like end-to-end: [**biomate.ai**](https://biomate.ai)

---

## What we're building, concretely

Three components inside BioMate:

**1. Prediction registry.** Every model output the agent produces is logged: model version, inputs, output, confidence, the decision it informed, the citations that supported it.

**2. Simulation hooks.** Before a decision lands, the agent sweeps the prediction over its uncertainty — what if the IC50 is 5× lower, what if response is half, what if variability is 2× higher. Robust decisions pass through. Fragile ones get flagged.

**3. Outcome reconciliation.** When the wet-lab measurement, the CRO study report, or the clinical readout lands, it's linked back to the original prediction. Deviation is computed and stored.

Over time the registry becomes a queryable record of where your models are reliable and where they aren't.

---

## The Merrimack question

Could a registry like this have saved Merrimack?

Honestly — probably not entirely. Pancreatic cancer is brutal. Single-target oncology is brutal. There were real biological limits no amount of better infrastructure would have overcome.

But Merrimack ran four programs on a network-biology playbook that had systematic blind spots. The signals were in the data. Nobody aggregated them across programs in a form anyone could act on.

The lesson isn't *computational drug development doesn't work*. Merrimack got a drug to market with it.

**The lesson is that the infrastructure to learn from your own predictions is as important as the predictions themselves.**

That's the gap we're building toward. If you're working on a program that's about to make a high-stakes call on a model output, [come run it through BioMate](https://biomate.ai) — and let us know what we got wrong.

---

*In two weeks: Evidence-grounded AI in biology — what we ground against, and what general-purpose LLMs get wrong in drug development and the clinic.*

— Yaoyun Wang
Founder & CEO, BioMate AI
Houston, Texas
