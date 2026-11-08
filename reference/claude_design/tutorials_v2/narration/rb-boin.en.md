# BOIN dose-escalation — capability advantage demo (EN)

One narration block per scene, in order, for edge-tts. RealBio task: boin (clinical dose escalation — selecting the maximum tolerated dose with the Bayesian Optimal Interval design). Head-to-head score demo. Numbers are the real ledger figures only (BioMate 0.80, LLM-direct 0.24, n=60 cross-harness); the cross-harness caveat is kept. Decision-support for trial design, not medical advice.

---

## Step 1 — The task · phase-I dose escalation

In an early-phase cancer trial, patients are dosed just a few at a time, and each cohort's toxicities decide what happens next. Do you escalate to a higher dose, stay where you are, or step back down? And when enrolment ends, which dose do you declare the maximum tolerated dose — the highest dose that is acceptably safe? This is not a judgement call or a guess. It is a pre-specified, sequential statistical decision rule, applied cohort by cohort. Getting it wrong is not a rounding error — it has a direct cost in patient safety, which is exactly why the rule has to be followed, not improvised.

---

## Step 2 — BioMate doing it · the published BOIN design

BioMate answers this by running the Bayesian Optimal Interval design — BOIN — a published, validated method for exactly this problem. The key idea is that BOIN sets its decision boundaries in advance: from the target toxicity rate, it derives the threshold below which you escalate and the threshold above which you de-escalate, before a single patient is dosed. BioMate then applies those boundaries to the observed data the same way every time — comparing each cohort's toxicity rate to the fixed thresholds to choose the next dose, and at the end selecting the maximum tolerated dose as a concrete dose level in milligrams. It is a codified rule, executed — not a model talking its way toward an answer.

---

## Step 3 — The result · score versus LLMs

Here is the comparison, on a single metric: the fraction of trials where the correct maximum tolerated dose, in milligrams, is selected. BioMate, running the BOIN design, scores zero point eight-zero. A large language model asked to reason out the same clinical decision directly scores zero point two-four. These are the real figures from our clinical dose-escalation benchmark — sixty trials — and this is a cross-harness comparison: BioMate's own BOIN benchmark set against the language-model sweep, not the identical items side by side. We state it that way on purpose. Even so, the gap is wide: a validated design lands the right dose far more often than a model reasoning from scratch.

---

## Step 4 — The takeaway

The lesson is simple and honest. For a sequential safety decision like dose escalation, running a validated clinical design beats having a language model reason it out — zero point eight-zero against zero point two-four on correct maximum-tolerated-dose selection, over sixty trials, cross-harness. And there is a second reason beyond the score: a codified statistical rule is auditable. You can inspect the boundaries, reproduce the decision, and defend it — where a model's chain of reasoning cannot be. BioMate is a trial-design decision-support tool, not medical advice. The point is to put a method you can stand behind in the path of a decision that matters.
