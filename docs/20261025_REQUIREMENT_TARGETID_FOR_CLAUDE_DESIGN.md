# Requirements — Target Identification (for Claude Design)

**Date:** 2026-10-25. **For:** Claude Design (target-ID demo/walkthrough) + engineering.
**Scope note:** this is a **demo of what we have** — a showcase of the working capability.
**No** internal benchmark discussion, **no** maturity/status badges, **no** roadmap or gap items.
Accurate and confident. Sources (for engineering, not for the demo copy): the `target_id`
module `backend/lib/galaxy/ai/target_id/` + `backend/.../api/target_id_api.py`
(`identify_targets` / MCP).

Today the only target-ID HTML is the marketing "five gates" page — it does **not** show the
real pipeline. This is a product walkthrough of the real one.

---

## What target identification is (the capability to show)

You give BioMate a **disease / indication**. It gathers evidence for candidate targets from
**multiple independent sources in parallel**, fuses them into a **ranked target list where every
target carries its evidence and provenance**, routes each target to its **best drug modality**,
and launches the **validation workflows** — all in one transparent flow.

## Flow to depict

1. **Input — a disease / indication** (e.g. rheumatoid arthritis; an EFO/MONDO id when known).
2. **Parallel evidence channels** (run together; each shows its own contribution):
   - **Human genetics** — Open Targets disease→target association (causal genetic support).
   - **Network / pathway** — STRING PPI proximity + pathway co-membership to known disease genes
     (mechanistic connection).
   - **LLM-reasoned evidence** — a frontier model scores each candidate for disease-specific
     target evidence.
   - (Curated data channels, e.g. dependency/essentiality, where available.)
3. **Arbiter → a ranked target list** (Open Targets harmonic-sum fusion). Each ranked target shows:
   - a **score + confidence tier** (corroborated / nominated),
   - **which channels fired** and the **per-channel evidence** (transparent provenance — click
     through to the source),
   - any **conflict / veto** flag.
4. **Target → modality routing** — each top target is routed to its best modality:
   antibody / small molecule / PPI-disruptor / **PROTAC** / molecular glue / **cyclic peptide**.
5. **Nominate → validate** — launch the BioMate validation workflows on the top targets
   (druggability/tractability, differential expression, structure + docking, CRISPR-perturbation).

## What the demo must show

1. **Disease in → ranked, evidence-backed targets out**, with the **per-channel provenance**
   visible (the differentiator vs a black-box list — every ranked target traces to its sources).
2. **Multiple evidence sources working together**, not a single lookup — genetics + network +
   LLM-reasoned, each contributing visibly.
3. **Transparent confidence** — tier + which channels agreed/conflicted, so a researcher can
   judge each target.
4. **Modality routing + the hand-off to validation** — target ID is not the end; each target is
   routed to a modality and into runnable BioMate workflows (and, for cyclic peptides, into the
   peptide design loop — see the loops requirement).

## Accuracy (so the demo stays truthful — not status badges, just don't overclaim)

- Frame it as **evidence-grounded prioritization with transparent provenance** — ranking targets
  by the strength of real, cited evidence. Do **not** claim BioMate "discovers novel targets by
  AI reasoning" or "out-ranks Open Targets"; that's not the message.
- **Only real evidence sources** — Open Targets, STRING, pathway sets, the LLM-reasoned channel,
  curated data. **Do not invent sources** (e.g. no "patent search" unless it exists).
- The honest, usable thesis to lean on: **human-genetic support roughly doubles approval success**
  (Nelson/Minikel) — that's why genetic evidence anchors the ranking. (A positive framing, real.)

## Fixed
Multi-source evidence with per-channel provenance; transparent confidence tiers; modality routing
+ validation hand-off; real sources only; evidence-prioritization (not novel-discovery / not
"beats Open Targets") framing.
