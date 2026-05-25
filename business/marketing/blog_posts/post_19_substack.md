# In vivo base editing — how BioMate reconstructs VERVE-102 from "knock out PCSK9 in the liver"

*Q4 2024: Verve Therapeutics dosed the first patient with VERVE-102 — the second iteration of their in vivo PCSK9 base-editing program, after VERVE-101 hit a liver-enzyme signal in 2023. VERVE-102 is the most-watched gene-editing trial in the world right now. Beam BEAM-101 is close behind. And the design lessons from VERVE-101 → VERVE-102 are public. Can BioMate recover the VERVE-102 architecture from "loss-of-function PCSK9 for hypercholesterolemia"? Yes — in 4 phases.*

---

## Why VERVE matters

Pharma spent 30 years on PCSK9. Repatha (Amgen, 2015) and Praluent (Sanofi/Regeneron, 2015) brought monoclonal antibodies to market — but both require biweekly injection. Inclisiran (Novartis, 2021) brought siRNA twice-yearly.

Verve's pitch: one-shot. CBE base editor + PCSK9 gRNA + LNP. The base editor introduces a premature stop codon at PCSK9 W8 (CAA → TAA). The protein is never expressed. LDL drops. Patient is done — for life.

VERVE-101 (2022) saw two patients with elevated liver function tests in Phase 1b. Verve paused VERVE-101 and pivoted to VERVE-102 — a reformulated LNP designed to reduce hepatotoxicity.

That reformulation is the CMC story BioMate has to surface.

## The 4 phases

> 📊 **Figure 1** — `figures/post_19_base_edit_pipeline.drawio.xml` (4-phase block diagram)

**Phase A — Atlas tissue check.** PCSK9 is hepatocyte-restricted — almost zero expression outside the liver. That makes LNP-IV delivery ideal: a hepatocyte-tropic LNP gets to >90% of the on-target tissue with minimal off-target editing elsewhere. The atlas confirms this in seconds.

Compare to ANGPTL3 (Verve's second target, VERVE-201): also hepatocyte-restricted. PCSK9, ANGPTL3, and HMGCR are all good in vivo base-editing targets because the biology lives in one tissue. CFTR (lung) and DMD (muscle) are not — they need different delivery platforms.

**Phase B — Editor selection.** Three viable base editors:
- CBE (cytosine → thymine): introduces premature stops via CAA → TAA / CAG → TAG / CGA → TGA
- ABE (adenine → guanine): correcting SNPs, restoring lost function
- Prime editing: precise insertion/deletion, but lower in vivo efficiency

For PCSK9 loss-of-function, CBE wins because the cheapest path is a premature stop in exon 1. Phase B emits "CBE selected — premature stop strategy" with literature citations.

**Phase C — Guide RNA design.** Identify a 20-nt protospacer in PCSK9 exon 1 with:
- An NGG PAM within editing distance of the target codon
- An editable C in the 4-8 position of the protospacer
- No off-targets within 3 mismatches in CRISPR off-target databases

For PCSK9, the W8 codon (CAA, Trp) is the canonical target — converts to TAA stop. The gRNA matches what Verve published.

**Phase D — CMC flag emission.** Surface the VERVE-101 LFT signal as a CMC risk for VERVE-102. The agent reads the tool_knowledge database, finds the 2023 Verve update on VERVE-101 hepatotoxicity, and emits a "CMC reformulation: optimize LNP for lower hepatotoxicity (per VERVE-101 LFT precedent, Nov 2023)" flag.

This is the difference between a generic gene-editing pipeline and one that knows what happened in November 2023.

## Why this isn't possible without grounding

The Verve / Beam / Prime base-editing literature is fragmented across:

- Liu lab Nature papers (2016, 2017) — original CBE/ABE chemistry
- Verve corporate releases (2022, 2023) — VERVE-101 and -102 program updates
- FDA briefings — INDirect references during the 2023 pause
- Editas, Beam, Prime, Intellia investor decks

A general-purpose LLM blends these. It will tell you CBE is the right editor for PCSK9, but it will not flag the VERVE-101 LFT signal as a CMC risk — because that signal is in a press release, not in PubMed.

BioMate grounds against a 11-topic cryo-EM and gene-editing knowledge base (`cryo_em_chunks` and `tool_knowledge` tables) that includes corporate program updates. When the workflow runs for PCSK9 loss-of-function, the agent reads VERVE-101's history and emits the reformulation flag.

That's the gap between **fluent** and **grounded**.

## Try it

```
Base editing strategy for PCSK9 loss of function in hypercholesterolemia
```

→ [biomate.ai](https://biomate.ai)

30 seconds. 4 phases.

Run it again with ANGPTL3 → BioMate produces VERVE-201's design. Run it with HMGCR → it'll flag "rosuvastatin already covers this; LDL-lowering bar is high" as a competitive note. Run it with CFTR → it'll flag "lung delivery; LNP-IV is wrong platform" and refuse to assemble.

VERVE-101's failure cost ~$200M to learn. The next program shouldn't.

---

*Yaoyun Wang is the founder of BioMate, an agentic AI orchestration platform for drug development.*
