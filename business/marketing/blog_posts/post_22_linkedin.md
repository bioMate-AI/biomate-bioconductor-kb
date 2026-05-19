# LinkedIn feed post — Post 22 (opinion: evaluation metrics)

**Hero image:** `figures/post_22_eval_matrix.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,800 / 3,000.

**Posting note:** retype the `@` in front of each name in LinkedIn's composer so it resolves to a real profile.

---

The benchmarks every "AI for biology" company quotes are measuring the wrong thing.

BixBench, BiomniEval1, SGI-Bench, MMLU-Med — they measure ONE slice well: given a fixed question with a known correct answer, how often does the model get it.

That is useful. It is also nowhere near sufficient for production pharma.

What they don't measure:

❌ Whether the agent INVENTS a tool that doesn't exist
❌ Whether the agent emits parameters that are type-valid but semantically wrong ("n_steps: 100" when the user said 100 nanoseconds)
❌ Whether the agent stabilizes a long-running multi-month session
❌ Whether the agent CLOSES the loop when QC fails — or just reports "done" with bad output
❌ Whether the agent leaves a regulatable audit trail
❌ Whether the agent knows when it doesn't know, and refuses cleanly

These are not edge cases.

Two weeks ago @Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca Molecular AI team published "Democratising real-world drug discovery through agentic AI" in Drug Discovery Today (doi: 10.1016/j.drudis.2026.104605) — describing their ChatInvent system.

They publicly named the engineering problems agentic AI hits in production:

Context explosion. Tool hallucination. Schema mismatch. Memory corruption. Workflow instability.

Plus six capability pillars the Agent era requires: tool orchestration, evaluation, traceability, governance, human-in-the-loop, memory.

NONE of these show up on the public benchmarks the industry quotes.

That is the gap between demo-grade and production-grade pharma AI. It is not closing by itself.

At BioMate we built our own evaluation matrix — one eval per production failure mode:

🔹 HALLUCINATION — independent LLM judge, task-specific rules → 0% fabrication on screen_gene + gwas_causal
🔹 ROUTING — IR layer (P@1 0.742, Hit@5 0.967) + end-to-end (84% exact, 120 cases)
🔹 SCHEMA — param_prefill with 115 cases including param_name_disambiguation; PBPK 71.7%→98.5% from a rule-based prereq gate
🔹 STABILITY — LongMemEval + LoCoMo-aligned 20 scenarios, 100% weighted, +45% vs GPT-4o no-injection baseline
🔹 CLOSED-LOOP — 96.4% auto-loop convergence within 3 user-approved iterations
🔹 TRACEABILITY — prediction registry coverage + outcome reconciliation latency

What we'd propose to the industry:

1. Publish hallucination rates with INDEPENDENT judges, not self-grading
2. Publish closed-loop convergence, not one-shot accuracy
3. Publish memory benchmarks aligned with LongMemEval / LoCoMo
4. Publish schema correctness, not just intent classification
5. Stop quoting benchmarks designed for the model architecture you're selling

Public benchmarks are necessary but insufficient. The right evaluation for production agentic AI in pharma is a matrix — not a single number — aligned to named production failure modes.

The ChatInvent five are a good starting list.

Open trial — bring your own workflow and your own benchmark, we'll run it against ours honestly:

👉 biomate.ai/try

Full essay (with the eval matrix diagram): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — this is the post most directly in dialogue with your paper. Would value any pushback on the matrix.

#AIinPharma #DrugDiscovery #BenchmarkEvaluation #Bioinformatics #AstraZeneca
