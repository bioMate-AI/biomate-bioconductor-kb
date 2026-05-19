# Evidence-grounded AI in biology: what we ground against, and what general-purpose LLMs get wrong

*General-purpose LLMs hallucinate biology and drug development facts at rates that are genuinely alarming. Here's the data, and the architecture we use to push that rate toward zero across drug discovery, omics, structural biology, and regulatory writing.*

---

In May 2026, a group of researchers published [an audit of 111 million citations across 2.5 million papers](https://arxiv.org/abs/2605.07723v1) on arXiv, bioRxiv, SSRN, and PubMed Central. They were looking for non-existent references — citations to papers that don't actually exist, fabricated wholesale by LLMs and slipped through peer review by authors who didn't check.

Their conservative estimate: **146,932 hallucinated citations in 2025 alone**, disproportionately concentrated in fields with rapid AI uptake and in manuscripts whose linguistic signatures suggest heavy AI-assisted writing.

That's the published literature — the part that survived peer review. The unfiltered output of LLMs is dramatically worse. [GhostCite, a 2026 benchmark study of 13 state-of-the-art LLMs across 40 research domains](https://arxiv.org/pdf/2602.06718), found citation hallucination rates ranging from **14.23% to 94.93%** depending on model and domain. In adversarial healthcare settings, [LLMs without grounding hallucinate at rates above 60%](https://sqmagazine.co.uk/llm-hallucination-statistics/). For citation identification specifically, the highest recorded hallucination rate is **94%**.

If you're building anything that touches biology — discovery, development, manufacturing, or regulatory — and you're using a vanilla LLM, you have a problem. The interesting question is what to do about it.

## Why hallucination matters more in biology than anywhere else

A hallucinated movie quote is embarrassing. A hallucinated legal citation is malpractice. A hallucinated biological fact can be all of the above plus dangerous.

A few examples of what hallucination looks like in actual scientific workflows, drawn from queries an agent in this domain has to handle every day:

- *"What's the FDA-recommended starting dose for a first-in-human study of a 35 kDa monoclonal antibody with NOAEL 50 mg/kg in cynomolgus monkey?"* A vanilla LLM will produce a confident-sounding number. There's a good chance the number ignores the MABEL principle for biologics, that the citation it provides is fabricated, and that the safety factor it implies doesn't match current FDA guidance.

- *"Which nf-core pipeline should I use for ATAC-seq with paired-end reads and a custom genome?"* The LLM may recommend something plausible. It may or may not be the actual current pipeline name, may suggest deprecated parameters, and almost certainly won't know which version is currently passing nf-core CI.

- *"What does it mean if hERG IC50 is 6.2 µM for a candidate with predicted free Cmax of 0.4 µM?"* The LLM will reproduce a pattern from training data. It will not flag that the relevant safety margin convention (30× by ICH S7B, sometimes 100× in cardiovascular indications) depends on the program context, and it will likely conflate total and free plasma concentrations.

- *"What's the typical resolution achievable for a 200 kDa membrane protein in cryo-EM single-particle analysis with 1.6 Å pixel size?"* The model will produce a number with no attached citation. The number may be from a 2018 paper that predates current detector and processing advances; the user has no way to know.

In all these cases, the user has no way to tell whether they're getting a real answer or a confabulation. The fluency masks the failure mode. A scientist who gets a wrong but confident-sounding number is *worse off* than one who gets no answer, because they may now make a decision based on it — and in drug development, decisions cost months and millions.

This is why evidence grounding — the discipline of forcing every assertion an AI system makes to be traceable to a verifiable source — isn't optional in this domain. It's the difference between a tool that helps and a tool that quietly poisons your science.

## What "evidence-grounded" actually means in practice

The conventional answer to LLM hallucination is RAG — retrieval-augmented generation. Build a vector database, embed your documents, retrieve relevant chunks at query time, stuff them into the prompt, ask the model to generate an answer grounded in the retrieved context. There are now dozens of tutorials, frameworks, and SaaS products built on this pattern.

The honest truth is that **most production RAG systems are still hallucinating, just at a lower rate**. A model with retrieved context can still:

- Cite a paper that exists but doesn't say what the model claims it says
- Confidently combine two retrieved facts into a third, fabricated fact
- Ignore the retrieved context when it conflicts with the model's prior
- Apply a retrieved fact outside the context in which it's valid (e.g., a binding affinity from one assay format to a different one)

The [arXiv ArxEval benchmark](https://arxiv.org/pdf/2501.10483) on scientific RAG specifically documents this — even with retrieval, factual accuracy in scientific queries varies substantially across models. Retrieval-grounded tasks can drop hallucination rates to <2% in narrow benchmarks (per OpenAI's evals) and as high as 56.8% in [open-ended scientific writing tasks](https://arxiv.org/pdf/2603.03299), depending on prompt framing and model choice.

So "we have RAG" is a starting point, not a solution. The harder engineering work is in four layers underneath:

**1. Curated knowledge sources, not the open web — and the source set depends on what you're answering.** Different parts of a drug program require different ground truth. Our knowledge layer is built from sources selected by domain, not a single monolithic vector store:

- **PubMed / PubMed Central** — peer-reviewed primary literature, ~38 million citations, full-text PMC access for ~10 million open-access articles. The "what does the literature say" layer for every domain. Indexed with biomedical-tuned embeddings (BGE-large with domain adaptation; specialized variants for clinical text).
- **UniProt + AlphaFold DB + InterPro** — protein sequences, functional annotations, structures. The "what does this protein do, where is it expressed, what does it bind, what's its predicted structure" layer.
- **ChEMBL + DrugBank + PubChem** — bioactivity, drug properties, chemical entities. The "what's known about this compound or compound class" layer.
- **Ensembl + gnomAD + ClinVar + OMIM** — human genomics, allele frequencies, clinical variant interpretation. The "is this variant pathogenic, common, druggable" layer.
- **FDA guidance corpus + ICH guidelines + OpenFDA + DailyMed** — regulatory ground truth. The "what does the regulator actually require here" layer, indispensable for any output that touches an IND, NDA, or BLA.
- **nf-core docs + Galaxy training corpus + tool-specific manuals (CryoSPARC, AutoDock, GROMACS, etc.)** — workflow knowledge. The "which pipeline, which parameter, which version" layer.
- **Domain-specific spectral and structural libraries** where applicable — GNPS/MassBank for metabolomics, EMPIAR for cryo-EM, PDB for structural biology, GEO/SRA for transcriptomics datasets.

These are *curated, versioned, citeable* sources only. Open-web retrieval is off by default. New PubMed entries indexed daily; FDA guidance updates indexed on publication; tool docs versioned to the workflow versions actually deployed.

**2. Retrieval that respects scientific structure.** Naive RAG embeds chunks of text. Scientific RAG needs to embed *with metadata*: instrument type, assay format, organism, units, measurement method, publication date, citation count, regulatory authority. A binding affinity from a 2010 paper using a SPR assay with a saturating ligand concentration is not directly comparable to one from a 2024 paper using fluorescence polarization at sub-saturating conditions. A starting-dose recommendation from a 2015 FDA guidance is not the same as one from the 2024 update. The retrieval layer has to surface that distinction, not flatten it. We use hybrid retrieval — dense embeddings for semantic match, structured filters for assay/method/version constraints, and BM25 for exact-term matching on identifiers (gene symbols, CHEMBL IDs, PDB IDs, FDA guidance numbers).

**3. Grounded generation with mandatory citation.** The model's prompt forces every factual claim to be followed by a citation token referencing the retrieved source. Claims without supporting retrieved context get flagged in the output as "model knowledge — not verified against current database." This is the difference between an output that says *"Recommended Phase 1 starting dose by MABEL is 0.1 mg/kg [FDA 2024 §III.B.2; Lowe et al. 2010, Br J Clin Pharmacol]"* and one that just says *"Recommended Phase 1 starting dose is 0.1 mg/kg."* The user can click through to the source and verify. If they can't, they know not to trust the number. For regulatory outputs that go into actual submissions, this isn't a UX nicety — it's the audit trail the sponsor will need when the agency asks why this dose was chosen.

**4. Outlier detection and self-consistency checks.** When retrieval returns multiple sources with conflicting numbers, the system flags the conflict rather than silently picking one. A [recent approach using peer-context outlier detection](https://arxiv.org/pdf/2604.01461) achieved up to 98% precision in catching scientific hallucinations by comparing extracted claims against validated peer information across the retrieved corpus. This is the layer that catches subtle failures the user wouldn't notice — like a reported binding affinity that doesn't match what three other papers report for the same compound under the same conditions, or a dose-response curve fit that one source publishes with a slope that's an outlier across the literature.

> 📊 **Figure 1 — The four-layer evidence-grounded stack.** Source: `figures/post_8_rag_stack.drawio.xml`
> Open in [diagrams.net](https://app.diagrams.net), export PNG at 1200×800.

## The architecture in one paragraph

User query → intent classification → query expansion with synonym resolution against curated ontologies (ChEBI for compounds, MeSH for biomedical concepts, MedDRA for adverse events, MONDO for diseases) → domain routing to the appropriate knowledge sources → hybrid retrieval across curated KBs with metadata filters → reranking by domain-tuned cross-encoder → grounded generation with mandatory inline citations → outlier and self-consistency checks → response with citation-linked claims and an explicit "not in knowledge base" marker on any unsupported assertion.

None of these components are individually novel. The discipline is in forcing every step to fail loudly rather than quietly, and in restricting knowledge sources to curated, citable, version-controlled databases rather than the open web.

## What this means for users

The practical difference shows up in three places:

**Trust calibration.** When the system tells a DMPK scientist that the recommended human equivalent dose is 4.8 mg/kg given a rat NOAEL of 30 mg/kg, the citation links to the relevant FDA guidance, the specific allometric scaling factor table, and the underlying study record. They can verify. When the system can't find a citation, it says so — "I don't have a validated reference for the species-specific correction in this case; recommend manual review with the clinical pharmacology lead."

**Audit trail.** Every model-recommended decision — parameter choice for a workflow, compound prioritization, QC interpretation, dose recommendation, IND narrative claim — is logged with the citations that supported it. When a regulator asks why a particular parameter or claim was chosen, the answer isn't "the AI said so" — it's "based on these three peer-reviewed papers, this FDA guidance section, and this internal study record, here are the references." This matters enormously for any work that touches regulatory submissions, and it's the difference between an AI tool that's usable in a GxP environment and one that isn't.

**Compounding accuracy.** Every interaction either confirms or corrects a knowledge base entry. A user who corrects a recommendation contributes to a feedback loop that improves retrieval and ranking for future users. Curated sources update over time as the literature and the regulatory corpus grow. Unlike a frozen model, a grounded system gets *more accurate* with use, not less.

## The honest limitations

A few things grounded RAG doesn't fix:

**Knowledge base completeness.** If the answer to your question isn't in our curated sources, you don't get an answer — or you get a marked-as-uncertain answer drawn from the base model's parametric knowledge. For novel compounds, recent preprints, proprietary data, or genuinely cutting-edge methods, the knowledge base will lag. We mitigate this with continuous indexing pipelines and explicit "knowledge cutoff: [date]" markers on responses, but lag is inherent to any curated system.

**Domain transfer.** A system grounded for ADMET reasoning doesn't generalize to cryo-EM particle picking without a separate knowledge layer, and a system grounded for FDA submissions doesn't translate one-for-one to EMA submissions. We see this as a feature, not a bug — domain specialization is what makes the answers reliable — but it means scaling to new domains requires the same investment in curated sources, not just swapping the prompt.

**Reasoning failures.** Grounding fixes "what is true." It doesn't fix "what follows from what's true." The most sophisticated hallucinations are the ones where every individual fact is correctly retrieved but the conclusion drawn from them is wrong. This is where multi-step verification, chain-of-thought tracing, and human-in-the-loop review still matter. Grounded RAG raises the floor of factual accuracy; it doesn't eliminate the ceiling of reasoning error. For high-stakes outputs — anything that lands in a regulatory submission, a clinical protocol, or a patient-facing report — human review is non-negotiable, and we design the UX to make that review easy rather than to make it skippable.

**Cost.** A grounded system with high-quality retrieval, reranking, and multi-source verification costs several times more per query than a raw LLM call. The math works at the throughput levels life science workflows generate, but it's a real constraint at scale. We make architectural choices — caching, query batching, tiered model routing, fine-tuned small models for the highest-volume sub-tasks — to keep unit economics reasonable.

## The summary, for skeptics

If you're a computational biologist, DMPK scientist, regulatory writer, or pharma R&D leader evaluating whether to bring an LLM into your workflow, the question isn't "does it work?" — it's "does it fail loudly enough that I'll notice?"

Vanilla LLMs fail silently. They produce fluent, confident, often-wrong answers indistinguishable from correct ones. The hallucination data isn't a marginal concern; it's a domain-defining one for science. The [Nature Communications benchmark](https://www.nature.com/articles/s41467-025-56989-2) of LLMs on biomedical NLP tasks found that traditional fine-tuned models still outperform zero-shot LLMs on most tasks, with hallucination patterns that vary significantly across applications.

Evidence-grounded systems with curated sources, mandatory citations, and outlier detection don't eliminate hallucination — but they make it observable, traceable, and progressively reducible. That's the difference between a tool you can deploy in a regulated environment and one you can't.

This is what we mean when we say BioMate's moat is the intelligence layer, not the underlying model. Anyone can call GPT-5 or Claude or Llama. What's hard is the curation, the metadata-aware retrieval, the citation discipline, and the outlier detection that turns a generic model into something a DMPK lead, a CMC director, or a clinical pharmacology consultant can actually rely on.

> 🧪 **Try it.** BioMate is in open trial — bring a question that needs to be grounded in FDA guidance, PubMed, or UniProt and see the citation-linked output: [**biomate.ai/try**](https://biomate.ai/try)

---

In two weeks: *Domain-specific LLMs for biology — post-train, fine-tune, or train from scratch? What we chose, and the one place we did train our own model.*

— Yaoyun Wang
Founder & CEO, BioMate AI
