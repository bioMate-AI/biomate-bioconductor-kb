# BioMate Tutorial Video Audit — Layman Reviewer
## From a non-expert perspective

---

## Verdict: Partial Success

A complete newcomer would understand the **one-loop concept** in T0 and could follow the basic workflow in T3–T4. However, tutorials T1 and T2 introduce domain-specific jargon too rapidly without sufficient scaffolding. The drug-development walkthrough, while ambitious, compresses eight stages into a dense script — best suited to someone already familiar with drug discovery vocabulary. **Strongest for: first-time navigation. Weakest for: understanding the science behind each step.**

---

## Per-Video Clarity (1–5 scale) and Key Confusion Points

| Tutorial | Rating | Biggest Confusion |
|----------|--------|-------------------|
| **T0 — Getting Started** | 4.5 | None major. Only minor: the word "composer" isn't intuitive for "message box," but it's explained on-screen. |
| **T1 — Design & Generate** | 2.5 | Jargon barrage: SMILES, BRICS, TPSA, logP, scaffold, structural alerts, Pareto all hit in rapid succession. No visual example of what a BRICS output looks like or why "Stay" vs "Hop" matters chemically. |
| **T2 — Models & Closed Loop** | 2 | Most abstract. "Applicability domain" is explained as preventing bad predictions, but the RA example is hypothetical. "Held-out test" assumes stats background. Hard to visualize what a "model" object *looks like* in practice. |
| **T3 — Run & Workflow** | 3 | Moderate. ADMET is never defined. hERG appears without intro—named as "cardiac potassium channel" only in the drug-dev tutorial but used here. The concept of "QC gates halting a run" needs a visual demo of the halt happening. |
| **T4 — Bringing Your Own Data** | 3.5 | "Effective N" (usable sample size when data is correlated/imbalanced) is too advanced without prior stats context. "Class balance" mentioned without explaining why imbalance matters. Otherwise clearer than T1–T2. |
| **Drug-Dev Walkthrough** | 2 | Compresses eight stages into six minutes. Each intro is ~30 seconds. REINVENT4, RBFE, MD, PK, PBPK, SAR, IC50 all named but minimally explained. A complete newcomer would finish confused about which stage is which. |

---

## Unexplained Jargon & Explanations Found

- **SMILES**: Defined ("a standard text code for a structure") but speed of intro makes it feel like a term to memorize, not understand.
- **Scaffold**: Defined ("a molecule's core skeleton") but no visual of a scaffold vs. decorated scaffold.
- **BRICS**: Named only—"a rule-based method"—no sense of what output it produces or why it matters.
- **logP & TPSA**: Defined in words ("oily vs. water-loving," "polar surface") but abstract without molecular structures shown.
- **Pareto front**: Defined as "trade-off boundary" but the mathematical concept behind Pareto ranking is opaque.
- **ADMET**: Never explicitly defined; appears in T3 without intro. Should be: "Absorption, Distribution, Metabolism, Excretion, Toxicity—five safety properties."
- **hERG**: Named as "cardiac potassium channel" only in drug-dev; used in T3 without that intro. Newcomer will not grasp why it's the "make-or-break" endpoint.
- **QC gate**: Explained as "automatic mid-run check" but concept of gating (blocking, halting) is not visually demonstrated.
- **Effective N**: Defined as "usable sample size when data is correlated/imbalanced"—too advanced for an ingest check tutorial.
- **Phred score**: Named ("average base quality") but has no explanation of the scale or what "below twenty" means.
- **Lineage**: Ubiquitous term; defined late and incompletely. Deserves its own slide in T4.
- **Held-out test**: Assumes understanding of train/test splits and why they prevent overfitting.
- **REINVENT4, RBFE, MD, SAR, PK, PBPK, IC50**: Named in drug-dev; minimal explanation of differences or why each stage exists.

---

## Pacing & Length Issues

1. **T0**: Good pacing. Clear sections. ~3:40 runtime appropriate.
2. **T1**: Feels rushed. Five new chemistry concepts in 6:30 without visual examples. Property window (molecular weight, logP, TPSA) introduced as defaults—newcomer unsure why these matter.
3. **T2**: Extremely dense. Model theory, validation, applicability domain, inference, custom training, rounds, evidence floors—all in 6:55. Little breathing room between concepts.
4. **T3**: Better structured. Follows a real run. Clear checkpoints (pre-run, running, completed). ~4:45 is reasonable.
5. **T4**: Moderate. Clear sections (Preview, Quality, Lineage, etc.). ~6:45 but concepts stack near the end.
6. **Drug-Dev**: Too long, too dense. 8 stages × 6 min = compressed narrative. Each idea-concept pairing helps, but 30-second intros are insufficient for newcomers. Would benefit from a 2-minute prerequisite video on "what is drug discovery."

---

## Concrete Suggestions for Clarity

1. **Add a 2-minute prerequisite video** before T1 and drug-dev: "What is drug discovery, and why does it take so long?" Introduce ADMET, hERG, and Pareto at that level.

2. **T1: Show a visual example** of BRICS output—before/after scaffold examples. Show why "Stay" (conservative) vs "Hop" (patent-dodging) matter in the real world.

3. **T2: Add a concrete example** of an applicability domain failure. E.g., "A model trained on kinase inhibitors predicts peptide binding → wrong. Here's why."

4. **T3: Lead with a 30-second ADMET definition** before Step 2. Rename the step "ADMET safety check" to signal domain.

5. **T4: Separate "Lineage" into its own explanatory slide.** Newcomers conflate it with "Consumers" and "Versions." Show how lineage answers "where did this number come from?"

6. **Drug-Dev: Consider splitting into two videos:**
   - **Drug-Dev A (4 min):** Stages 1–4 (goal, design, properties, structure).
   - **Drug-Dev B (4 min):** Stages 5–8 (ranking, QC, dose, record).

7. **Add on-screen tooltips or captions** for first use of jargon (SMILES, Pareto, hERG, Phred, effective N) so the narration doesn't have to repeat them.

---

## Summary

**Strongest videos:** T0 and T3 are clear and follow a logical flow. A newcomer can follow them.

**Weakest video:** T2 (Models) assumes too much prior knowledge of machine learning and validation.

**Gap:** No intro video on "what is drug discovery" and why the eight stages exist. T1 and drug-dev will confuse newcomers who don't know why ADMET, hERG, or Pareto matter.

**Actionable fix:** Reorder as: (new) What is drug discovery → T0 → T1 (with BRICS visual) → T2 (with concrete failure example) → T3 → T4, then drug-dev as an optional deep-dive.
