# Website repositioning — from "AI platform" to a biotech that owns a realm

**Date:** 2026-10-16 · The homepage currently positions BioMate as an AI tools/platform vendor. The ask: position
like a biotech (the Moderna model) — **own a therapeutic realm, with AI + automation as the engine beneath** —
and surface the drug-development challenges we systematically engineer against (multi-round optimization +
wet-lab validation). Register: formal, honest, capability-level; pre-clinical stage stated plainly.

---

## 1. Diagnosis — why the current site reads as a tools vendor, not a biotech

| | Moderna (the model) | biomate.ai (today) |
|---|---|---|
| Hero | "Pioneering mRNA technology" — a **modality + medicines** | "AI that designs, tests and learns" — an **engine** |
| Positioning | A biotech; mRNA is the realm it owns | "The AI platform for biomedical research & drug discovery" — a platform |
| Tech framing | Platform/automation **beneath** the medicine ("design, test multiple mRNAs within days") | AI is the **headline**, not the beneath |
| Proof | Pipeline (45 programs, 36 trials), science, disease breadth | Benchmarks (BixBench 92.7%), services, research engines |
| Missing on our site | — | the **realm** we own, the **hard problems** of drug dev, **multi-round + wet-lab** rigor |

**The core flaw in the hero.** "AI that designs, tests and learns" describes *the engine*, not *what we make or
for whom*. Moderna never leads with "AI that designs mRNA" — it leads with **mRNA medicines**, and lets the
platform sit underneath. Leading with the engine makes us read as a vendor of AI tooling, not a biotech that
owns a realm.

## 2. The repositioning — Moderna's structure, applied honestly to BioMate

**One-line identity:** *A biotech engineering the next generation of therapeutics for immune-mediated disease —
built on a self-improving design → make → test → learn loop.* (mRNA : Moderna :: the closed-loop
cyclic-peptide/macrocycle engine : BioMate.) The AI and automation are the **how**, not the **what**.

Homepage section architecture (replaces the current order):
1. **Hero** — the realm + the medicine; the engine named beneath (not as the headline).
2. **The realm we own** — immune-mediated disease (autoimmune + immuno-oncology): why it's hard, why we focus.
3. **The modality** — AI-designed cyclic / macrocyclic peptides (+ radioligand theranostics): the programmable,
   target-general modality (our "mRNA" — one engine, many targets).
4. **The hard problems of drug discovery — and the system we built for each** (the challenge inventory as rigor).
5. **The loop** — design → make → test → learn: multi-round optimization + wet-lab validation.
6. **Pipeline / programs** — lead program + the immune-mediated portfolio (Moderna-style pipeline, honest stage).
7. **The engine beneath** — the AI + automation platform (generative models, honest verifier, AWS Batch,
   private/auditable). This is where today's "platform" content lives — as the enabler, not the identity.
8. **Credibility, honestly stated** — the real data, validated subsystems, benchmark wins; pre-clinical, building.

---

## 3. Draft copy (usable)

### Hero (pick one headline; sub-line is shared)
- **A** (realm-first): **"Engineering the next generation of therapeutics for immune-mediated disease."**
- **B** (modality-first, most Moderna-like): **"Programmable cyclic-peptide therapeutics for immune-mediated disease."**
- **C** (loop-first): **"A biotech built on a loop that designs, makes, tests, and learns — for immune-mediated disease."**

**Sub-line:** *"We take on the hardest molecules in drug discovery — the ones competitors defer — and prove them in
the wet lab. A closed loop of generative design, honest multi-constraint verification, and experimental feedback
turns every round into a better next molecule."*

> Why this works: it names the **what** (therapeutics), the **realm** (immune-mediated disease), the **modality**
> (cyclic peptides), and the **engine** (the loop) — with AI/automation implied as the enabler, exactly Moderna's
> order. "AI that designs, tests and learns" becomes a caption on the engine section, not the masthead.

### Section 4 — "Drug discovery fails on the hard gates. We built a system for each."
Lead: *"A molecule that binds is the easy part. Candidates die on selectivity, developability, freedom-to-operate,
mechanism-correct physics, and the inability to learn from each experiment. We engineer against each one as a
first-class part of the loop — not a post-hoc filter."* Then a grid (grounded in the challenge inventory):

| The hard problem | What we built |
|---|---|
| **Selectivity** (binding ≠ on-target) | counter-target scoring in-loop; selectivity a first-class objective |
| **Developability & permeability** | calibrated predictors as gates, not afterthoughts |
| **Freedom-to-operate / novelty** | patent-claim + structure/compound screening before synthesis |
| **Mechanism-correct physics** | target-aware scoring (e.g. metal-dependent sites modeled explicitly) |
| **Multi-objective optimization** | Pareto selection across activity · safety · synthesizability |
| **Closing the loop with the wet lab** | design → CRO synthesis → assay → the model learns from the result |
| **Data scarcity** | a proprietary, growing base of real measurements compounding each round |

