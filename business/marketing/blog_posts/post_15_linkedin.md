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

What we built at BioMate is a single closed loop with four moving parts:

🔹 PER-PHASE QC GATES grounded in published thresholds (FDA, ICH, primary literature)
🔹 REMEDIATION PROPOSALS with a was → now parameter diff and a citation to the rule behind the fix
🔹 USER APPROVAL surface — human-in-the-loop, no surprise re-runs
🔹 ONE ORCHESTRATOR across many domains — shared architecture, domain-specific rules

📊 Production evidence:
✓ Cross-domain auto-loop convergence: 96.4% within 3 iterations
✓ Coverage across ADMET, CYP-DDI, docking, NCA-PK, and cryo-EM (production E2E green)
✓ Every remediation logged with citation + user-approval timestamp — GxP-defensible

The standard "AI for drug discovery" pitch is better one-shot prediction. 91% AUC. 0.3 Å better RMSD.

The real bottleneck isn't one-shot accuracy.

It's the iteration cycle: how many days between "workflow gave me X" and "I have something better than X."

In typical R&D today: 3–14 days, gated by a human bioinformatician.

Auto-loop: minutes — with the full audit trail regulators need.

Compounding productivity isn't one model getting better. It's the cycle getting 100× faster while staying defensible.

Open trial — bring an ADMET hit series with hERG liabilities, watch the loop propose → approve → converge:

👉 biomate.ai


@Jiazhen He @Ola Engkvist @Samuel Genheden — the closed-loop QC remediation is where I think we diverge most from ChatInvent. Would love your view on the human-approval surface.

#AIinPharma #DrugDiscovery #ADMET #PBPK #Pharma #AstraZeneca
