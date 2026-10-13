# Website revisions from leadership feedback — 2026-10-13

Acted on page-by-page site feedback (homepage, Services, Drug Discovery, Research
Engines, Cyclic Peptide section). Goal: shift the public site from "what we plan
to do" toward "what we have done," ahead of ACT reviewers and the US Biotech
Summit — **without disclosing any internal program specifics**.

Site source: `reference/claude_design/webpage_design_v2/` (static HTML, canonical
public site). Shared style system: `workbench.css` + `styles.css` (`wb-*` classes,
cream/navy brand tokens).

## Guardrails respected
- **No internal disclosure.** No target names (αvβ6/GRPR), no ACT/SDL, no
  collaborators (SYSUCC/MDA), no methods/architecture, no pilot results. Immune
  drug discovery is framed at the **capability / therapeutic-area** level only.
- **Citation integrity.** Every proof point added to the homepage is a figure
  **already published on `benchmarks.html`** — nothing new was asserted.
- **Continuous loop first, dates as phase markers within it.** A start→finish dated
  line ("…complete", "validation Q4 2026 → results Q1 2027") reads as a one-shot
  waterfall and kills the iteration story. Final framing keeps the loop central AND
  shows Q4/Q1 estimates as rounds *within* the ongoing cycle:
  - drug-discovery chip = "Active program · design → evaluate → test → learn,
    iterating continuously" (no dates on the teaser).
  - research-engines = loop diagram + "The loop runs continuously…" + an
    **"Estimated phasing"** strip of two chips: "Q4 2026 · first wet-lab validation
    rounds enter the loop" and "Q1 2027 · results feed the next round of designs."
    Wording ("rounds", "enter the loop", "next round") keeps it cyclic, not linear.

## Changes by file

### `workbench.css` (additive, shared)
Added reusable, token-based, responsive classes: `.wb-proof` (stat band),
`.wb-flow` / `.wb-flow--arrow` (numbered step flow for the worked example and the
loop diagram), `.wb-note`, `.wb-cycle-note`. Mobile: collapse to 2-up, hide arrows.

### `index.html` (Homepage)
- **Headline** `Move science forward.` → **`AI that designs, tests and learns.`**
  (the feedback's own framing); subhead → `From target to candidate. / From raw
  data to reproducible result.` Kept platform breadth in the subhead rather than
  narrowing the top headline to one modality.
- **Proof band** (new tint section after hero): 92.7% BixBench (vs Biomni 88.7%),
  90.8% routing (94.6% incl. equivalents), 4,000+ pipelines, 100% PBPK — plus the
  **Innovation Partner** line for the Autoimmune Neuromuscular & Nerve Disorders
  Drug Development Summit, linking to `benchmarks.html` and `blog-summit-2026.html`.
- Discovery paragraph now names **immunology, immuno-oncology** and cyclic-peptide.

### `drug-discovery.html` (Drug Discovery)
- **Worked example** (new section): target context → ~2,000 generated → ~180 pass
  ADMET/developability → 12 shortlisted. Clearly labeled **illustrative**.
- **Therapeutic areas named**: "immunology and immuno-oncology" (was "immune biology").
- **Security/data line** added to the closing band: "Private deployment options.
  Your data and results stay yours."
- **Program-status chip** added to the cyclic teaser (mirrors Research Engines).
- Preserved section light/tint rhythm.

### `research-engines.html` (Cyclic Peptide section)
- Added **How it works** (structure-aware generation conditioned on target +
  binding site → computational scoring → ranked shortlist) and **Where it is
  applied** (immune / immuno-oncology target class, no target named).
- Kept **"Candidates remain hypotheses until tested experimentally."**
- Added the **4-step loop diagram**: Design → Computational evaluation →
  Synthesis & assays → Model update, with a "loop repeats" note.
- **Continuous-loop** framing: loop diagram + "The loop runs continuously…" + an
  "Estimated phasing" strip with Q4 2026 and Q1 2027 milestone chips framed as
  rounds within the ongoing cycle.
- Hero now names immunology, immuno-oncology, cyclic peptides.

### `compare.html` ("BioMate vs. the alternatives") — reviewed, no change
Every named-competitor claim is already tied to a sourced benchmark (BixBench
92.7%; BiomniEval1 68–69% vs Biomni 65.9%; LABBench 93.9% vs Claude 3.5 Sonnet 60%
from Jansen et al. 2025). Capability-based and citation-backed — meets the ask.

## Tested
- `reference/.../webpage_design_v2/tests` → `node --test`: **50/50 pass** (link/
  fragment resolution, unique IDs, SEO, static shell, navigation).
- Tag-balance check on all three edited pages: balanced.
- Full-page screenshots (1280px) of all three pages: components render on-brand,
  section rhythm clean, no overflow. Screenshots in session scratchpad.

## Open / deferred
- `index.html` headline is a brand-level choice; easy to swap if leadership
  prefers the explicit "…from target to cyclic peptide" variant.
- Services page: no change (feedback said it's already clean).
- These edits are to the source site tree; publishing/deploy of the public site
  is a separate step outside this change.
