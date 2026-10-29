# Progress notes: knowledge-base paper (not part of the manuscript)

Manuscripts: `docs/20261031_MANUSCRIPT_KNOWLEDGE_BASE_DRAFT.md` (standalone) and `docs/20261031_MANUSCRIPT_KB_SECTION_FOR_METHOD_PAPER.md` (section for the method paper). Both are kept free of project-management text. This file holds what was removed from them. Last updated 2026-10-29.

## 1. Workstream legend (removed from the manuscripts)
K = hand-verified gold set and campaign ledger (`allatom_paper/knowledge/`); K2 = imports of existing collections and scaled literature extraction (`knowledge_scale/`); K3 = structure knowledge (`structure_knowledge/`); K4 = patent mining (`patent_mining/`); I-B = retrieval package and group-A re-mining (`retrieval/`, `rules_mining/`); E = evaluation track and source-group definitions (`track_e/`).

## 2. Unfilled values in the standalone manuscript (registry)
Each cell shown as "—" in the manuscript, the file that fills it, and the owner.

| Manuscript location | Value | Filling result file | Workstream |
|---|---|---|---|
| 5.3 table | patents retrieved; passages processed; items extracted / verified / rejected; structure parse success; audit precision with Wilson interval; patents contributing verified example compounds; share of kept example compounds not in the BindingDB patent subset | `docs/20261031_ALLATOM_PATENT_KNOWLEDGE.md` (pre-registration `docs/20261031_ALLATOM_PATENT_PREREG.md` is committed) | K4 |
| 5.3 text | tier-P weighting rule (the manuscript states retrieval-context use only) | same | K4 |
| 5.5 table | complexes by cyclisation type; agreement of re-detected cyclisation with the manifest label; target cards completed / flagged "no structure available"; bound-conformation priors exported; leave-one-target-out stability | `docs/20261031_ALLATOM_STRUCTURE_KNOWLEDGE.md` | K3 |
| 5.6 | fraction of records joinable across structure, property, conformation, complex and outcome | integration note to be written after the four sources land | K, K2, K3, K4 |
| 6.3 table | raw-output quote-match rate; surviving rules; precision on the judged sample of 100; recall against the gold set; proxy entailment rate; planted-quote, altered-quote and shuffled-source controls; determinism | `docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md` | K2 |
| 6.4 | coverage of the property by substructure matrix for the scaled layer; target by structure-feature matrix (16 x 5); lesson-type counts for the scaled ledger | `docs/20261031_ALLATOM_KNOWLEDGE_SCALE.md`, `docs/20261031_ALLATOM_STRUCTURE_KNOWLEDGE.md` | K2, K3 |
| 7.2 / 8 | effect of the priors on generation (hard rules only vs literature priors vs data-descriptive ablation) | results of the method manuscript (`docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md` results sections) | method manuscript |

## 3. Open items
- Per-resource parse-rate table for the imports (acceptance: at least 95% of rows parsed per resource); CyclicPepedia metadata join to structures; SweMacrocycleDB assay normalisation onto log Papp with an assay flag and a cross-source check on the 154 structures shared with CycPeptMPDB; Macrocycle-DB PDB-table filter to peptidic ring systems. Source: `docs/20261031_ALLATOM_KNOWLEDGE_IMPORTS.md`, section 5. Explanation of the SweMacrocycleDB and Macrocycle-DB count differences is not available.
- Gold set: weight tuning on group A has not been run; target pharmacophore rules (RGD / alphavbeta6, PD-L1 macrocycle series, GRPR / bombesin), encyclopaedic and database facts (no T3 entries), display-campaign hit rates and per-drug properties of approved cyclic peptides were not collected. Fourteen entries were noted in the K report as review statements whose primary sources were not re-opened (the K report's tier counts give 31 T2 entries; reconcile the two statements). A person has not judged statement-to-quote fidelity for the gold set.
- Scaled extraction: the first stage (150 to 300 papers, cap USD 3) is pre-registered with thresholds (raw quote-match at least 40%, judged precision at least 0.80 on 100 rules, 60% projected coverage); the full run (2,000 to 5,000 papers) needs a go-ahead with a measured cost. The audit sample is drawn by the coordinator (seed 20261031).
- Patent stage: pilot cap USD 3; the first audit is by the extracting workstream and is not independent, so the sample file must be redrawn and judged independently; scale-up needs a go-ahead.
- Test of the hypothesis that existing collections cover only part of the patent literature depends on the K4 overlap measurement; the manuscript states only that the degree of coverage was not established by the survey.
- The manuscripts are 7,278 words (standalone; target 5,000 to 7,000) and 1,659 words (method section; target 900 to 1,300). Trimming is open.
- "We release ..." in the introduction states an intention; whether and where anything is made public is the owner's decision.

## 4. Decisions recorded
- Two headline contributions (owner): (1) the integrated, provenance-linked knowledge layer; (2) the construction pipeline with deterministic exact-quote verification, including the separate patent tier. Imports, gold set, structure layer, leak guards and loaders are parts of these two.
- No priority claims ("first"); the qualifier "subject to a deeper literature check" was removed from the contributions; factual coverage limits stay in Limitations.
- Licences are not discussed in the manuscripts (owner).
- Patent work is knowledge extraction only; no freedom-to-operate analysis.
- Soft-rule weights come from the literature; our own labels check direction and do not set weights (group-A re-mining gave no validated rule because the criteria need at least three sources and the train group has two).
- Train, stop and held-out groups: `track_e/source_groups_v2.json` (membership sha256 `be8a9945f5042b97afa177d85c23f80b9343c933722c54f02188bd75b276db1c`); the earlier 7/7/6-source split is kept for a robustness arm.

## 5. Corrections applied to earlier text (history)
- The statement that the live CycPeptMPDB database "has been updated since the paper" was withdrawn: the live file has 8,466 rows and the same 7,988 unique structures as the local table (repeated measurements explain the row difference).
- The earlier gold-set description (48 entries from 19 papers; 38 T1, 10 T2; 21 weight-eligible) is superseded by the 107-entry set (`knowledge_kb_v1.json`, sha256 `b6c8988545bc1ae9dcda73521a03a2ec5bd735504bfca7d300a6e1f9261d42b7`). The earlier description of the 14 unit tests is superseded by 17.
- Commits of the manuscript files: 9a91d1634 (first draft), 5f1dcedd0 (K2 import corrections), d9300419b (two-contribution framing); this revision follows the owner's instruction to remove project-management content and the K report of the 107-entry set (commit 21680221b).
- The K report (`docs/20261031_ALLATOM_KNOWLEDGE_LAYER.md`) states spend of about USD 0.05 for nine small spot instances; K2's import run was a single CPU spot instance of about four minutes (no cost stated); these figures do not appear in the manuscripts.
- Items I did not verify myself: the primary sources behind the literature entries (read from the committed survey and K files), the per-feature correlations in 6.1 (read from the committed K report and checked against `direction_check_results.json` for the N-methyl count in Townsend), and the K4 pre-registration details (read from the committed pre-registration).
