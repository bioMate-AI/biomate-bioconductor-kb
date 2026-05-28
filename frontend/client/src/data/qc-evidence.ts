/** QC gate evidence — generated from backend/config/qc_evidence.yaml. */
export interface QCEvidenceEntry { paper_ref: string; paper_doi: string;
  provenance: "GOLD" | "SILVER" | "BRONZE";
  paper_supports: string; rule_text: string; finding: string; }
export type QCEvidenceMap = Record<string, Record<string, QCEvidenceEntry[]>>;
export const QC_EVIDENCE: QCEvidenceMap = {
  "pbpk": {
    "pbpk_tmax_fraction": [
      {
        "paper_ref": "FDA Guidance for Industry — PBPK Analyses (2018)",
        "paper_doi": "https://www.fda.gov/media/101469/download",
        "provenance": "SILVER",
        "paper_supports": "The guidance recommends simulations cover sufficient time to characterise absorption, distribution, and elimination phases — i.e. Tmax should not coincide with the end of the simulation window.\n",
        "rule_text": "BioMate flags Tmax > 80% of simulation_duration_h (IND profile) or > 90% (screening profile). Exact cutoffs are BioMate operational conventions.\n",
        "finding": "Remediation when triggered: extend simulation_duration_h so Tmax falls earlier in the window.\n"
      }
    ],
    "pbpk_cl_min": [
      {
        "paper_ref": "Davies B & Morris T. Pharm Res 1993; 10(7):1093-1095",
        "paper_doi": "10.1023/A:1018943613122",
        "provenance": "BRONZE",
        "paper_supports": "Davies & Morris 1993 is a table of physiological parameters (organ weights, blood flows, GFR) across species. It does NOT state any systemic-clearance minimum.\n",
        "rule_text": "BioMate flags CL < 0.01 L/h as physiologically implausible for a clinically-significant small molecule. This cutoff is operational, not peer-reviewed.\n",
        "finding": "Pending replacement with a GOLD-anchored gate (CL ≤ Qh ≈ 87 L/h — see Davies & Morris Table 1 for cardiac output). Tracked in docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md.\n"
      }
    ],
    "pbpk_mass_balance": [
      {
        "paper_ref": "EMA Guideline EMA/CHMP/458101/2016 (2019)",
        "paper_doi": "https://www.ema.europa.eu/documents/scientific-guideline/guideline-reporting-physiologically-based-pharmacokinetic-pbpk-modelling-simulation_en.pdf",
        "provenance": "SILVER",
        "paper_supports": "The EMA PBPK guideline requires verification that the model conserves mass — sum of compartment masses plus cumulative excretion equals the administered dose.\n",
        "rule_text": "BioMate enforces |recovery − 1.0| ≤ 0.05 (IND profile) or ≤ 0.10 (screening profile). Exact tolerance cutoffs are BioMate operational; the principle of mass-balance verification is from the guideline.\n",
        "finding": "Remediation when triggered: tighten ODE solver tolerance (rtol/atol) by ~100× to reduce numerical drift.\n"
      }
    ],
    "pbpk_auc_fold_error": [
      {
        "paper_ref": "FDA Guidance for Industry — PBPK Analyses (2018)",
        "paper_doi": "https://www.fda.gov/media/101469/download",
        "provenance": "GOLD",
        "paper_supports": "The guidance states the conventional acceptance criterion for PBPK model verification is that predicted PK parameters (AUC, Cmax) fall within twofold of observed clinical values (i.e. 0.5 ≤ predicted/observed ≤ 2.0). This is the standard verification criterion in PBPK submissions.\n",
        "rule_text": "BioMate enforces |log2(AUC_pred / AUC_obs)| ≤ 1 (IND profile, 2-fold) or ≤ log2(3) (screening, 3-fold).\n",
        "finding": "Remediation: adjust tissue partition coefficients (Kp scale). Reduce when overpredicting, increase when underpredicting.\n"
      }
    ]
  },
  "admet": {
    "admet_herg_ic50": [
      {
        "paper_ref": "Redfern P et al. Cardiovasc Res 2003; 58(1):32-45",
        "paper_doi": "10.1016/S0008-6363(02)00846-5",
        "provenance": "GOLD",
        "paper_supports": "Redfern 2003 establishes the 30× safety margin between hERG IC50 and free therapeutic Cmax as the industry-accepted cardiac liability cutoff; for a typical small-molecule free Cmax of ~0.3 µM this corresponds to an IC50 ≥ 10 µM.\n",
        "rule_text": "BioMate halts if hERG IC50 ≤ 10 µM (admet_standard profile). The 10 µM operational threshold is confirmed in Bowes 2012 (Nat Rev Drug Discov 11:909-922, DOI 10.1038/nrd3845) as the cross-pharma industry consensus.\n",
        "finding": "Remediation: tighten upstream logP filter per Waring & Johnstone 2007 (Bioorg Med Chem Lett 17:1759-1764, DOI 10.1016/ j.bmcl.2006.12.061) logP/IC50 regression; or reduce MW per Aronov 2008 (Curr Opin Drug Discov Devel 11:128-140, PMID 18175275) \"Tuning out of hERG.\"\n"
      }
    ],
    "admet_dili_probability": [
      {
        "paper_ref": "Lammert C et al. Hepatology 2010; 51:615-620",
        "paper_doi": "10.1002/hep.23317",
        "provenance": "SILVER",
        "paper_supports": "Lammert 2010 establishes lipophilicity + daily-dose as the primary DILI-risk drivers; the model provides a probability score rather than a threshold.\n",
        "rule_text": "BioMate halts if DILI probability > 0.5 (operational midpoint).\n",
        "finding": "Remediation: reduce daily dose target; tighten logP filter.\n"
      }
    ],
    "admet_ames": [
      {
        "paper_ref": "Kazius J et al. J Med Chem 2005; 48:312-320",
        "paper_doi": "10.1021/jm040835a",
        "provenance": "GOLD",
        "paper_supports": "Kazius 2005 defines the structural alerts (toxicophores) used for mutagenicity prediction; a positive prediction = presence of one or more toxicophores.\n",
        "rule_text": "BioMate halts if Ames probability > 0.5 (any toxicophore alert).\n",
        "finding": "Remediation: substitute reactive groups (aniline, nitro, epoxide, etc.) per ICH M7.\n"
      }
    ],
    "admet_ro5": [
      {
        "paper_ref": "Lipinski CA et al. Adv Drug Deliv Rev 1997; 23:3-25",
        "paper_doi": "10.1016/S0169-409X(96)00423-1",
        "provenance": "GOLD",
        "paper_supports": "Lipinski's Rule of Five: MW ≤ 500, logP ≤ 5, HBD ≤ 5, HBA ≤ 10. Establishes the empirical bounds for oral bioavailability.\n",
        "rule_text": "BioMate halts on >1 Ro5 violation (admet_standard profile).\n",
        "finding": "Remediation: simplify the molecule (reduce MW or logP) before progressing to in vivo.\n"
      }
    ]
  },
  "cyp_ddi": {
    "cyp_ddi_r1_basic": [
      {
        "paper_ref": "FDA In Vitro Drug Interaction Studies Guidance (2020)",
        "paper_doi": "https://www.fda.gov/regulatory-information/search-fda-guidance-documents/vitro-drug-interaction-studies-cytochrome-p450-enzyme-and-transporter-mediated-drug-interactions",
        "provenance": "GOLD",
        "paper_supports": "FDA 2020 DDI guidance specifies R1 (basic model) cutoffs for perpetrator-mediated CYP inhibition: R1 ≥ 1.02 → investigate; R1 ≥ 1.1 → conduct clinical DDI study.\n",
        "rule_text": "BioMate halts when R1 ≥ 1.1 (cyp_ddi_standard profile); advisory when 1.02 ≤ R1 < 1.1.\n",
        "finding": "Remediation: model-based prediction of clinical DDI magnitude; consider lowering dose or substrate avoidance.\n"
      }
    ],
    "cyp_ddi_r2_mbi": [
      {
        "paper_ref": "FDA In Vitro Drug Interaction Studies Guidance (2020)",
        "paper_doi": "https://www.fda.gov/regulatory-information/search-fda-guidance-documents/vitro-drug-interaction-studies-cytochrome-p450-enzyme-and-transporter-mediated-drug-interactions",
        "provenance": "GOLD",
        "paper_supports": "FDA 2020 DDI guidance R2 (mechanism-based inhibition) cutoffs: R2 ≤ 0.79 → investigate; R2 ≤ 0.71 → conduct clinical study.\n",
        "rule_text": "BioMate halts when R2 ≤ 0.71; advisory when 0.71 < R2 ≤ 0.79.\n",
        "finding": "Remediation: characterize KI and kinact via TDI assay; time-dependent inhibition often requires substrate avoidance.\n"
      }
    ]
  },
  "nca_pk": {
    "nca_auc_extrap": [
      {
        "paper_ref": "FDA Bioavailability Studies Guidance (2003)",
        "paper_doi": "https://www.fda.gov/media/70958/download",
        "provenance": "GOLD",
        "paper_supports": "FDA 2003 BA/BE guidance: AUC extrapolation from last observed concentration to infinity should be ≤ 20% of AUC_inf for the estimate to be reliable. Higher values indicate inadequate sampling duration.\n",
        "rule_text": "BioMate halts when AUC_extrap_pct > 20% (nca_standard); regulatory profile tightens to > 15%.\n",
        "finding": "Remediation: extend last_sampling_time_h by 1.5× to capture more of the terminal elimination phase.\n"
      }
    ],
    "nca_terminal_slope_coverage": [
      {
        "paper_ref": "Gabrielsson J & Weiner D. PK/PD Data Analysis 5th ed.",
        "paper_doi": "(textbook, no DOI)",
        "provenance": "SILVER",
        "paper_supports": "Standard NCA practice requires ≥3 points in the terminal log-linear phase for lambda_z estimation; lambda_z fit without sufficient terminal coverage gives unreliable half-life estimates.\n",
        "rule_text": "BioMate halts if subjects_with_no_terminal_slope > 2 (nca_standard).\n",
        "finding": "Remediation: widen the lambda_z window; or extend sampling if terminal phase wasn't reached.\n"
      }
    ]
  },
  "docking": {
    "docking_binding_score": [
      {
        "paper_ref": "Trott O & Olson AJ. J Comput Chem 2010; 31:455-461",
        "paper_doi": "10.1002/jcc.21334",
        "provenance": "BRONZE",
        "paper_supports": "Trott & Olson 2010 introduces AutoDock Vina but does NOT prescribe a binding-score cutoff. The -7 kcal/mol \"hit\" threshold is community heuristic.\n",
        "rule_text": "BioMate flags binding_score > -7 kcal/mol (advisory) for docking_hit_finding profile.\n",
        "finding": "Remediation: increase exhaustiveness 8 → 32; expand search box; try Glide SP→XP if available.\n"
      }
    ],
    "docking_valid_poses": [
      {
        "paper_ref": "AutoDock Vina + Glide community practice",
        "paper_doi": "(none)",
        "provenance": "BRONZE",
        "paper_supports": "Standard docking workflows require ≥3 valid poses for consensus scoring; no peer-reviewed minimum is cited.\n",
        "rule_text": "BioMate flags if n_poses_generated < 3.\n",
        "finding": "Remediation: lower the energy-cutoff filter; expand the search box around the receptor.\n"
      }
    ]
  },
  "structure_prediction": {
    "struct_pred_mean_plddt": [
      {
        "paper_ref": "Jumper J et al. Nature 2021; 596:583-589",
        "paper_doi": "10.1038/s41586-021-03819-2",
        "provenance": "GOLD",
        "paper_supports": "AlphaFold supplementary materials define pLDDT bands: >90 high accuracy; 70-90 well-modelled; 50-70 low confidence; <50 often disordered.\n",
        "rule_text": "Recommended gate: mean pLDDT ≥ 70 for downstream docking use.\n",
        "finding": "Remediation: increase recycling_steps (3 → 6) or use deeper MSA (Mirdita 2022 ColabFold).\n"
      }
    ],
    "struct_pred_confident_fraction": [
      {
        "paper_ref": "Tunyasuvunakool K et al. Nature 2021; 596:590-596",
        "paper_doi": "10.1038/s41586-021-03828-w",
        "provenance": "SILVER",
        "paper_supports": "Tunyasuvunakool et al. apply AlphaFold to the human proteome and report per-residue pLDDT distributions, defining the >70 band as the \"confident\" set used for downstream structural analyses. The paper frames confident-fraction as a model-quality summary but does NOT state the exact ≥0.70 fraction cutoff used here — that is a community convention extrapolated from the paper's framework.\n",
        "rule_text": "BioMate flags structures with confident_fraction (frac residues with pLDDT > 70) below 0.70 as advisory. Cutoff is operational.\n",
        "finding": "Remediation: increase recycling iterations, supply a deeper MSA, or restrict downstream analysis to confident residues only.\n"
      }
    ],
    "struct_pred_max_pae": [
      {
        "paper_ref": "Tunyasuvunakool K et al. Nature 2021; 596:590-596",
        "paper_doi": "10.1038/s41586-021-03828-w",
        "provenance": "SILVER",
        "paper_supports": "Tunyasuvunakool et al. use predicted aligned error (PAE) to characterise inter-domain relative orientation confidence; low PAE between domains indicates the model places them reliably with respect to each other. The paper presents PAE as a continuous confidence measure but does NOT state the exact ≤8 Å cutoff used here — that is a community convention extrapolated from the paper's framework.\n",
        "rule_text": "BioMate flags multi-domain structures with max inter-domain PAE > 8 Å as advisory. Skipped for single-domain proteins where max_pae is not reported.\n",
        "finding": "Remediation: deepen MSA, increase recycling, or treat domains independently if inter-domain orientation is unreliable.\n"
      }
    ]
  },
  "hts": {
    "hts_z_prime": [
      {
        "paper_ref": "Zhang JH, Chung TD, Oldenburg KR. J Biomol Screen 1999; 4(2):67-73",
        "paper_doi": "10.1177/108705719900400206",
        "provenance": "GOLD",
        "paper_supports": "Zhang 1999 introduces the Z'-factor statistic and explicitly recommends Z' ≥ 0.5 as \"excellent\" assay quality. Z' between 0 and 0.5 = \"doable but marginal\"; Z' < 0 = \"screen will not work.\"\n",
        "rule_text": "BioMate flags plates with Z' < 0.5 (configurable via params.min_z_prime). The 0.5 cutoff is the Zhang 1999 \"excellent\" threshold verbatim.\n",
        "finding": "Remediation when triggered: investigate control well distribution, plate-edge effects, or re-run with different controls.\n"
      }
    ],
    "hts_signal_window": [
      {
        "paper_ref": "Iversen PW et al. J Biomol Screen 2006; 11(3):247-252",
        "paper_doi": "10.1177/1087057105285610",
        "provenance": "SILVER",
        "paper_supports": "Iversen 2006 establishes signal-window as a complement to Z'. Signal-window ≥ 2 is generally accepted as adequate dynamic range, though the paper presents it as a continuous quality metric, not a hard cutoff.\n",
        "rule_text": "BioMate computes signal window but does not yet enforce a hard gate. Recommended cutoff: SW ≥ 2 (Iversen 2006 convention).\n",
        "finding": "Pair with Z' for full dynamic-range assessment; SW low + Z' OK indicates separation by mean but poor variance characterization.\n"
      }
    ]
  },
  "ich_s5": {
    "ich_s5_safety_margin": [
      {
        "paper_ref": "ICH S5(R3) Guideline on detection of reproductive and developmental toxicity (2020)",
        "paper_doi": "https://database.ich.org/sites/default/files/S5-R3_Step4_Guideline_2020_0218.pdf",
        "provenance": "GOLD",
        "paper_supports": "ICH S5(R3) §3.1 specifies that for women of childbearing potential (WOCBP), the default safety margin between the highest non-effect dose in animal reproductive toxicity studies and clinical exposure should be ≥10× Cmax.\n",
        "rule_text": "BioMate flags compounds with safety margin < 10× Cmax under the WOCBP scenario (RED) or 10-30× (YELLOW).\n",
        "finding": "Remediation: dose reduction, alternative formulation to reduce Cmax, or additional reproductive tox studies.\n"
      }
    ],
    "ich_s5_structural_alert": [
      {
        "paper_ref": "Schilter B et al. Regul Toxicol Pharmacol 2013; 67(1):39-52",
        "paper_doi": "10.1016/j.yrtph.2013.05.001",
        "provenance": "SILVER",
        "paper_supports": "Schilter 2013 catalogs structural alerts for reproductive toxicity (DART) including known teratogens, endocrine disruptors, and developmental toxicants. The categorical RED/YELLOW/GREEN scheme is BioMate's adaptation.\n",
        "rule_text": "BioMate classifies alerts as RED (known teratogen), YELLOW (structural similarity to teratogens), or GREEN (no alerts). Categorical tiers, not numeric thresholds.\n",
        "finding": "Remediation: structural modification to remove flagged moieties; early DART screening (Hayess 2013 EST assay) recommended.\n"
      }
    ]
  },
  "ich_s7": {
    "ich_s7b_herg_margin": [
      {
        "paper_ref": "ICH S7B Nonclinical Evaluation of Delayed Ventricular Repolarization (2005)",
        "paper_doi": "https://database.ich.org/sites/default/files/S7B_Guideline.pdf",
        "provenance": "GOLD",
        "paper_supports": "ICH S7B requires both in vitro IKr (hERG) assay and in vivo QT/QTc assessment. Safety margin = hERG IC50 / free Cmax. A margin < 30× indicates need for further QT investigation; < 10× is high cardiac risk.\n",
        "rule_text": "BioMate flags safety margin < 10× as RED, 10-30× as YELLOW, ≥30× as GREEN.\n",
        "finding": "Remediation: structural modification to reduce hERG binding, or comprehensive in vivo QT assessment.\n"
      }
    ],
    "ich_s7b_qnet": [
      {
        "paper_ref": "Dutta S et al. Front Physiol 2017; 8:616",
        "paper_doi": "10.3389/fphys.2017.00616",
        "provenance": "GOLD",
        "paper_supports": "Dutta 2017 establishes qNET (net charge difference) as a CiPA proarrhythmia metric. qNET < -30 pC/pF indicates high proarrhythmic risk under the CiPA initiative.\n",
        "rule_text": "BioMate flags qNET < -30 pC/pF as triggering CiPA Tier 2 evaluation (in silico action potential modeling).\n",
        "finding": "Remediation: full CiPA cell-model simulation (Dutta 2017) or avoidance if multi-channel risk confirmed.\n"
      }
    ]
  },
  "clinical_trial": {
    "boin_dlt_boundary": [
      {
        "paper_ref": "Liu S, Yuan Y. J R Stat Soc C 2015; 64(3):507-523",
        "paper_doi": "10.1111/rssc.12089",
        "provenance": "GOLD",
        "paper_supports": "Liu & Yuan 2015 establishes BOIN dose-escalation boundaries λ_e and λ_d as functions of target DLT rate φ. For φ=0.25, λ_e=0.197 (escalate) and λ_d=0.298 (de-escalate). MTD = highest dose with observed DLT rate ≤ φ.\n",
        "rule_text": "BioMate enforces BOIN decision rules verbatim from Liu & Yuan 2015 Table 2. MTD selection per the paper's algorithm.\n",
        "finding": "Remediation: BOIN parameters are not auto-tunable — the algorithm is the gold standard. If MTD selection seems wrong, audit the DLT observations.\n"
      }
    ]
  },
  "allometric": {
    "allometric_r_squared": [
      {
        "paper_ref": "FDA Estimating the Maximum Safe Starting Dose in Initial Clinical Trials (2005)",
        "paper_doi": "https://www.fda.gov/media/72309/download",
        "provenance": "GOLD",
        "paper_supports": "FDA 2005 FIH dose guidance describes allometric scaling of animal pharmacokinetic parameters (CL, V) across species to predict human PK. Inter-species power-law fit with R² is the standard quality metric.\n",
        "rule_text": "BioMate flags allometric fits with R² < 0.85 as low confidence (would not be acceptable in FIH submission).\n",
        "finding": "Remediation: include additional species (typically ≥3), check for outliers (often the smallest species), or use mechanistic PBPK scaling instead.\n"
      }
    ]
  },
  "ivive": {
    "ivive_fold_error": [
      {
        "paper_ref": "Obach RS. Drug Metab Dispos 1999; 27(11):1350-1359",
        "paper_doi": "(no DOI; PMID 10534321)",
        "provenance": "GOLD",
        "paper_supports": "Obach 1999 establishes that in vitro–in vivo extrapolation (IVIVE) from hepatocyte CLint should predict in vivo CL within 2-fold for ~50% of compounds; within 3-fold for ~80%. The 2-fold criterion is the de facto acceptance threshold.\n",
        "rule_text": "BioMate flags IVIVE predictions with |predicted/observed| > 2 as failing the Obach 1999 criterion.\n",
        "finding": "Remediation: incorporate well-stirred or parallel-tube model corrections; consider protein binding and active transport.\n"
      }
    ],
    "ivive_well_stirred_consistency": [
      {
        "paper_ref": "Pang KS, Rowland M. J Pharmacokinet Biopharm 1977; 5(6):625-653",
        "paper_doi": "10.1007/BF01059688",
        "provenance": "SILVER",
        "paper_supports": "Pang & Rowland 1977 derives the well-stirred and parallel-tube models of hepatic clearance. Well-stirred: CL = Q_h × fu × CLint / (Q_h + fu × CLint). For high-extraction drugs (E > 0.7), the choice of model matters and consistency between in vitro and in vivo is harder.\n",
        "rule_text": "BioMate adopts the well-stirred model as default; flags when extraction ratio E > 0.7 indicates model-choice sensitivity.\n",
        "finding": "Remediation: try parallel-tube model; for high-E drugs, in vitro CLint may underpredict in vivo CL by 2-3 fold.\n"
      }
    ]
  },
  "openfe": {
    "openfe_cycle_closure": [
      {
        "paper_ref": "Mey ASJS et al. Living J Comput Mol Sci 2020; 2(1):18378",
        "paper_doi": "10.33011/livecoms.2.1.18378",
        "provenance": "GOLD",
        "paper_supports": "Mey 2020 (Best Practices for Relative Binding Free Energy Simulations) recommends that the sum of free energies around any closed thermodynamic cycle should be < 1 kcal/mol for the calculation to be considered converged. Larger errors indicate sampling problems.\n",
        "rule_text": "BioMate flags RBFE results with cycle-closure |ΔG_sum| > 1 kcal/mol as not converged.\n",
        "finding": "Remediation: extend simulation time, add intermediate λ windows, or use Hamiltonian Replica Exchange (HREX).\n"
      }
    ]
  },
  "p0_pkpd": {
    "p0_pkpd_weight_loss_band": [
      {
        "paper_ref": "Overgaard RV et al. Clin Pharmacokinet 2019; 58:781-791",
        "paper_doi": "10.1007/s40262-018-0728-4",
        "provenance": "GOLD",
        "paper_supports": "Overgaard 2019 reports the semaglutide PKPD model predictions for weight change vs SUSTAIN clinical trial outcomes. The passing acceptance band for model qualification is ±3 to -6 kg weight change at week 30, matching SUSTAIN-1 (Sorli 2017).\n",
        "rule_text": "BioMate validates simulations against the ±3 to -6 kg band at 30 weeks.\n",
        "finding": "Remediation: re-fit ER model parameters or refine PD model structure (typically the issue is appetite vs basal metabolic rate coupling).\n"
      }
    ]
  },
  "pocket_detection": {
    "pocket_druggability_score": [
      {
        "paper_ref": "Le Guilloux V, Schmidtke P, Tuffery P. BMC Bioinformatics 2009; 10:168",
        "paper_doi": "10.1186/1471-2105-10-168",
        "provenance": "GOLD",
        "paper_supports": "Le Guilloux 2009 introduces fpocket and establishes the druggability score (combining pocket volume, hydrophobicity, and polarity). Score ≥ 0.5 indicates a druggable pocket; < 0.3 is non-druggable.\n",
        "rule_text": "BioMate gates pocket druggability ≥ 0.5 as PASS; 0.3-0.5 as borderline; < 0.3 as FAIL.\n",
        "finding": "Remediation: allosteric site search, fragment screening for cryptic pocket opening, or PROTAC strategy.\n"
      }
    ]
  },
  "aizynthfinder": {
    "aizynth_solved_routes": [
      {
        "paper_ref": "Genheden S et al. J Cheminform 2020; 12:70",
        "paper_doi": "10.1186/s13321-020-00472-1",
        "provenance": "SILVER",
        "paper_supports": "Genheden 2020 introduces aizynthfinder retrosynthesis. The paper recommends generating ≥1 solved synthetic route within a time budget; the specific score thresholds (≥0.9 for \"high quality\") are reasonable but presented as guidelines rather than fixed cutoffs.\n",
        "rule_text": "BioMate flags compounds with 0 solved routes as PASS-fail and flags max score < 0.9 as WARN.\n",
        "finding": "Remediation: relax stock database constraints; increase search time budget; consider alternative disconnections.\n"
      }
    ]
  },
  "cancer_biology": {
    "cancer_somatic_vaf_min": [
      {
        "paper_ref": "GATK Best Practices for Somatic Variant Calling (Broad Institute)",
        "paper_doi": "https://gatk.broadinstitute.org/hc/en-us/articles/360035531132",
        "provenance": "GOLD",
        "paper_supports": "GATK Best Practices documentation specifies VAF >= 0.05 as the default confident-call threshold for Mutect2 somatic variant calling.\n",
        "rule_text": "BioMate flags variants with VAF < 0.05 as below confident-call threshold (GATK Mutect2 default).\n",
        "finding": "Remediation: re-examine raw allele counts; consider deeper sequencing if sub-clonal calls are needed.\n"
      }
    ],
    "cancer_somatic_depth_min": [
      {
        "paper_ref": "Kim S et al. Nat Methods 2018; 15:591-594",
        "paper_doi": "10.1038/s41592-018-0051-x",
        "provenance": "GOLD",
        "paper_supports": "Strelka2 paper Table 2 reports 30x depth as a standard for confident somatic variant calls in tumor samples.\n",
        "rule_text": "BioMate flags variants at loci with depth < 30x as low confidence (Strelka2 community standard).\n",
        "finding": "Remediation: top-up sequencing of low-depth regions.\n"
      }
    ],
    "cancer_somatic_mapping_quality": [
      {
        "paper_ref": "Li H. Bioinformatics 2009; 25:1754-1760",
        "paper_doi": "10.1093/bioinformatics/btp324",
        "provenance": "SILVER",
        "paper_supports": "BWA-MEM paper establishes MAPQ scoring; Phred-20 = 99% accuracy is the de facto community convention for filtering low-quality alignments.\n",
        "rule_text": "BioMate flags reads with mean MAPQ < 20; advisory at 10-20; FAIL below 10.\n",
        "finding": "Remediation: re-align with stricter --min-score; check for reference contamination.\n"
      }
    ]
  },
  "cryo_em": {
    "cryo_em_fsc_resolution": [
      {
        "paper_ref": "Rosenthal PB & Henderson R. J Mol Biol 2003; 333:721-745",
        "paper_doi": "10.1016/j.jmb.2003.07.013",
        "provenance": "GOLD",
        "paper_supports": "Rosenthal & Henderson 2003 establish the FSC 0.143 criterion as the gold-standard resolution metric for single-particle cryo-EM.\n",
        "rule_text": "BioMate flags maps with FSC 0.143 > 4 angstroms as publication-quality threshold; advisory 4-8; FAIL > 15.\n",
        "finding": "Remediation: more particles, deeper refinement, or revisit masking strategy.\n"
      }
    ],
    "cryo_em_motion_drift": [
      {
        "paper_ref": "Punjani A et al. Nat Methods 2017; 14:290-296",
        "paper_doi": "10.1038/nmeth.4169",
        "provenance": "SILVER",
        "paper_supports": "cryoSPARC paper discusses typical drift values; specific cutoff of 50 A is operational community practice for motion-corrected movies.\n",
        "rule_text": "BioMate flags drift > 50 A per movie as advisory; > 100 A as FAIL.\n",
        "finding": "Remediation: re-collect with dose-symmetric protocol; check stage backlash.\n"
      }
    ],
    "cryo_em_particle_count": [
      {
        "paper_ref": "Henderson R. Q Rev Biophys 1995; 28:171-193",
        "paper_doi": "10.1017/S003358350000305X",
        "provenance": "SILVER",
        "paper_supports": "Henderson's information-limit theory describes particle counts needed for sub-3 A resolution; the 50K threshold is operational in the modern detector era.\n",
        "rule_text": "BioMate flags reconstructions with < 50K particles for sub-3 A targets.\n",
        "finding": "Remediation: collect more data; loosen 2D classification filters; recheck picking.\n"
      }
    ]
  },
  "cryo_et": {
    "cryo_et_sta_fsc_resolution": [
      {
        "paper_ref": "Rosenthal PB & Henderson R. J Mol Biol 2003; 333:721-745",
        "paper_doi": "10.1016/j.jmb.2003.07.013",
        "provenance": "GOLD",
        "paper_supports": "Rosenthal & Henderson 2003 establish FSC 0.143 as the gold standard. The criterion applies identically to subtomogram averaging maps as to single-particle cryo-EM.\n",
        "rule_text": "BioMate flags STA FSC 0.143 > 15 angstroms as advisory; > 30 angstroms as FAIL.\n",
        "finding": "Remediation: increase particles in STA; iterate alignment rounds; check missing-wedge compensation.\n"
      }
    ],
    "cryo_et_tilt_residual": [
      {
        "paper_ref": "Mastronarde DN, Held SR. J Struct Biol 2017; 197:102-113",
        "paper_doi": "10.1016/j.jsb.2016.07.011",
        "provenance": "SILVER",
        "paper_supports": "Mastronarde & Held 2017 describe IMOD alignment; residual < 1 px is community standard for good tilt-series alignment.\n",
        "rule_text": "BioMate flags mean tilt-alignment residual > 1 px advisory; > 3 px FAIL.\n",
        "finding": "Remediation: re-run patch tracking with denser fiducials; widen tilt-axis search range.\n"
      }
    ],
    "cryo_et_defocus_range": [
      {
        "paper_ref": "Hagen WJH, Wan W, Briggs JAG. J Struct Biol 2017; 197:191-198",
        "paper_doi": "10.1016/j.jsb.2016.06.007",
        "provenance": "SILVER",
        "paper_supports": "Hagen 2017 describes dose-symmetric tilt schemes. Typical defocus targets are -2 to -6 um; outside [-8.0, -0.5] is usually a data-collection error.\n",
        "rule_text": "BioMate flags mean defocus outside [-8.0, -0.5] um as FAIL.\n",
        "finding": "Remediation: re-check SerialEM/Tomo5 collection protocol.\n"
      }
    ]
  },
  "lnp_formulation": {
    "lnp_z_avg_particle_size": [
      {
        "paper_ref": "FDA Liposome Drug Products Guidance (2018); ISO 22412:2017; Yamamoto et al. Int J Pharm 2019; 569:118547",
        "paper_doi": "10.1016/j.ijpharm.2019.118547",
        "provenance": "SILVER",
        "paper_supports": "FDA 2018 requires DLS characterization of LNP size per ISO 22412 but does not prescribe a numeric Z-avg cutoff. Yamamoto 2019 reports clinical LNP-mRNA Z-averages typically 60-120 nm.\n",
        "rule_text": "BioMate operational rule: 60-120 nm = pass; 40-60 or 120-150 = advisory; outside = FAIL. Community/literature range, not FDA verbatim.\n",
        "finding": "Z-avg outside 60-120 nm risks altered biodistribution or aggregation.\n"
      }
    ],
    "lnp_pdi": [
      {
        "paper_ref": "ISO 22412:2017; LNP DLS community convention",
        "paper_doi": "https://www.iso.org/standard/65410.html",
        "provenance": "SILVER",
        "paper_supports": "ISO 22412 defines PDI as cumulant analysis width metric. Community convention (Yamamoto 2019, Onpattro CMC) treats PDI < 0.2 as pharmaceutical-grade monodisperse; >0.3 broad.\n",
        "rule_text": "PDI < 0.2 = pass; 0.2-0.3 = advisory; > 0.3 = FAIL.\n",
        "finding": "Higher PDI indicates batch heterogeneity / formulation instability.\n"
      }
    ],
    "lnp_encapsulation_efficiency": [
      {
        "paper_ref": "Yamamoto et al. Int J Pharm 2019; 569:118547; FDA Liposome Guidance 2018",
        "paper_doi": "10.1016/j.ijpharm.2019.118547",
        "provenance": "SILVER",
        "paper_supports": "LNP-mRNA literature reports RiboGreen-exclusion EE of 85-95% as the clinical-grade target. FDA requires control, not a numeric floor.\n",
        "rule_text": "EE >= 85% = pass; 70-85% = advisory; < 70% = FAIL.\n",
        "finding": "Low EE indicates suboptimal lipid:RNA ratio or mixing — reformulate.\n"
      }
    ]
  },
  "nlmixr2_poppk": {
    "nlmixr2_eta_shrinkage": [
      {
        "paper_ref": "Savic RM & Karlsson MO. Clin Pharmacokinet 2009; 48(7):415-426",
        "paper_doi": "10.2165/00003088-200948070-00001",
        "provenance": "GOLD",
        "paper_supports": "Savic & Karlsson 2009 establish ~30% as the η-shrinkage threshold above which EBE-based diagnostics and covariate screening become unreliable. The paper explicitly recommends this cutoff.\n",
        "rule_text": "η-shrinkage < 20% = pass; 20-30% = advisory; > 30% = FAIL (EBE-based covariate inference unreliable).\n",
        "finding": "High shrinkage → rely on simulation-based diagnostics, not EBE plots.\n"
      }
    ],
    "nlmixr2_condition_number": [
      {
        "paper_ref": "FDA Population Pharmacokinetics Guidance (1999, reaffirmed 2022); NONMEM/nlmixr2 community",
        "paper_doi": "https://www.fda.gov/media/128793/download",
        "provenance": "SILVER",
        "paper_supports": "FDA requires reporting of model stability/condition diagnostics; the <1000 community convention for covariance matrix condition is from Bonate & Mould/Upton tutorials, not stated verbatim in FDA guidance.\n",
        "rule_text": "Condition number < 100 = pass; 100-1000 = advisory; > 1000 = FAIL (ill-conditioned, model likely overparameterized).\n",
        "finding": "Ill conditioning indicates redundant parameters — simplify model.\n"
      }
    ],
    "nlmixr2_ofv_stability": [
      {
        "paper_ref": "FDA Pop-PK Guidance + NONMEM community practice",
        "paper_doi": "https://www.fda.gov/media/128793/download",
        "provenance": "BRONZE",
        "paper_supports": "FDA requires convergence/stability evidence. The |ΔOFV| < 3.84 community cutoff comes from chi-squared 1 df interpretation, not published as a Pop-PK QC threshold.\n",
        "rule_text": "|ΔOFV| < 1.0 = pass; 1.0-3.84 = advisory; >= 3.84 = FAIL.\n",
        "finding": "Large OFV swings across seeds → local minimum suspected.\n"
      }
    ]
  },
  "antibody_developability": {
    "ab_tap_cdr_length": [
      {
        "paper_ref": "Raybould MIJ et al. PNAS 2019; 116:4025-4030 (Therapeutic Antibody Profiler)",
        "paper_doi": "10.1073/pnas.1810576116",
        "provenance": "GOLD",
        "paper_supports": "Raybould 2019 Table 1 reports total CDR length distribution across clinical-stage therapeutics; CST 5th-95th percentile bounds for total CDR length are 43-63 residues (IMGT numbering).\n",
        "rule_text": "Total CDR length within 43-63 residues = pass; 40-43 or 63-67 = advisory; outside = FAIL.\n",
        "finding": "Outside CST band: risk of poor expression, aggregation, polyspecificity.\n"
      }
    ],
    "ab_tap_surface_hydrophobicity": [
      {
        "paper_ref": "Raybould MIJ et al. PNAS 2019; 116:4025-4030",
        "paper_doi": "10.1073/pnas.1810576116",
        "provenance": "GOLD",
        "paper_supports": "Raybould 2019 Table 1 defines TAP PSH (Patches of Surface Hydrophobicity) amber band as CST 5th-95th percentile ≈ 90-150.\n",
        "rule_text": "PSH within 90-150 = pass; outside = FAIL.\n",
        "finding": "High PSH correlates with viscosity + self-association at formulation conc.\n"
      }
    ],
    "ab_camsol_intrinsic_solubility": [
      {
        "paper_ref": "Sormanni P, Aprile FA, Vendruscolo M. PNAS 2017; 114:E3367-E3375 (CamSol)",
        "paper_doi": "10.1073/pnas.1422401112",
        "provenance": "SILVER",
        "paper_supports": "Sormanni 2017 reports CamSol intrinsic solubility per-residue scale where >+1 = highly soluble, <-1 = aggregation-prone. Whole-sequence average cutoff is community application of the scale.\n",
        "rule_text": "CamSol score >= 1.0 = pass; 0-1 = advisory; < 0 = FAIL.\n",
        "finding": "Low CamSol = aggregation-prone regions, poor for high-conc formulation.\n"
      }
    ]
  },
  "sirna_offtarget": {
    "sirna_seed_mismatch_count": [
      {
        "paper_ref": "Birmingham A et al. Nat Methods 2006; 3:199-204",
        "paper_doi": "10.1038/nmeth854",
        "provenance": "SILVER",
        "paper_supports": "Birmingham 2006 demonstrates seed-region (positions 2-8) complementarity as the driver of siRNA off-target silencing. The paper establishes the property; the >=2 mismatch operational cutoff is community convention.\n",
        "rule_text": "Min seed mismatches across off-target hit list >= 2 = pass; 1 = advisory; 0 = FAIL.\n",
        "finding": "Near-perfect seed matches in off-targets = high miRNA-like silencing risk.\n"
      }
    ],
    "sirna_thermodynamic_asymmetry": [
      {
        "paper_ref": "Khvorova A, Reynolds A, Jayasena SD. Cell 2003; 115:209-216",
        "paper_doi": "10.1016/S0092-8674(03)00801-8",
        "provenance": "GOLD",
        "paper_supports": "Khvorova 2003 quantitatively demonstrates functional siRNAs exhibit thermodynamic asymmetry favoring antisense-strand loading; functional siRNAs show ΔdG (5' sense - 5' antisense, 5 bp) >= ~0.5 kcal/mol.\n",
        "rule_text": "Thermodynamic asymmetry ΔdG >= 0.5 kcal/mol = pass; 0-0.5 = advisory; < 0 = FAIL (sense strand will preferentially load into RISC).\n",
        "finding": "Insufficient asymmetry → sense-strand RISC loading → off-target silencing.\n"
      }
    ]
  },
  "polymorph_stability": {
    "assay_degradation_accelerated": [
      {
        "paper_ref": "ICH Q1A(R2) Stability Testing (2003) §2.1.7.1",
        "paper_doi": "https://database.ich.org/sites/default/files/Q1A%28R2%29%20Guideline.pdf",
        "provenance": "SILVER",
        "paper_supports": "ICH Q1A(R2) §2.1.7.1 defines significant change at accelerated conditions (40°C/75%RH, 6 mo) as ≥5% change in assay from initial. The 5% threshold is in the guideline verbatim for the significant-change definition.\n",
        "rule_text": "Assay loss at 6mo / 40°C / 75%RH < 5% = pass; >= 5% = FAIL (significant change per ICH Q1A R2 — intermediate condition study triggered).\n",
        "finding": "Significant change at accelerated → cannot rely on accelerated for shelf-life.\n"
      }
    ],
    "polymorph_form_conversion": [
      {
        "paper_ref": "ICH Q6A Decision Tree #4 (1999); Bauer et al. Pharm Res 2001; Brittain 2009",
        "paper_doi": "https://database.ich.org/sites/default/files/Q6A%20Guideline.pdf",
        "provenance": "SILVER",
        "paper_supports": "ICH Q6A DT#4 requires polymorphic form control when forms differ in performance. The 10% conversion cutoff is community practice (Bauer 2001, Brittain 2009), not numeric in ICH.\n",
        "rule_text": "Polymorph conversion < 10% during accelerated stability = pass; >= 10% = FAIL (form may be metastable).\n",
        "finding": "Significant form conversion = reformulate or change polymorph selection.\n"
      }
    ],
    "shelf_life_projection": [
      {
        "paper_ref": "ICH Q1E Evaluation of Stability Data (2003) §2.4 + §2.6",
        "paper_doi": "https://database.ich.org/sites/default/files/Q1E%20Guideline.pdf",
        "provenance": "SILVER",
        "paper_supports": "ICH Q1E permits shelf-life extrapolation up to 2× long-term data period when conditions met. 24-month target is community/regulatory convention for room-temperature solid orals.\n",
        "rule_text": "95% LCB on projected shelf-life >= 24 months = pass; < 24 = advisory.\n",
        "finding": "Short shelf-life → refrigerated labeling or reformulation indicated.\n"
      }
    ]
  },
  "biomarker_enrichment": {
    "biomarker_positive_hazard_ratio": [
      {
        "paper_ref": "FDA Enrichment Strategies for Clinical Trials Guidance (2019); Wang SJ et al. Stat Med 2018",
        "paper_doi": "10.1002/sim.7572",
        "provenance": "SILVER",
        "paper_supports": "FDA 2019 endorses predictive enrichment when marker-positive shows substantially larger effect. Wang 2018 + Mehrotra 2011 operationally use HR <= 0.7 for clinically meaningful enrichment; not in FDA verbatim.\n",
        "rule_text": "Biomarker-positive HR <= 0.7 = pass; > 0.7 = FAIL (enrichment unjustified).\n",
        "finding": "Inadequate effect concentration in marker+ → reconsider all-comers design.\n"
      }
    ],
    "predictive_prevalence": [
      {
        "paper_ref": "Simon R, Maitournam A. Clin Cancer Res 2004; 10:6759-6763",
        "paper_doi": "10.1158/1078-0432.CCR-04-0496",
        "provenance": "SILVER",
        "paper_supports": "Simon & Maitournam 2004 show enrichment efficiency depends on biomarker prevalence. The 10-50% efficient window is community convention derived from their efficiency curves.\n",
        "rule_text": "Predicted biomarker-positive prevalence in [0.10, 0.50] = pass; outside = advisory.\n",
        "finding": "<10% prevalence: screening burden too high; >50%: little efficiency benefit.\n"
      }
    ],
    "phase3_enrichment_factor": [
      {
        "paper_ref": "Mehrotra DV et al. Pharm Stat 2011; 10:357-369; FDA Enrichment 2019",
        "paper_doi": "10.1002/pst.473",
        "provenance": "BRONZE",
        "paper_supports": "Mehrotra 2011 notes enrichment worthwhile when sample-size reduction exceeds ~30%. The 1.5 enrichment-factor cutoff is back-derived from this; not stated verbatim.\n",
        "rule_text": "Enrichment factor (N_all_comers / N_enriched) >= 1.5 = pass; < 1.5 = advisory.\n",
        "finding": "Below 1.5: targeted design saves insufficient sample size vs screening cost.\n"
      }
    ]
  }
};
export function getEvidenceForGate(d: string, g: string): QCEvidenceEntry[] {
  return (QC_EVIDENCE[d] ?? {})[g] ?? [];
}
export function getAllGatesForDomain(d: string): Record<string, QCEvidenceEntry[]> {
  return QC_EVIDENCE[d] ?? {};
}
export function listDomains(): string[] { return Object.keys(QC_EVIDENCE); }