*(Honesty note for the build: several of these are validated in-silico / on retrospective real data; the loop's
learning-from-real-wet-lab-feedback is being proven now. Keep the copy at "we engineer against / we built a system
for" — the systematic approach — not "solved." See `20261005_CHALLENGE_INVENTORY_RECOVERED.md` for per-item status.)*

### Section 5 — "It takes many rounds, and the wet lab decides." (the program as example)
*"Designing a real therapeutic is not one shot. For a single target we run multiple optimization rounds — generate,
score against every gate, select the Pareto-best, synthesize a focused set, test in the wet lab, and feed the
results back so the next round is better. The hard gates (selectivity vs. homologs, developability, freedom-to-
operate, mechanism-correct binding) are enforced every round. The wet lab, not the model, is ground truth."*
Use the lead program as the illustration (capability-level, the stage already shown in the ACT materials): a
cyclic-peptide radioligand against αvβ6 for pancreatic cancer, with the broader immune-mediated portfolio behind it.

### Section 7 — "The engine beneath" (where the current platform content moves)
*"Beneath every molecule is a self-hosted engine: a generative model for cyclic/macrocyclic chemistry, an honest
multi-constraint verifier, physics validation, and automated cloud execution — running privately, deterministically,
and auditable end to end. The same engine powers our research platform."* (The existing 4,210-workflow /
instrument-connectivity / private-deployment content lives here as the enabler — not as the company's identity.)

---

## 3b. "Therapeutic Areas" page — the disorder categories we target (Moderna-style)

Moderna's site has a Therapeutic Areas / Pipeline page listing the disease areas it works in. BioMate should have
the same — it is what makes us legible as a biotech that **owns the immune-mediated realm**. Grounded in the
cross-disease target scorecard (`docs/20260727_CROSS_DISEASE_TARGET_SCORECARD.md`, 8 OT-ranked autoimmune diseases)
+ the 16-target autoimmune panel + the immuno-oncology arm. **Honest framing: these are the disease categories and
validated mechanisms we DESIGN FOR (pre-clinical focus areas), not programs in the clinic.**

**Page header:** *"Immune-mediated disease — where we focus."* Sub: *"One engine, many targets. We design
cyclic-peptide and macrocycle therapeutics against the mechanisms that drive immune-mediated disease — anchored on
human genetics and validated target biology."*

| Category | Disorders | Validated mechanisms we design against | Modality |
|---|---|---|---|
| **Rheumatologic & systemic autoimmune** | Rheumatoid arthritis, Lupus (SLE) | TNF, IL-6R, CD40, BAFF, CTLA-4, TYK2 | cyclic-peptide PPI blockers |
| **Inflammatory bowel disease** | Crohn's, Ulcerative colitis | IL-23 / IL-12B, α4β7 integrin, TNF, JAK | PPI blockers + integrin (metal-site) binders |
| **Dermatologic & spondyloarthritis** | Psoriasis, Ankylosing spondylitis | IL-17A/F, IL-23, TNF, TYK2 | cyclic-peptide PPI blockers |
| **Neuroimmune** | Multiple sclerosis, Myasthenia gravis | C5 (complement), FcRn, CD20, S1P₁, IL-2Rα, α4 integrin | PPI blockers + integrin binders |
| **Endocrine autoimmune** | Type 1 diabetes | CTLA-4, TYK2 | cyclic-peptide binders |
| **Immuno-oncology (cold tumors)** | Pancreatic cancer, IO-resistant solid tumors | αvβ6 integrin (lead), PD-L1 | radioligand theranostic (αvβ6) + PPI blocker (PD-L1) |

Design notes for the page:
- Each row → a short card (Moderna-style): disease(s), the mechanism(s), one line on *why cyclic peptides fit*
  (reach PPI/groove targets small molecules miss; private, metal-aware physics for integrins).
- Mark the **lead** clearly (αvβ6 radioligand, PDAC) and everything else as **discovery-stage focus areas**.
- A footnote on provenance: *"Target mechanisms are drug-blind rediscoveries from a human-genetics-anchored
  cross-disease analysis; disease areas reflect where our engine and data are strongest."* (true, per the scorecard).
- CN mirror required (per the platform deck's EN+CN standard).

## 4. Honesty & disclosure guardrails (do not skip)
- **Stage:** we are **pre-clinical / platform-stage**, not a clinical-stage biotech. Do NOT borrow Moderna's "45
  programs / 36 trials" shape as if we have it. Frame as *"a biotech building this realm,"* lead program
  pre-clinical. Credibility = the engine, the data, the validated subsystems — not a clinical pipeline we lack.
- **Capability, not method:** keep the engine described at the WHAT level (per `feedback_no_method_disclosure`).
- **Program disclosure is a founder call:** the Moderna model shows a pipeline. Default to the level already public
  in the ACT investor materials (αvβ6/PDAC lead named; portfolio described by disease area, not proprietary
  targets/sequences). If the site must stay program-silent (`feedback_website_no_internal_work`), use the program
  as an *anonymized* example ("a metal-dependent integrin target") and keep the realm + modality + loop.
- **No fabricated metrics.** Every number traces to ground truth (workflow counts, 136k affinities, benchmark
  cells). No invented clinical/efficacy claims.

## 5. Concrete next step
The local `webpage_design*` dirs are stale (Sep 4) vs. the live site, so changes must land wherever the live site
is deployed. On your word I will: (a) finalize the hero (your pick of A/B/C), (b) draft the full HTML for the
homepage sections 4–7, (c) **build the "Therapeutic Areas" page** (§3b) as a standalone page + a nav item, and
(d) produce EN + CN copy — consistent with the platform deck's register and the honest-stage framing above.
Tell me where the live site is deployed from (repo/path/host) and I'll implement there rather than the stale
`webpage_design*` copies.
