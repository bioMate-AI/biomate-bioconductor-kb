# Protocol QC — PASS or FAIL, decided by codified gates — narration (EN)

One narration block per scene, in order, for edge-tts. RealBio capability demo: protocol-QC. Head-to-head score demo, not a tutorial. Numbers are the real RealBio ledger figures (BioMate 0.925 PASS/FAIL accuracy; LLM-direct 0.33–0.63). Source: docs/20261005_REALBIO_CAPABILITY_DEMO_SERIES.md, protocol-QC ledger row.

---

## Step 1 — The task · does this run pass quality control?

Here is a deceptively simple question. You have an experimental protocol and the outputs it produced — now decide: does it pass quality control, or fail? That verdict is not a matter of style. It depends on real domain thresholds: an ADMET hERG safety limit, a minimum sequencing coverage depth, how far a model is allowed to extrapolate. Getting it right needs the correct threshold and real judgment, not a fluent paragraph. Ask a general language model to eyeball the run, and it will produce confident-sounding text — but it is, in the end, guessing at the pass-fail line. BioMate does not guess. It checks the run against a gate it has already codified.

---

## Step 2 — BioMate doing it · measured value against threshold

This is how BioMate makes the call. Every quality gate is evaluated as a plain comparison — the measured value on one side, the codified threshold on the other, shown as two numbers you can read at a glance. When a breach actually matters, the gate halts the run. A soft miss raises an advisory. A clean metric passes. In this example, a hERG inhibition of zero-point-six-eight against a ceiling of zero-point-five halts; a coverage depth of twenty-four-fold against a floor of thirty raises an advisory; an oral bioavailability of zero-point-four-one clears its threshold and passes. And on a halt, BioMate's auto-loop can go further — adjust the offending parameter and re-run — rather than simply reporting that something broke. The same rule applies every time, so the verdict is reproducible, not an opinion.

---

## Step 3 — The result · the score against language models

Now the head-to-head. On the RealBio protocol-QC task, BioMate calls PASS or FAIL correctly nine hundred and twenty-five times in a thousand — zero-point-nine-two-five. A language model answering the very same questions directly lands somewhere between zero-point-three-three and zero-point-six-three. At its worst that is barely better than a coin flip; even at its best, zero-point-six-three, it falls far short. The gap is not small — it is more than thirty points over the best model run, and nearly sixty over the worst. These are the real measured figures. Codified gates do not drift from one run to the next, and they do not guess.

---

## Step 4 — Takeaway · gates beat guessing

The lesson is one sentence. Quality control is not a writing task — it is a comparison against a known threshold. BioMate encodes each domain gate once and applies it the same way on every run, so the pass-fail verdict is reproducible, verifiable, and defensible — something you can put straight into a report. A model asked to judge the same run has no fixed threshold to hold itself to, and the score shows it: zero-point-nine-two-five against zero-point-three-three to zero-point-six-three. Codified, verifiable quality gates beat a model guessing PASS or FAIL.
