# Citation Audit — 2026-05-28

Scope: `backend/config/qc_evidence.yaml` (57 gates × paper_ref/paper_doi pairs) plus four manuscript reference lists:
flagship, autoloop_benchmark, cryo_em_benchmark, cryoensemble.

Tooling: `research_repos/scripts/verify_citations.py` (Crossref REST API on every DOI; YEAR regex bug fixed in this audit). Raw data: `research_repos/scripts/citation_audit_20260528.csv`.

## Totals

| Status | Count |
|---|---|
| verified (Crossref hit, author + year match) | 69 |
| non_doi_skip (FDA/ICH/ISO/EMA gov URLs, ISO standards, GitHub) | 16 |
| no_doi (textbook / community practice / unnumbered) | 17 |
| not_found (DOI does not resolve in Crossref) | 5 |
| author_mismatch (Crossref first author differs from ref) | 5 |
| year_mismatch (Crossref publication year differs) | 4 |
| **Total citations audited** | **116** |

Two previously caught fabrications (Aronov 2008 → Redfern 2003; Avilov 2023 → Taylor 2023) had already been corrected in the YAML and manuscripts before this audit and re-verify as correct.

## Per-failure investigation

Each flagged row was triaged via WebFetch (doi.org) and/or WebSearch.

### Confirmed additional fabrications / wrong citations

1. **qc_evidence.yaml — Schilter B et al. *Regul Toxicol Pharmacol* 2013; 67(1):39-52** (DOI 10.1016/j.yrtph.2013.05.001)
   - DOI is real, but the actual paper is by **Sutter A, Amberg A, Boyer S, et al.** ("Use of in silico systems and expert knowledge for structure-based assessment of potentially mutagenic impurities", RTP 2013).
   - Schilter is not on the authorship. **Proposed fix:** `Sutter A et al. Regul Toxicol Pharmacol 2013; 67(1):39-52`.

2. **qc_evidence.yaml — Overgaard RV et al. *Clin Pharmacokinet* 2019; 58:781-791** (DOI 10.1007/s40262-018-0728-4)
   - DOI resolves to **Granhall C et al.** "Safety and Pharmacokinetics of Oral Semaglutide", Clin Pharmacokinet 2019.
   - A real Overgaard 2019 semaglutide pop-PK paper exists but is in **Diabetes Therapy** 10:649-662 (DOI 10.1007/s13300-019-0581-y). The qc_evidence pairing (author + DOI) is fabricated.
   - **Proposed fix:** either keep Overgaard and replace DOI with 10.1007/s13300-019-0581-y, or relabel as Granhall et al. and keep the existing DOI.

3. **qc_evidence.yaml — Yamamoto et al. *Int J Pharm* 2019; 569:118547** (DOI 10.1016/j.ijpharm.2019.118547)
   - DOI resolves to **Calcutt JJ, Anissimov YG** "Physiologically based mathematical modelling of solute transport within the epidermis and dermis" — not Yamamoto, not liposome work.
   - **Proposed fix:** verify which Yamamoto LNP/liposome paper was intended; current pairing is fabricated. Citation appears twice in YAML (LNP DLS gate context).

4. **qc_evidence.yaml — Sormanni P, Aprile FA, Vendruscolo M. *PNAS* 2017; 114:E3367-E3375 (CamSol)** (DOI 10.1073/pnas.1422401112)
   - DOI is real but resolves to Sormanni et al. **2015** *PNAS* "Rational design of antibodies targeting specific epitopes within intrinsically disordered proteins" — not the claimed CamSol-2017 record.
   - The 2017 CamSol-relevant Sormanni paper actually appeared in *Sci Rep* 7:8200 (mAb library solubility screen).
   - **Proposed fix:** replace with the 2015 *PNAS* DOI and update year, or with Sci Rep 2017 (DOI 10.1038/s41598-017-07800-w) if CamSol-screening is the intended evidence.

5. **qc_evidence.yaml — Mehrotra DV et al. *Pharm Stat* 2011; 10:357-369** (DOI 10.1002/pst.473)
   - DOI resolves to a "Literature Review July–September 2010" editorial in *Pharm Stat*, not a Mehrotra paper. The actual biomarker-enrichment paper at that volume/range is **Jenkins M, Stone A, Jennison C. 2011 Pharm Stat 10:347-356** (note pages 347-356, not 357-369).
   - **Proposed fix:** replace with Jenkins/Stone/Jennison 2011 (DOI 10.1002/pst.472).

