# K4 patent mining: pre-registration (written 2026-10-29, before any extraction)

Scope: knowledge extraction from publicly available patent documents (SAR, example compounds with sequences/structures and activity values, assay conditions, ADME/permeability data, design rationale). Not freedom-to-operate or claim-scope analysis. Unpublished/internal material is out of scope. All patent-derived content carries provenance tier `P`, kept separate from peer-reviewed tiers T1/T2.

## 1. Route inventory (tested 2026-10-29 from the coordinator machine with HEAD/GET; further tests on EC2 in probe.py)
| route | status | use |
|---|---|---|
| SureChEMBL bulk parquet, snapshot 2026-05-15 (`compounds`, `patent_compound_map`, `patents`, `biomedical_*`, fingerprints) at ftp.ebi.ac.uk | reachable (directory listing OK; sizes 3.9 / 4.6 / 5.5 GB) | candidate selection: which patents contain macrocyclic-peptide compounds |
| BindingDB patent subset `BindingDB_Patents_202610_tsv.zip` | reachable (HTTP 200) | curated SAR from US patents: overlap/novelty baseline, plus structured SAR |
| Google Patents `/patent/<number>/en` pages | reachable; robots.txt allows `/patent/`; fixed 2.5 s delay, identifying user agent, <= 250 pages | full text (claims, description), CPC, dates, assignee for the pilot corpus |
| PatentsView bulk tables (old S3 and data.patentsview.org paths) | NOT reachable (403/connection failure); site redirects to the USPTO Open Data Portal | not used (portal access needs registration) |
| USPTO bulk data (bulkdata.uspto.gov) | NOT reachable; data.uspto.gov reachable but JavaScript-driven | not used |
| EPO Espacenet / OPS, WIPO PATENTSCOPE | 403 from automated access | not used |
| Lens.org | page reachable; API needs a token | not used |
| BigQuery public patents | needs a billed cloud project | not used |
| ChEMBL web API (`document` with patent type) | HEAD returned 405; GET untested | optional cross-check only |
CPC codes: VERIFIED against the USPTO CPC scheme page for C07K 7/50, 7/52, 7/54, 7/56, 7/58, 7/60, 7/62, 7/64, 7/645, 7/66 (cyclic peptides). A61K 38/12 could NOT be verified from the page opened (truncated): used only as a query hint, never as a verified filter. Macrocycle heterocycle classes are not used.

## 2. Pilot corpus selection (frozen)
1. From SureChEMBL: compounds with MW in [500, 2600] whose RDKit ring system contains a ring of >= 12 atoms and >= 3 amide bonds in or attached to the ring (peptide macrocycle filter), mapped to patents through `patent_compound_map`. Patents with publication year >= 2000.
2. Rank patents by the number of distinct such compounds; PILOT = 120 highest-ranked + 80 drawn at random (seed 20261031) from the next 2,000 ranked patents (to limit selection bias). 200 patents total.
3. Retrieve each patent page from Google Patents (`/patent/<number>/en`); patents whose page lacks a description are dropped and reported. A manifest records number, family if available, dates, assignee, CPC, text sha256, and the SureChEMBL compound count.
4. Report: share of the pilot patents carrying a verified cyclic-peptide CPC code (C07K 7/50-7/66) to describe the selection.

## 3. Extraction (frozen)
Open-weight model `Qwen/Qwen3-8B` via vLLM on a spot GPU (no paid external APIs), temperature 0, passage-level prompts over text passages that match example/table/SAR patterns (Example, Table, IC50/EC50/Kd/Ki, nM/uM, permeability, N-methyl, D-amino acid, ring size, residue notation). Item kinds: `example_compound` (identifier, sequence or HELM or SMILES string copied verbatim, assay, value, unit), `sar_statement`, `adme_permeability`, `binding_mode`, `design_rationale`. Every item has a verbatim quote of 6-40 words.

## 4. Deterministic verification (a failing item is discarded, never repaired)
(a) quote found by exact whitespace-normalised substring match in the retrieved patent text; (b) every numeric value and unit given as a field occurs in the quote or the passage; (c) a structure string (SMILES/sequence/HELM) occurs verbatim in the quote or passage; SMILES must parse in RDKit; sequences are mapped to canonical SMILES by the pipeline's converter and failures are flagged, not hidden; (d) patent number, passage offset, kind code and publication date must be present. Quote-match rate is 100% by construction for kept items; the rejected fraction by reason is reported.

## 5. Measurements and acceptance (fixed now)
- counts: patents retrieved, passages processed, items extracted/verified/rejected by reason, structure parse success rate, items by kind and by target class;
- precision: author-audit of a stratified random sample of >= 50 kept items (seed 20261031, >= 8 per kind where available): an item is correct if the quote supports the extracted statement/values/structure. The audit is NOT independent (done by the extracting workstream); the sample file is provided so the coordinator can redraw and audit independently. **Acceptance for recommending scale-up: audit precision >= 0.80 with the Wilson interval reported, structure parse success >= 0.60 among example compounds with a structure string, and >= 20 patents contributing verified example compounds.** Below these, the doc reports the pilot as not ready for scale-up;
- overlap and novelty: kept example compounds (stereo-aware InChIKey) vs BindingDB patents TSV, CycPeptMPDB (two patent-derived entries), and SureChEMBL membership of the same patent; report the share not present in BindingDB;
- cost: instance-hours and spot price from instance ids and times (cost log), cost per patent, and a full-scale estimate (patents/hour on the pilot GPU x 5,000 patents).
- caps: pilot cap USD 3 total; scale-up only with the coordinator's go-ahead.

## 6. Limits stated in advance
PDF/table layout loss in HTML text; chemical-name-to-structure mapping fails for IUPAC names (not attempted); claims vs examples differ in reliability (examples with measured data are tagged `example`, claim text `claim`); US-centric and English-centric selection through SureChEMBL/Google Patents; the model may miss multi-page tables; selection by macrocyclic-peptide compound density favours patents with large compound libraries.
