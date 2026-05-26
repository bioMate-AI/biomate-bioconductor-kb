/**
 * QC gate evidence — generated from backend/config/qc_evidence.yaml.
 * DO NOT hand-edit. To regenerate:
 *   python3 -c "import yaml, json; print(json.dumps(yaml.safe_load(open('backend/config/qc_evidence.yaml')), indent=2, ensure_ascii=False))" \
 *     > frontend/client/src/data/qc-evidence.json
 *
 * Why embed at build time instead of fetching via /api/qc/evidence?
 * The Node routes.ts file is protected against parallel-session edits
 * (see docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md). Embedding the
 * static provenance data into the bundle avoids the API path entirely.
 *
 * Provenance grades:
 *   GOLD   — verbatim from cited source
 *   SILVER — community convention; concept supported, exact cutoff not
 *   BRONZE — operational heuristic; cited paper is related context only
 */

export interface QCEvidenceEntry {
  paper_ref: string;
  paper_doi: string;
  provenance: "GOLD" | "SILVER" | "BRONZE";
  paper_supports: string;
  rule_text: string;
  finding: string;
}

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
        "paper_ref": "Aronov AM 2008. J Med Chem 51:6632-6641",
        "paper_doi": "10.1021/jm800467u",
        "provenance": "GOLD",
        "paper_supports": "Aronov 2008 establishes hERG IC50 ≤ 10 µM as the safety cutoff for cardiac liability in early-stage drug discovery.\n",
        "rule_text": "BioMate halts if hERG IC50 ≤ 10 µM (admet_standard profile).\n",
        "finding": "Remediation: tighten upstream logP and pKa filters; hERG liability correlates with basic amines and high lipophilicity.\n"
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
    ]
  }
};

export function getEvidenceForGate(
  domain: string,
  gate: string,
): QCEvidenceEntry[] {
  const domainEntries = QC_EVIDENCE[domain] ?? {};
  return domainEntries[gate] ?? [];
}

export function getAllGatesForDomain(
  domain: string,
): Record<string, QCEvidenceEntry[]> {
  return QC_EVIDENCE[domain] ?? {};
}

export function listDomains(): string[] {
  return Object.keys(QC_EVIDENCE);
}
