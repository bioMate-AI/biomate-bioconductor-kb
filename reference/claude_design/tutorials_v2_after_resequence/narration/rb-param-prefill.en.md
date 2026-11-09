# param_prefill — capability advantage demo — narration (EN)

One narration block per scene, in order, for edge-tts (Aria, +40%). RealBio task: param_prefill — turning a free-text scientific request into correct workflow parameters. Head-to-head score demo. Grounded in the honesty ledger in docs/20261005_REALBIO_CAPABILITY_DEMO_SERIES.md (BioMate 0.848 F1; LLM-direct 0.62–0.76). Real figures only.

---

## Step 1 — The task

Consider a single request a scientist might type: RNA-seq differential expression, human, GRCh38, dUTP strand-specific, treated versus control, FDR point zero five. Behind that sentence is a workflow with dozens of parameters, and every one has to be exactly right. "Human" has to become the GRCh38 genome. "dUTP" has to become reverse strandedness. "FDR point zero five" has to become an adjusted-p-value threshold. Get one field wrong and the run either fails, or quietly produces the wrong answer. And this is precisely where a language model, on its own, is least reliable — at arithmetic unit conversions, at deterministic boolean mapping, and at choosing values a schema will actually accept.

---

## Step 2 — BioMate doing it

BioMate does not hand the whole job to the model. It extracts parameters with deterministic rules first, and uses the language model only as a fallback. The rules do the exact work: unit conversions, like nanoseconds to step counts; negations, like "remove adapters" becoming a flag set to false; boolean flags, like "single-end" becoming true; and canonical aliases, like "human" becoming GRCh38, or "dUTP" becoming reverse. The model is reserved for the genuinely open-ended fields a rule can't enumerate — free-text values like SMILES strings, structure IDs, or gene names. And then a guardrail validates every extracted value against the workflow's allowed values, dropping or normalizing anything that violates a constraint before the run begins.

---

## Step 3 — The result

Here is the score. On the RealBio param_prefill task — measured as parameter-extraction F1 — BioMate's hybrid extractor reaches zero point eight four eight. A frontier language model, prompted directly for the same parameters, lands in the range of zero point six two to zero point seven six. That's an advantage of roughly nine to twenty-three F1 points, and it comes from exactly the fields the rules handle deterministically: the conversions, the booleans, and the schema-constrained enums where a model asked directly tends to slip.

---

## Step 4 — The takeaway

The lesson is simple. The rules make parameter extraction exact, testable, and zero-cost, so it doesn't drift from one run to the next; the language model is reserved only for the parts that are genuinely free text. That division of labor is why BioMate reaches zero point eight four eight where a model on its own stays between zero point six two and zero point seven six — turning a sentence of science into a run you can defend.
