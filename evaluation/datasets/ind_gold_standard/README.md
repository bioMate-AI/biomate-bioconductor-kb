# IND Gold Standard Evaluation Datasets

Curated reference compounds for evaluating BioMate §2.6.1–§2.6.3 generation accuracy.
All values sourced from peer-reviewed literature or regulatory databases.

## Datasets Used

| Dataset | Source | n_compounds | Property | §2.6 section |
|---------|--------|-------------|----------|--------------|
| Redfern 2003 | Cardiovasc Res doi:10.1016/S0008-6363(02)00846-5 | 32 | hERG IC50 + TdP risk | §2.6.3.7 |
| ICH S7B reference | FDA guidance 2005, FDA-2003-D-0524 | 6 | hERG IKr assay QC | §2.6.3.7 |
| TDC hERG | Karim 2019, CC-BY 4.0 | 655 (131 test) | hERG binary IC50<10µM | §2.6.3.7 |
| DILIrank | Chen 2016 Drug Discov Today | 1,036 | DILI severity class | §2.6.3.2 |
| TDC DILI | CC-BY 4.0 | 475 (95 test) | DILI binary | §2.6.3.2 |
| Hansen 2009 Ames | Chem Res Toxicol doi:10.1021/tx900161p | 6,512 | Ames TA98/TA100±S9 | §2.6.3.3 |
| TDC AMES | CC-BY 4.0 | 7,278 (1,456 test) | Ames binary | §2.6.3.3 |
| TDC PPBR_AZ | AstraZeneca, Wenzel 2019, CC-BY 4.0 | 1,614 (323 test) | % plasma protein bound | §2.6.2 |
| Obach 2008 | Drug Metab Dispos doi:10.1124/dmd.107.018861 | 371 | CLint→CLh measured | §2.6.2 |
| DrugBank open | CC-BY-NC 4.0 | ~2,000 | Vd, CL, t½, F% | §2.6.2 |
| OSP PBPK Qualification | GitHub MIT | 30+ | Cmax, AUC, t½ vs observed | §2.6.2 |

## Reference Compound Set (Annotated)

See `reference_compounds.yaml` for the full annotated compound list.

## Evaluation Coverage

- **TC-1 (Safety flags):** hERG, DILI, Ames — exact flag count matching
- **TC-2 (PK accuracy):** f_u, Vd, CLh — within published reference ranges
- **TC-3 (Document completeness):** All 8 §2.6 sections, DOCX, size
- **TC-4 (Narrative quality):** ICH guideline citations
- **TC-5 (Known compound accuracy):** Withdrawn drugs correctly flagged
- **TC-6 (PPBR live validation):** TDC PPBR_AZ test set, MAE vs Chemprop baseline
- **TC-7 (hERG live validation):** TDC hERG test set, AUROC vs Chemprop 0.870
- **TC-8 (Ames live validation):** TDC AMES test set, AUROC vs Chemprop baseline
