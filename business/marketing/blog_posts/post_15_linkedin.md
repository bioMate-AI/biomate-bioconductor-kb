# LinkedIn feed post — Post 15

**Hero image:** `figures/post_15_auto_loop.drawio.xml` exported as 1200×627 PNG.

**Character count:** ~2,700 / 3,000.

---

**Posting note:** retype the `@` in front of each name in LinkedIn's composer to resolve real profiles.

---

The workflow ran. It didn't crash. The output files exist.

The science is still wrong.

- ADMET screen: 25% hERG-flag rate, gate is 10%
- Cryo-EM: stuck at 4.2 Å with blobby 2D classes
- NCA-PK: AUC extrap at 38%, FDA cap is 20%
- RNA-seq: half the samples have RIN 4.1

In every case the agent says "done!" and hands the result to a bioinformatician. Days pass. Next run has a different problem. More days.

This is workflow instability — fourth in the five engineering problems named by @Jiazhen He @Ola Engkvist @Samuel Genheden and the AstraZeneca team in "Democratising real-world drug discovery through agentic AI" (Drug Discovery Today, doi: 10.1016/j.drudis.2026.104605). It's the failure mode that sets the productivity ceiling on agentic AI in pharma.

What we built at BioMate, four pieces working as a single closed loop:

🔹 PER-PHASE QC GATES with configured thresholds
ADMET (Aronov / Lammert / Kazius). CYP-DDI (FDA 2020 R1/R2). Docking (Vina kcal/mol). NCA-PK (FDA AUC extrap ≤20%). CryoEM (CTF, FSC, particle dist). Each gate: pass / advisory / halt.

🔹 REMEDIATION PROPOSALS with was → now diff
"hERG-flag 25% > gate 10%. Proposed: tighten logP ≤ 4.5, MW ≤ 500 (Aronov 2008). Was: ≤5/≤550. Now: ≤4.5/≤500."

Every proposal carries a citation to the rule behind it.

🔹 USER APPROVAL surface
Human-in-the-loop. No surprise re-runs. The user sees the diff, the citations, approves or rejects with one click.

🔹 ONE ORCHESTRATOR, MANY DOMAINS
Shared architecture; domain-specific rules. Adding a new auto-loop is one PHASES list + QC gates + remediation rules.

📊 Production benchmark evidence:
✓ ADMET auto-loop: 24/24 tests + ADMET benchmark 89.3%
✓ CYP-DDI auto-loop: 24/24 tests
✓ Docking auto-loop: 24/24 tests
✓ NCA-PK auto-loop: 24/24 tests
✓ CryoEM auto-loop: 95/95 unit + 24/24 E2E
✓ Cross-domain convergence: 96.4% within 3 iterations
✓ BixBench (closed-loop bioinformatics execution): 80% vs Biomni Lab 52.2% vs Claude Code 39.5% vs GPT-4o 17%

That's 96/96 across four drug-development domains + 95+24 for cryo-EM. Same engineering team. Same quarter.

The standard "AI for drug discovery" pitch is better one-shot prediction. 91% AUC. 0.3 Å better RMSD.

The real bottleneck isn't one-shot accuracy.

It's the iteration cycle: how many days between "workflow gave me X" and "I have something better than X."

In typical R&D today: 3–14 days, gated by a human bioinformatician.

Auto-loop: minutes — with the full audit trail regulators need.

Compounding productivity isn't one model getting better. It's the cycle getting 100× faster while staying defensible.

Open trial — bring an ADMET hit series with hERG liabilities, watch the loop propose → approve → converge:

👉 biomate.ai/try

Full essay (with auto-loop cycle diagram): [Substack link]

@Jiazhen He @Ola Engkvist @Samuel Genheden — the closed-loop QC remediation is where I think we diverge most from ChatInvent. Would love your view on the human-approval surface.

#AIinPharma #DrugDiscovery #ADMET #PBPK #Pharma #AstraZeneca
