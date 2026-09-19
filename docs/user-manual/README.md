# BioMate User Manual — Book Source (index)

This directory is the **source of truth** for the BioMate user manual (see the plan in
`docs/20260919_USER_MANUAL_BOOK_PLAN.md`). It is written as a structured, indexed book, verified
against the live system (dev) before anything is marked "supported" — see `coverage-ledger.md`.

- Content lives here as markdown + a page-model; Claude design polishes it into the in-app `/manual`
  (doc-page style, per `reference/claude_design/data_centroid_design_v2/spec`).
- **Honesty rule:** nothing is documented as supported unless it is green in `coverage-ledger.md`.
  Unverified / coverage-gapped items go in Appendix E (roadmap), never sold as present.
- Every domain/module page follows `_CHAPTER_TEMPLATE.md`.

## Index (table of contents)

### Part 0 — Overview & orientation
- [~] `overview/00-what-is-biomate.md`
- [ ] `overview/01-object-model.md`
- [ ] `overview/02-personas.md`
- [ ] `overview/03-first-analysis-5min.md`

### Part I — General function modules
- [~] `modules/I01-getting-started-cold-start.md`   (design v2 §00)
- [~] `modules/I02-composer-talking-to-biomate.md`   (§06)
- [~] `modules/I03-search-and-evidence.md`           (§01, §09)
- [~] `modules/I04-projects-instructions-collaboration.md` (§00 ProjectSetup)
- [~] `modules/I05-files-and-dataset-object.md`      (§04)
- [~] `modules/I06-running-an-analysis.md`           (§07)
- [~] `modules/I07-full-step-view-provenance.md`     (§08)
- [~] `modules/I08-outputs-viewers-interactive.md`   (§14)
- [~] `modules/I09-reports-and-reproducibility.md`   (§12)
- [~] `modules/I10-models.md`                        (§03, §10)
- [~] `modules/I11-design-and-generate.md`           (§05, §11)
- [~] `modules/I12-connectors-and-skills.md`
- [~] `modules/I13-billing-quotas-two-lane-cost.md`

### Part II — Databases & retrieval supports
- [ ] `data/II01-workflow-catalog-and-routing.md`
- [ ] `data/II02-public-datasets-accession-resolver.md`
- [ ] `data/II03-literature-and-evidence-retrieval.md`
- [ ] `data/II04-reference-data-and-indexes.md`
- [ ] `data/II05-memory-and-project-knowledge.md`

### Part III — Function areas by domain
- [~] `domains/drug-discovery-ind.md`   ← **flagship, D1 (drafted + code-verified)**
- [~] `domains/transcriptomics.md`
- [ ] `domains/cryo-em.md`
- [ ] `domains/single-cell.md`
- [ ] `domains/variant-calling.md`
- [ ] `domains/structural-biology.md`
- [ ] `domains/pharmacology-clinical.md`
- [ ] `domains/multi-omics.md`
- [ ] `domains/epigenomics.md`      (P2)
- [ ] `domains/proteomics.md`       (P2)
- [ ] `domains/metabolomics.md`     (P2)
- [ ] `domains/metagenomics.md`     (P2)
- [ ] `domains/cro-regulatory.md`   (cross-domain)

### Appendices
- [ ] `appendix/A-glossary.md`
- [ ] `appendix/B-file-formats.md`
- [ ] `appendix/C-qc-gate-reference.md`
- [ ] `appendix/D-troubleshooting-routing.md`
- [ ] `appendix/E-coverage-and-roadmap.md`   (honest "not yet supported")
- [ ] `appendix/F-api-cli-quickref.md`

(`[ ]` = not started · `[~]` = drafted, verifying · `[x]` = verified + polished)
