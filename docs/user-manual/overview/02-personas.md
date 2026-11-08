# Who BioMate is for — find your door

> One-line promise: after this page you know the shortest path from your role to the chapters you need.

<!-- Orientation page; every path links to already-verified chapters. -->

BioMate serves several kinds of user from the same conversation. Find yourself below and follow the
path — each step links to the chapter that shows you how.

## The wet-lab PI / bench scientist (little or no computing)
You have data (or an accession) and a question; you want an answer, not a pipeline.
- Start at the [cold start](../modules/I01-getting-started-cold-start.md) — describe your goal in plain words.
- Ask a question → an [Instant cited answer](../modules/I03-search-and-evidence.md).
- Have data → attach it in the [composer](../modules/I02-composer-talking-to-biomate.md); BioMate checks
  its [quality at ingest](../modules/I05-files-and-dataset-object.md) before anything runs.
- Run a validated pipeline → [running an analysis](../modules/I06-running-an-analysis.md); read the
  result in the [after-run report](../modules/I09-reports-and-reproducibility.md).
- Your domain chapter (e.g. [transcriptomics](../domains/transcriptomics.md),
  [single-cell](../domains/single-cell.md)) is written for you — use-case-first, interpretation over statistics.

## The bioinformatician / computational scientist
You want control, provenance, and reproducibility.
- Tune parameters and read the [full step view](../modules/I07-full-step-view-provenance.md)
  (params-by-origin, rendered⇄raw).
- Trust the [reproducibility record](../modules/I09-reports-and-reproducibility.md) — SHA-256 checksums,
  software, citations, versioned methods.
- Treat [datasets, runs, outputs as objects](01-object-model.md); reference them across the work.
- Train/adapt a [model](../modules/I10-models.md); design candidates in [design & generate](../modules/I11-design-and-generate.md).

## The drug-discovery / regulatory scientist
You're heading toward a submission.
- The flagship path: [Drug discovery → IND](../domains/drug-discovery-ind.md) — ADMET → auto-loop → PBPK
  → IND §2.6, with a [21 CFR 11 audit trail](../domains/cro-regulatory.md).
- [Pharmacology & clinical](../domains/pharmacology-clinical.md) for PopPK/BOIN/PGx.
- Know the honest scope before you rely on it: [Appendix E](../appendix/E-coverage-and-roadmap.md).

## The core-facility / lab admin
You run BioMate for many users.
- [Projects, roles & collaboration](../modules/I04-projects-instructions-collaboration.md) — owner/editor/viewer,
  standing instructions vs human-only notes, plans.
- [Connectors & skills](../modules/I12-connectors-and-skills.md) and
  [billing & the two-lane cost model](../modules/I13-billing-quotas-two-lane-cost.md).
- What data BioMate can reach: [databases & retrieval](../data/II01-workflow-catalog-and-routing.md) and
  the [accession resolver](../data/II02-public-datasets-accession-resolver.md).

> **Tip.** Whatever your role, the entry is the same: describe the goal. The router decides Instant vs
> Cloud and the domain — you don't need to know workflow names.