6. **qc_evidence.yaml — Savic RM & Karlsson MO. *Clin Pharmacokinet* 2009; 48(7):415-426** (DOI 10.2165/00003088-200948070-00001)
   - DOI does not resolve. The real Savic/Karlsson transit-compartment paper is **J Pharmacokinet Pharmacodyn 2007; 34(5):711-726** (DOI 10.1007/s10928-007-9066-0). No 2009 Clin Pharmacokinet 48(7):415-426 Savic paper exists.
   - **Proposed fix:** replace with the 2007 J Pharmacokinet Pharmacodyn citation.

7. **autoloop manuscript — Ref [5] Lammert C, Bjornsson E, Niklasson A, Chalasani N. *Toxicol Sci* 2010. DOI 10.1093/toxsci/kfq059**
   - Journal and DOI fabricated. The genuine Lammert/Bjornsson/Niklasson/Chalasani 2010 DILI paper is in ***Hepatology* 51:615-620, DOI 10.1002/hep.23317**. The toxsci DOI resolves to an unrelated PBDE/OATP study.
   - The qc_evidence.yaml row for the same gate already cites the correct Hepatology paper. The manuscript should be aligned.

8. **cryo_em manuscript — Ref [18] Klaholz BP. *Prog Biophys Mol Biol* 2019; DOI 10.1016/j.pbiomolbio.2019.05.005**
   - DOI resolves to "Biophysics and the nonlinear dynamics instigated by a special hormone" (2020) — unrelated to cryo-EM and not by Klaholz. No Klaholz 2019 PBMB cryo-EM data-quality paper located.
   - **Proposed fix:** drop or replace with the genuine cryo-EM-validation reference the authors intended (e.g., Lawson et al. EMDataResource challenge papers, or Klaholz's 2017 *Curr Opin Struct Biol*).

9. **cryo_em manuscript — Ref [10] Glaeser RM. "Preparing better samples for cryo-electron microscopy". *J Struct Biol* 2021; DOI 10.1016/j.jsb.2021.107788**
   - DOI does not resolve. The real paper is in **Annual Review of Biochemistry 2021; 90:451-474, DOI 10.1146/annurev-biochem-072020-020231** — journal name and DOI both fabricated; the article itself is genuine.
   - **Proposed fix:** correct journal + DOI.

### Likely typos (citation is real, identifier wrong)

10. **qc_evidence.yaml — Tunyasuvunakool K et al. *Nature* 2021; 596:590-596** — listed DOI `10.1038/s41586-021-03828-w`; correct DOI is `10.1038/s41586-021-03828-1` (final character typo). Paper is real.

11. **cryo_em manuscript — Ref [4] Stabrin M et al. TranSPHIRE *Nat Commun* 2020** — listed DOI `10.1038/s41467-020-19513-0`; correct DOI is `10.1038/s41467-020-19513-2`. Paper is real.

12. **cryo_em / cryoensemble manuscripts — Liu YT et al. *Nat Methods* 2024** (DOI 10.1038/s41592-024-02505-1) — Crossref lists the published year as **2025**, not 2024. Paper is real; year needs correction once final pagination is known.

### False positives (no action)

- **Le Guilloux V, Schmidtke P, Tuffery P. Fpocket. BMC Bioinformatics 2009; 10:168** — script flagged "Le" vs "Le Guilloux" surname; citation is fully correct.
- **CryoBench (cryoensemble ref [5], arXiv DOI 10.48550/arXiv.2408.05526)** — arXiv DOIs are not indexed in Crossref; preprint is real.
- All `year_mismatch` rows from the initial CSV that previously appeared (Davies 1993, Lipinski 1997, Jumper 2021, etc.) were caused by a regex bug (`YEAR_RE` returning the captured prefix `19`/`20` instead of the full year) and re-verify cleanly under the patched script.

## Verdict

**9 additional citation defects detected beyond the two already caught (Aronov, Avilov).** Six are clear fabrications where the author–DOI pairing is invalid (Schilter, Overgaard, Yamamoto, Sormanni PNAS-2017, Mehrotra Pharm Stat, Lammert Toxicol Sci), two are fabricated journal+DOI for otherwise-real work (Klaholz 2019, Glaeser 2021), and one (Savic & Karlsson 2009 Clin Pharmacokinet) is a fully invented citation for which a real underlying paper exists in a different journal/year. Three additional typos (Tunyasuvunakool, Stabrin, Liu YT year) should be corrected before bioRxiv submission but are not fabrications.

**Recommendation: hold submission until at minimum items 1–9 above are corrected.**

Source artifacts:
- Script: `research_repos/scripts/verify_citations.py`
- Raw CSV: `research_repos/scripts/citation_audit_20260528.csv`
