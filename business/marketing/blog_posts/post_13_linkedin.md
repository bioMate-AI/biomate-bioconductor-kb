# LinkedIn feed post — Post 13

**Hero image:** `figures/post_13_tool_grounding.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,700 / 3,000.

**Posting note:** retype the `@` in front of each name in LinkedIn's composer to resolve real profiles.

---

Tool hallucination is the most dangerous AI failure mode in regulated R&D.

@Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca team named it in their Drug Discovery Today paper "Democratising real-world drug discovery through agentic AI" (doi: 10.1016/j.drudis.2026.104605, describing their ChatInvent system) as one of the five engineering problems agentic AI hits in pharma R&D.

In a chat app, a hallucinated tool is a glitch. In a drug program, it's a record going into a regulatory submission that points at a tool that never ran on data that was never produced.

This has to go to zero. Not "low," not "rare." ZERO.

Most "AI for biology" demos skip three things, and each silently re-introduces hallucination:

❌ They retrieve free-text tool descriptions, then let the LLM rewrite them
❌ They run one LLM call to pick a tool, with no independent judge
❌ They have no "I don't know" — every query gets a confident answer

What we built at BioMate, four discipline layers:

🔹 REGISTRY IS THE SOURCE OF TRUTH
2,455 indexed workflows. The agent doesn't generate workflow names — it picks from retrieved registry candidates. No registry hit = no execution.

🔹 DISAMBIGUATION GATE, NOT COIN FLIP
Fires only when ≥2 candidates score ≥6.0 AND gap < 3.0. The user sees a candidate card, not the agent's guess.

🔹 CITATION DISCIPLINE
Every factual claim followed by a source token. Unsupported claims marked "model knowledge — not verified."

🔹 INDEPENDENT HALLUCINATION JUDGE
Separate LLM-judge pass with task-specific rules grades the output. Hallucinated claims get reformulated or removed.

📊 Benchmark evidence:
✓ HallucinationDetector on screen_gene + gwas_causal: 0% hallucination (actual fabrication, distinct from overconfidence)
✓ Routing v5: 84% exact match on 120 cases
✓ IR Hit@5 = 0.967 — correct workflow in top 5 candidates 97% of the time
✓ BiomniEval1 patient_gene: 84% (BioMate v9), competitive with Biomni-R0-32B on its own benchmark
✓ Variant calling: 0.567 → 0.824 (+0.206) via 4 structural retrieval fixes

The hardest cultural shift: in production pharma agents, you reward "being right when you speak and silent when you don't."

Demo agents are rewarded for sounding confident.
GxP-deployable agents are rewarded for refusing cleanly.

That's a different design target.

Open trial — ask BioMate for a workflow that's clearly outside catalog. Watch it refuse cleanly instead of inventing one:

👉 biomate.ai/try

Full essay (with grounding diagram + benchmark detail): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — would value your reaction to the registry-bounded approach.

#AIinPharma #DrugDiscovery #LLM #Hallucination #Regulatory #AstraZeneca
