# LinkedIn feed post — Post 19 (In Vivo Base Editing / VERVE-102)

**Recommended hero image:** the 4-phase pipeline + VERVE-101/102 CMC flag. See `figures/post_19_base_edit_pipeline.drawio.xml`.

**Character count:** ~2,400 / 3,000 limit.

---

Q4 2024: Verve Therapeutics dosed the first patient with VERVE-102.

The most-watched gene-editing trial in the world. PCSK9 base editing, one-shot, replaces every-2-week Repatha/Praluent injections with a single IV dose for life.

VERVE-101 (the first iteration) was paused in 2023 after two patients showed elevated liver function tests. Verve reformulated the LNP for VERVE-102. The lesson cost ~$200M.

Can BioMate recover the VERVE-102 architecture from just "loss-of-function PCSK9 for hypercholesterolemia"? Yes — in 4 phases.

1️⃣ Atlas tissue check — PCSK9 is hepatocyte-restricted. LNP-IV delivery is ideal: >90% on-target tissue with minimal off-target editing. The atlas confirms this in seconds.

2️⃣ Editor selection — CBE (cytosine → thymine) wins because the cheapest path is a premature stop in exon 1. The W8 codon (CAA, Trp) converts to TAA (stop). Exactly what Verve published.

3️⃣ Guide RNA design — 20-nt protospacer in PCSK9 exon 1, NGG PAM within editing distance, editable C at position 4-8, no off-targets within 3 mismatches.

4️⃣ CMC flag emission — surface the VERVE-101 LFT signal as a CMC risk for VERVE-102. The agent reads the tool_knowledge database, finds the 2023 hepatotoxicity update, emits "CMC reformulation: optimize LNP for lower hepatotoxicity (per VERVE-101 LFT precedent, Nov 2023)".

This last phase is the difference between a generic gene-editing pipeline and one that knows what happened in November 2023.

You can ask ChatGPT for "PCSK9 base-editing design" and get a fluent answer that names CBE, mentions the W8 codon, and lists the right LNP composition. What it won't do:

❌ Flag the VERVE-101 LFT signal as a CMC risk (that's in a press release, not PubMed)
❌ Cite ANGPTL3 / HMGCR / CFTR as parallel/wrong-platform cases when you swap targets
❌ Refuse to assemble for CFTR because the lung needs a different delivery platform

BioMate grounds against an 11-topic knowledge base that includes corporate program updates. When the workflow runs for PCSK9 loss-of-function, the agent reads VERVE-101's history and emits the reformulation flag.

That's the gap between fluent and grounded.

Run BioMate on PCSK9 — recover VERVE-102.
Run it on ANGPTL3 — recover VERVE-201.
Run it on CFTR — get a "wrong delivery platform" warning.

The same pipeline. Different biology. Different answer.

VERVE-101's failure cost ~$200M. The next program shouldn't.

👉 biomate.ai

Full essay (with diagrams): [link to Substack post]

#GeneEditing #BaseEditing #VerveTherapeutics #AIinPharma #BiotechInnovation
