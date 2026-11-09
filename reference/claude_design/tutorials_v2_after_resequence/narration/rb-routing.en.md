# Cross-domain routing — intent to the one correct workflow — narration (EN)

One narration block per scene, in order, for edge-tts. RealBio capability-advantage demo for the **cross-domain routing** task (intent → correct workflow selection). Numbers are the real RealBio leaderboard figures in docs/20261005_REALBIO_CAPABILITY_DEMO_SERIES.md (BioMate 0.965 [.930,.983]; LLM-direct 0.46 mean, 0.615 best). Head-to-head score demo, not a how-to.

---

## Step 1 — The task · intent to the one correct pipeline

A scientist describes what they want in their own words — call somatic variants on these tumour-normal pairs, or quantify this bulk RNA-seq and run differential expression. Before anything can run, that plain-English request has to become a specific choice: the one correct pipeline, out of thousands, spanning genomics, transcriptomics, proteomics, cryo-electron microscopy, drug discovery, and more. This is cross-domain routing. It is deceptively hard, because the request rarely names a tool, and the domains overlap. Pick the wrong pipeline and the entire run is wasted — the compute, the wait, and the trust. Routing is where orchestration either earns its keep or fails quietly.

---

## Step 2 — BioMate doing it · match by meaning over a real catalog

BioMate does not guess a pipeline name from memory. It holds a catalog of four thousand two hundred and ten indexed workflows across forty-two domains — real, validated pipelines, each described by what it actually does. When your request arrives, BioMate scores it against every one of those workflows by dense-cosine resonance: it compares what you mean to what each workflow performs, so paraphrase and synonyms are handled, with no brittle keyword list to maintain. The candidates are ranked, and the best match comes back with its domain and its steps attached. One selector spans every domain at once. This is retrieval over a real catalog — not a name recalled, and possibly invented, from training.

---

## Step 3 — The result · the score against bare models

Here is the head-to-head. The metric is intent-to-correct-workflow accuracy: given a plain-English request, did the system select the right pipeline? Higher is better. BioMate's catalog-grounded routing scores zero point nine six five — ninety-six and a half percent — with a ninety-five percent confidence interval from zero point nine three zero to zero point nine eight three. It picks the right pipeline almost every time. Ask a frontier language model to name the pipeline directly, and the strongest one reaches zero point six one five; across the model sweep the average is zero point four six — close to a coin flip on which pipeline to run. That is a gain of about thirty-five points over the best bare model, and roughly double the mean. A wrong pick is a wasted run — the gap is the difference between a defensible result and an expensive mistake.

---

## Step 4 — The takeaway · the catalog is the moat

The lesson is one sentence. Naming the one correct pipeline from a plain-English request is a retrieval problem over a real catalog — not a feat of recall. That is exactly where orchestration beats a bare model: BioMate's indexed workflows and dense-cosine resonance turn "which pipeline?" from a coin flip into a near-certainty — zero point nine six five against zero point four six — and every routing answer is reproducible and effectively free to serve. The catalog, and the resonance over it, is the moat.
