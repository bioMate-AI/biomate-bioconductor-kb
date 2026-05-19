# LinkedIn feed post — Post 9

**Recommended hero image:** `figures/post_9_options_matrix.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,600 / 3,000 limit.

---

About once a month, someone asks me if BioMate is training its own LLM.

My honest answer has two halves: mostly no — but for one workload, yes. And the reasons are instructive.

Four options when you build an AI for biology:

1️⃣ Prompt + RAG on a frontier model — weeks to deploy, $50–150K/mo at scale
2️⃣ Fine-tune an open base — 1–3 months, $50–200K
3️⃣ Continue pre-training on biomedical corpus — 3–9 months, $500K–1.5M
4️⃣ Train from scratch — 9–18+ months, $10M+

Most "AI for biology" companies should pick option 1 with selective option 2. Here's why:

🔹 The frontier doubles in capability every 12 months. Any custom foundation model you train today is matched by a frontier release within 6–9 months.

🔹 Most of your hard problems aren't language problems. They're orchestration, tool integration, knowledge curation, evaluation. A 10% lift on language is a 2% lift on the overall product.

🔹 Frontier + grounded RAG beats domain-trained + no-scaffolding in our internal evals across drug discovery, omics, cryo-EM, and ADMET workflows. The Nature Communications benchmark says the same thing.

So for BioMate's orchestration agent — workflow routing, parameter selection, QC interpretation, cross-domain reasoning — we use frontier + RAG. No custom foundation model.

The ONE exception: our regulatory LLM for IND submissions (§2.6.1 Pharmacology Written Summary).

We trained it. Continued pre-training on Llama base + DPO on checker-grounded pairs.

Why this one was worth it:

✅ FDA-acceptable prose is a specialized register. Frontier models write good papers, not good IND sections.
✅ The training corpus is bounded and high-signal: FDA guidance, ICH, public IND/NDA reviews.
✅ Pharma sponsors won't send draft regulatory text to third-party APIs. On-prem is required.
✅ Volume × per-token cost makes the unit economics flip vs. frontier APIs.

The lesson: build the scaffolding first, train models second, and train only where the domain has a constrained corpus, specialized output, and customer-driven deployment constraints that APIs can't satisfy.

For everything else: frontier + grounded RAG + good evaluation wins.

Open trial — try the scaffolding without any custom foundation model in the loop:

👉 biomate.ai/try

Full essay (with the options matrix): [Substack link]

#AIinPharma #DrugDiscovery #LLM #FineTuning #Regulatory #FDA
