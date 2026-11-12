# BioMate Evidence-Based Writer — Design & Plan

**Date:** 2026-11-12
**Status:** Design + phased plan (naming + skill-group settled; rewrite-only, own content)

> **Provenance / naming.** Informed by reviewing a clinician-authored, buyer-licensed reference
> clinical-writing skill locally as a **design reference only** — it is **not named, copied, or
> vendored** into BioMate (its license bars inclusion of a substantial portion in another product;
> and per product direction no external product name appears in BioMate). Everything here is
> BioMate's own capability, written in our own words. The integrated capability is **BioMate's
> Evidence-Based Writer**.

---

## 0. TL;DR

The **Evidence-Based Writer** turns BioMate's analysis outputs + grounded evidence into
publication-grade clinical manuscript text, with **verified** claim/citation discipline. It closes
the loop BioMate is missing — from analysis to manuscript — and it is the natural home for the
evidence-audit enforcement that the grounded-answer committee review (`docs/20261112_
GROUNDED_ANSWER_COMMITTEE_REVIEW.md`) prioritized.

```
BioMate run / analysis ──► frozen result tables + variable defs + data version
        │                                   │
        │ grounded evidence (federated_query: PubMed/ChEMBL/gnomAD/Open Targets/PDB…)
        ▼                                   ▼
   Evidence-Based Writer ──► Results/Discussion/Abstract draft
        │  (claim labels, citation semantic-fit, internal≠external,
        │   association≠causation, denominators, hedging) — ENFORCED, not just prompted
        ▼
   BioMate manuscript / IND / report pipeline ──► final document
```

**Skill + group (settled).** A BioMate skill **`evidence-based-writer`** with
`domains: [clinical, drug_discovery, pharmacology]` so it is grouped — via BioMate's existing
domain-grouping mechanism (`SkillManager.matches_domain`) — with the relevant existing skills:
`clinical-biostatistician`, `regulatory-affairs`, `evidence-source-selection`,
`source-query-intelligence`. One cohesive **clinical research & evidence** group.

**The improvement thesis.** The reference skill's one ceiling is that it is *unenforced prompt-rules*
— it can only *assert* "check the citation actually supports the sentence," because it hands search
off. BioMate has what it lacks (live `federated_query` search + real run outputs), so our writer
**enforces** the discipline: it verifies each citation against the *actually retrieved* source
(semantic fit), checks every number against the *real output table*, and labels claims — rather
than hoping the model complies.

---

## 1. Scope & boundary (what the Writer owns vs the group)

The Evidence-Based Writer owns **writing + claim/citation audit**. It does **not** duplicate the
group's other skills — it composes with them:

| Capability | Owner |
|---|---|
| Results→manuscript prose; bilingual academic style; section moves; preservation of numbers/denominators/claim-strength | **evidence-based-writer** (new) |
| Claim-evidence audit (claim labels, 4-layer citation check, clinical gates, internal≠external) | **evidence-based-writer** (new; enforced via `federated_query`) |
| Trial design, estimand, sample size, survival/dose-finding stats | `clinical-biostatistician` (existing) |
| FDA/EMA/ICH submission, IND, reporting-guideline authority | `regulatory-affairs` (existing) |
| Which evidence sources to query per question facet | `evidence-source-selection` (existing) |
| How to query each source intelligently | `source-query-intelligence` (existing) |

The Writer **deliberately does not** run statistics, perform live search itself, do Word layout, or
make clinical decisions — it draws stats from BioMate run outputs, evidence from the group's
retrieval skills, and emits text + an audit. (Those are BioMate capabilities, so unlike the
reference skill there is no external hand-off.)

## 1.1 Core discipline (rewritten in our own words)

- **Preservation rules** any edit must keep: research question / design / population; n / events /
  denominators / analysis set; effect direction / magnitude / units / intervals / precision;
  citation position + meaning + locator; primary/secondary/exploratory labels; internal / temporal
  / external validation; association / prediction / diagnostic-accuracy / clinical-utility /
  mechanism status; negative findings + qualifiers + conclusion strength; ethics / registration /
  funding / authorship / data-availability.
- **Claim labels**: `supported` / `partially_supported` / `indirect` / `unsupported` /
  `unverifiable` (fit to the retrieved evidence, not ultimate truth).
- **4-layer citation check**: existence → metadata → locator → **semantic fit**.
- **Clinical gates**: Design / Data / Analysis / Reporting / Claim / Reproducibility.
- **Guards**: association ≠ causation; discrimination (AUC/HR) ≠ clinical utility; internal ≠
  external validation; preserve the denominator/population; no fabricated numbers/IDs; honest
  abstention over confabulation.

These are domain standards (EQUATOR/CONSORT/STROBE/TRIPOD, ICH E9, GRADE-style grading) — we encode
the discipline ourselves and link official checklists directly.

---

