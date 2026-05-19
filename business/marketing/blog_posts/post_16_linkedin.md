# LinkedIn feed post — Post 16

**Hero image:** `figures/post_16_memory_governance.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,700 / 3,000.

---

**Posting note:** retype the `@` in front of each name in LinkedIn's composer to resolve real profiles.

---

A drug program runs for months. The agent that helps it should know:

- Which workflows the team has run, on which inputs
- Which parameter choices were standardized after a tox surprise
- Which corrections the user made (and the agent should NOT repeat)
- Why the team dropped compound CMP-014 six weeks ago

A chat-style agent has none of this. Every session starts blank. The audit question "why did the agent recommend dose X?" has no answer.

The opposite extreme — drag every prior turn into every new prompt — is worse. Stale assumptions poison new tasks.

This is memory corruption. Fifth and final in the five engineering problems named by @Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca team in "Democratising real-world drug discovery through agentic AI" (Drug Discovery Today, doi: 10.1016/j.drudis.2026.104605).

They also named six capability pillars the Agent era requires: tool orchestration, evaluation, traceability, governance, human-in-the-loop, memory.

The pillars are not a menu. They work as a system or they don't work.

What we built at BioMate, four layers:

🔹 EPISODE MEMORY — what happened
Workflow runs distilled into structured records: inputs, params, outputs, QC outcome, user corrections. The agent on day 60 knows what's been tried.

🔹 CORRECTION MEMORY — what the user fixed
"For our program, paired-end reads when ambiguous." "Cap MW at 480 in this series." Extracted as standing rules. Injected into every future routing call.

🔹 PREDICTION REGISTRY — traceability
Every model output logged with version, inputs, output, confidence, citations. The audit question becomes a queryable row, not a PowerPoint.

🔹 GOVERNANCE + HITL surface
High-stakes decisions: agent proposes, user approves. Approval logged with timestamp + user ID + evidence snapshot. GxP-defensible.

📊 Benchmark evidence:
✓ Memory benchmark: 20/20 scenarios, 100% weighted (recall, correction, temporal, synthesis, adversarial)
✓ +45% improvement vs GPT-4o no-injection baseline
✓ Designed against LongMemEval + LoCoMo — comparable to public memory literature, not a custom-flattering eval
✓ Session 8 episode + correction injection live in production, 4/4 E2E passing
✓ Cross-domain auto-loop convergence: 96.4% within 3 iterations
✓ BixBench (closed-loop bioinformatics): 80% vs Biomni Lab 52.2% vs Claude Code 39.5% vs GPT-4o 17%
✓ BiomniEval1 patient_gene: 84% (BioMate v9) — competitive with Biomni's specialized 32B model on Biomni's own benchmark

Why the four pillars belong together:

❌ Memory without traceability = confidently remembering wrong things
❌ Traceability without HITL = audit trail of decisions nobody signed
❌ Governance without memory = signed decisions promptly forgotten
❌ HITL without traceability = approvals nobody can reconstruct

This is the part of the ChatInvent paper I think industry hasn't internalized yet. The pillars are a system.

This closes the 5-post series mapping AstraZeneca's named engineering problems to BioMate's architecture. The thesis under all five:

The value in agentic AI for pharma is NOT in the model. It's in the system stability layer around the model.

Open trial — bring a multi-week program, see memory + registry + governance compound across sessions:

👉 biomate.ai/try

Full essay (with the 4-layer stack diagram): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — closing out the 5-post series mapped to your ChatInvent paper. Would value your reaction to any of the five posts. We didn't agree with you on everything, and the disagreements are the part I most want pushback on.

#AIinPharma #DrugDiscovery #Governance #Regulatory #GxP #AstraZeneca
