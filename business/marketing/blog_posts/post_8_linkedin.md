# LinkedIn feed post — Post 8

**Recommended hero image:** `figures/post_8_rag_stack.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,500 / 3,000 limit.

---

LLMs hallucinate science at rates between 14% and 95% depending on the model and domain.

In adversarial healthcare settings, the rate goes above 60%.

For citation identification specifically, the highest recorded number is 94%.

If you're bringing an LLM into a drug development workflow, the question isn't "does it work?" — it's "does it fail loudly enough that I'll notice?"

A hallucinated movie quote is embarrassing. A hallucinated legal citation is malpractice. A hallucinated FIH starting dose, hERG safety margin, or patient stratification criterion is dangerous — and goes into a regulatory submission.

The standard answer is RAG. Most production RAG systems still hallucinate, just at a lower rate. They cite papers that don't say what the model claims. They mix two facts into a third, fabricated one. They apply retrieved facts outside their valid context.

What actually works — what we built at BioMate — has four layers:

🔹 LAYER 1: Curated sources, not the open web
PubMed/PMC, UniProt + AlphaFold DB, ChEMBL + DrugBank, Ensembl + gnomAD + ClinVar, FDA guidance + ICH + OpenFDA, nf-core docs. Versioned, citeable, domain-routed.

🔹 LAYER 2: Retrieval that respects scientific structure
Embed with metadata (instrument, assay format, organism, units, FDA guidance version). Hybrid: dense + BM25 + structured filters.

🔹 LAYER 3: Mandatory inline citation
Every factual claim is followed by a citation token. Unsupported claims are flagged "model knowledge — not verified."

🔹 LAYER 4: Outlier + self-consistency checks
Conflicts between sources surface to the user. Peer-context outlier detection catches subtle failures.

The result for users:

✅ TRUST CALIBRATION — every number has a clickable source
✅ AUDIT TRAIL — every decision has a citation when the FDA asks
✅ COMPOUNDING ACCURACY — corrections feed back into retrieval

This is not hypothetical engineering. It's the difference between an AI tool you can deploy in a GxP environment and one you can't.

Open trial — bring a regulatory or DMPK question and see the citation-linked output:

👉 biomate.ai/try

Full essay (with the architecture diagram): [Substack link]

#AIinPharma #DrugDiscovery #Regulatory #Bioinformatics #LLM #RAG