## 2. Integration architecture

1. **Skill** `evidence-based-writer` in `SkillManager` (frontmatter `name/title/triggers/domains`,
   body = the discipline above + section moves + the audit protocol). Triggers: writing/audit intent
   (draft results, write discussion, polish abstract, check citations, audit claims, reviewer
   response, reporting check, manuscript/thesis review…). Grouped by `domains` with the clinical/
   evidence skills.
2. **Enforcement, not assertion** — the audit mode calls the group's retrieval
   (`federated_query` / `evidence-source-selection`): for each citation it resolves the id, pulls
   the abstract, and scores semantic fit against the citing sentence; for each DB id it validates
   against the real record (the committee's P2/P3). This is the mechanism the standalone grounded-
   answer fixes also need — build once, use in both.
3. **Results→draft action** (backend): a BioMate run's frozen outputs + a user-confirmed
   analysis-set/denominator spec → a Results/Discussion draft, every number traced to the output
   table (reproducibility audit). Surfaced in the findings/report UI.
4. **Project state** → the BioMate **project module** (research question, data version, key
   decisions, next steps — cross-session recovery using infra we already have).

---

## 3. Convergence with the grounded-answer evidence work (one build)

The committee review of BioMate's grounded answers prioritized exactly the Writer's audit layer:

| Committee item (grounded answers) | Evidence-Based Writer mechanism |
|---|---|
| P2 — validate emitted DB ids against the real record (the "10JT = bacterial enzyme" error) | 4-layer citation check + DB-id resolution |
| P3 — citation semantic-fit (celecoxib-derivative "real citation, wrong claim") | the semantic-fit layer |
| P4 — no uncited specific locator/number in a grounded answer | claim-audit / preservation rules |
| P6/P7 — attribution+denominator, corroboration weighting | preservation + claim-strength guards |

→ **Build the enforcement engine once** (citation/ID verification + claim-audit over
`federated_query`), use it as the Writer's `audit` mode AND as the grounded-answer post-synthesis
gate. The **held-out facet eval** (`backend/lib/galaxy/ai/evals/`) already built is the shared
generalization measure.

---

## 4. Phased plan

**Phase 1 — `evidence-based-writer` skill (rewrite-safe, groups immediately).** Author the skill
(own words) with the discipline + section moves + audit protocol; `domains: [clinical,
drug_discovery, pharmacology]`; verify it detects + groups with the clinical skills. No external
content.

**Phase 2 — Enforcement engine (shared with grounded answers).** Build citation/ID verification +
claim-audit over `federated_query` (resolve id, check metadata, retrieve abstract, score semantic
fit; validate DB-ids against records). Wire as the Writer's audit mode AND the grounded-answer gate.
Measure on the held-out facet eval (no regression to the honesty/abstention controls).

**Phase 3 — Results→draft loop.** Run outputs + confirmed analysis spec → Results/Discussion draft
with per-number traceback. Findings/report UI surface.

**Phase 4 — Reviewer-response + reporting-guideline coverage** in the manuscript/IND pipeline;
project-passport fields on the project module.

**Phase 5 — Validation.** Clinical-writing eval in the benchmark harness (claim-label accuracy,
no-fabrication, preservation), extending the facet eval.

Each phase is independently shippable; Phase 1–2 give immediate value to clinical users and
directly strengthen the grounded-answer path.

---

## 5. Naming, license, privacy (gating rules)

- **No external product name** anywhere in BioMate (code, UI, skills, docs beyond this one
  provenance note). The capability is **Evidence-Based Writer** / skill `evidence-based-writer`.
- **Rewrite-only** — own words; do not copy the reference skill's reference Markdown, prompts,
  templates, or evals (its license bars including a substantial portion in another product).
  Standards it encodes (reporting guidelines, claim taxonomy) are reimplemented; official checklists
  linked, not reproduced. Carry Apache-2.0 attribution if we lean on any writing-move/phrasebank
  *concepts* traceable to the open Nature-Skills project.
- **Privacy / PHI:** no identifiable patient data to unapproved services; identifier scan ≠
  de-identification; no invented ethics/registration/authorship. Honor BioMate rules — **no hospital
  name in code/UI**; no S3 URIs in user text; private/approved env for patient data.
- **Scope honesty:** no publication/approval guarantee; not a substitute for supervisor /
  statistician / ethics / peer review.

---

## 6. Recommendation

Build **Phase 1 (`evidence-based-writer` skill, grouped via domains) + Phase 2 (the shared
enforcement engine)** now. Phase 2 is the same citation/ID-verification + claim-audit the grounded-
answer committee prioritized, so it pays off twice (the Writer's audit mode *and* the grounded-
answer quality gate), measured on the held-out facet eval already in place. This delivers the
analysis→manuscript loop for the clinical users, keeps naming/licensing clean, and groups the new
capability with the existing clinical/evidence skills.
