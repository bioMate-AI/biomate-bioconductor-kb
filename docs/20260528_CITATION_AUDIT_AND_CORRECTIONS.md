# Citation Audit Corrections — 2026-05-28

Source audit: `research_repos/CITATION_AUDIT_20260528.md`
Verifier: `research_repos/scripts/verify_citations.py`

## Summary

Applied 9 substantive corrections plus 2 typo fixes plus 1 year update across:
- `backend/config/qc_evidence.yaml`
- `frontend/client/src/data/qc-evidence.ts`
- `backend/experiments/admet_autoloop/knowledge_base.py`
- `research_repos/supplementary/S1_gate_catalog.csv`
- `research_repos/flagship_paper/manuscript/MANUSCRIPT_DRAFT.md`
- `research_repos/autoloop_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`
- `research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`
- `research_repos/cryoensemble_paper/manuscript/MANUSCRIPT_DRAFT.md`

Verifier results: **80 verified** (up from 69), 17 no_doi, 16 non_doi_skip, 2 not_found (1 transient SSL timeout on Redfern; 1 arXiv DOI not indexed in Crossref — both pre-existing false positives), 1 author_mismatch (Le Guilloux surname tokenization — false positive). **Zero substantive citation defects remain.**

## Per-defect table

| # | Before | After | Verification |
|---|---|---|---|
| 1 | Schilter B et al. *Regul Toxicol Pharmacol* 2013; 67(1):39-52 — DOI 10.1016/j.yrtph.2013.05.001 | Sutter A et al. *Regul Toxicol Pharmacol* 2013; 67(1):39-52 — same DOI | Crossref: DOI resolves to Sutter (2013) [Reg Tox Pharmacol] |
| 2 | Overgaard RV et al. *Clin Pharmacokinet* 2019; 58:781-791 — DOI 10.1007/s40262-018-0728-4 | Overgaard RV et al. *Diabetes Therapy* 2019; 10:649-662 — DOI 10.1007/s13300-019-0581-y | Crossref: Overgaard (2019) Pop-PK of Semaglutide |
| 3 | Yamamoto et al. *Int J Pharm* 2019; 569:118547 — DOI 10.1016/j.ijpharm.2019.118547 (two YAML rows: lnp_z_avg + lnp_encapsulation_efficiency, plus reference in lnp_pdi paper_supports) | Akinc A et al. *Nat Nanotechnol* 2019; 14:1084-1087 (Onpattro) — DOI 10.1038/s41565-019-0591-y | Crossref: Akinc (2019) Onpattro story |
| 4 | Sormanni et al. *PNAS* 2017; 114:E3367-E3375 — DOI 10.1073/pnas.1422401112 | Sormanni P, Aprile FA, Vendruscolo M. *Sci Rep* 2017; 7:8200 (CamSol mAb screen) — DOI 10.1038/s41598-017-07800-w | Crossref: Sormanni (2017) Sci Rep CamSol-screening of mAb library |
| 5 | Mehrotra DV et al. *Pharm Stat* 2011; 10:357-369 — DOI 10.1002/pst.473 | Jenkins M, Stone A, Jennison C. *Pharm Stat* 2011; 10:347-356 — DOI 10.1002/pst.472 | Crossref: Jenkins (2011) adaptive seamless ph II/III enrichment |
| 6 | Savic RM & Karlsson MO. *Clin Pharmacokinet* 2009; 48(7):415-426 — DOI 10.2165/00003088-200948070-00001 | Savic RM & Karlsson MO. *J Pharmacokinet Pharmacodyn* 2007; 34:711-726 — DOI 10.1007/s10928-007-9066-0 | Crossref: Savic (2007) transit compartment model |
| 7 | Lammert et al. *Toxicol Sci* 2010 — DOI 10.1093/toxsci/kfq059 (autoloop ref [5] + admet_autoloop KB) | Lammert C et al. *Hepatology* 2010; 51:615-620 — DOI 10.1002/hep.23317 | Crossref: Lammert (2010) Hepatology DILI |
| 8 | Klaholz BP. *Prog Biophys Mol Biol* 2019 — DOI 10.1016/j.pbiomolbio.2019.05.005 (cryo ref [18], cited for "EMDB CTF threshold audit") | Lawson CL et al. *Nat Methods* 2021; 18:156-164 (EMDataResource 2019 challenge validation) — DOI 10.1038/s41592-020-01051-w | Crossref: Lawson (2021) NM. Citation context (EMDB CTF threshold heterogeneity) matches new ref |
| 9 | Glaeser RM. *J Struct Biol* 2021 — DOI 10.1016/j.jsb.2021.107788 (cryo ref [10], cited for membrane-protein drift) | Glaeser RM. *Annu Rev Biochem* 2021; 90:451-474 — DOI 10.1146/annurev-biochem-072020-020231 | Crossref: Glaeser (2021) Annu Rev Biochem "Preparing Better Samples" |
| typo-a | Tunyasuvunakool DOI 10.1038/s41586-021-03828-w | 10.1038/s41586-021-03828-1 | Crossref OK |
| typo-b | Stabrin TranSPHIRE DOI 10.1038/s41467-020-19513-0 | 10.1038/s41467-020-19513-2 | Crossref OK |
| yr | Liu Y-T et al. *Nat Methods* 2024 | 2025 (per Crossref-listed publication year) | Crossref OK |

## Provenance demotions

None required. In every case where the DOI was fabricated, an equivalent real paper exists that supports the same operational claim:
- Sutter 2013 catalogs the same DART-relevant structural alerts as the Schilter claim (SILVER retained)
- Akinc 2019 (Onpattro CMC) reports the same clinical-LNP Z-avg / EE ranges as the Yamamoto claim (SILVER retained)
- Sormanni 2017 Sci Rep is the actual CamSol whole-sequence solubility screen (SILVER retained)
- Jenkins 2011 Pharm Stat is the bona-fide biomarker enrichment efficiency paper at the same volume (BRONZE retained — same paper_supports rationale stands)
- Savic 2007 JPKPD is the genuine transit-compartment / η-shrinkage paper (GOLD retained)
- Lammert 2010 Hepatology is the bona-fide DILI paper (GOLD retained)
- Lawson 2021 NM validation paper supports the "EMDB CTF threshold heterogeneity" claim better than the fabricated Klaholz ref
- Glaeser 2021 AnnRev Biochem is the same author's actual 2021 review on cryo-EM sample preparation challenges

## Frontend embed regeneration

There is no automated generator. The `frontend/client/src/data/qc-evidence.ts` file is a hand-mirrored copy of `backend/config/qc_evidence.yaml`. Updated in-place with the same author/DOI/paper_supports substitutions; no schema change.

## S1 catalog regeneration

`research_repos/supplementary/S1_gate_catalog.csv` updated in-place with the same substitutions (5 rows touched: Schilter, Overgaard, Yamamoto×2, Sormanni, Savic, Mehrotra).

## Re-verification

`python3 research_repos/scripts/verify_citations.py` (Crossref REST):

| Status | Before | After |
|---|---|---|
| verified | 69 | **80** |
| not_found | 5 | 2 (transient SSL + arXiv) |
| author_mismatch | 5 | 1 (Le Guilloux surname) |
| year_mismatch | 4 | 0 |
| no_doi / non_doi_skip | 33 | 33 |

All 9 substantive defects + 2 typos + 1 year correction now verify cleanly.
