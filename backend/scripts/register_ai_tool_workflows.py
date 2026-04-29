#!/usr/bin/env python3
"""
register_ai_tool_workflows.py

Registers the 8 BioMate AI tool Nextflow workflows into the Galaxy workflows
table and rebuilds the FTS index. Run once after files are created; safe to
re-run (uses workflow_hash for idempotency).

Usage:
    python scripts/register_ai_tool_workflows.py [--db /path/to/galaxy_ai_tools.db]
"""

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
NF_BASE   = REPO_ROOT / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"

WORKFLOWS = [
    {
        "name":        "boltz_structure_prediction",
        "filename":    "structural_biology/boltz_structure_prediction/main.nf",
        "description": (
            "Biomolecular structure prediction using Boltz-2 (MIT licensed). "
            "Predicts structures of proteins, RNA, DNA, ligands, and protein-ligand complexes "
            "with binding affinity estimates. 1000x faster than physics-based FEP. "
            "Input: FASTA or YAML. Output: mmCIF/PDB structures, confidence scores."
        ),
        "annotation":  "Boltz-2 v2.2.1 structure prediction. Input: FASTA/YAML. Output: mmCIF, confidence JSON.",
        "tags":        "boltz,boltz2,structure prediction,protein folding,ligand binding,binding affinity,biomolecular",
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest",
        "input_types": ["fasta", "yaml"],
        "output_types":["mmcif", "pdb", "json"],
        "step_count":  3,
        "tools_used":  "Boltz-2",
    },
    {
        "name":        "chai1_structure_prediction",
        "filename":    "structural_biology/chai1_structure_prediction/main.nf",
        "description": (
            "Multi-modal biomolecular structure prediction using Chai-1 (Apache 2.0). "
            "Handles proteins, small molecules, DNA, RNA, glycosylations, and multi-chain "
            "complexes in a single forward pass. State-of-the-art accuracy. "
            "Input: FASTA with chain type headers. Output: mmCIF structures."
        ),
        "annotation":  "Chai-1 multi-modal structure prediction. Input: FASTA (chain headers). Output: CIF structures.",
        "tags":        "chai1,chai-1,structure prediction,protein complex,ligand,multi-chain,dna,rna,glycan",
        "domain":      "structural_biology",
        "category":    "Structure Prediction",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest",
        "input_types": ["fasta"],
        "output_types":["cif", "json"],
        "step_count":  2,
        "tools_used":  "Chai-1",
    },
    {
        "name":        "drugclip_virtual_screening",
        "filename":    "drug_discovery/drugclip_virtual_screening/main.nf",
        "description": (
            "Ultra-fast structure-based virtual screening using DrugCLIP (Science 2026). "
            "CLIP-based contrastive learning; 10 million times faster than docking. "
            "Screened 10K proteins x 500M compounds. Input: protein PDB + SMILES file. "
            "Output: ranked compound hits with scores."
        ),
        "annotation":  "DrugCLIP virtual screening. Input: receptor PDB + SMILES. Output: ranked hits CSV.",
        "tags":        "drugclip,virtual screening,drug discovery,docking,CLIP,compound screening,hit finding,SMILES",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest",
        "input_types": ["pdb", "smi"],
        "output_types":["csv", "json"],
        "step_count":  3,
        "tools_used":  "DrugCLIP",
    },
    {
        "name":        "scfv_antibody_design",
        "filename":    "drug_discovery/scfv_antibody_design/main.nf",
        "description": (
            "AI-driven scFv intrabody design using ProteinMPNN + AlphaFold2 (Science Advances 2026). "
            "Converts conventional antibodies to functional single-chain Fv intrabodies. "
            "73% success rate vs 31% standard methods. "
            "Input: antibody PDB. Output: designed scFv sequences (FASTA) + predicted structures."
        ),
        "annotation":  "scFv antibody design via ProteinMPNN+AF2. Input: antibody PDB. Output: designed FASTA + PDB.",
        "tags":        "scfv,antibody design,intrabody,ProteinMPNN,AlphaFold2,protein design,antibody engineering",
        "domain":      "drug_discovery",
        "category":    "Protein Design",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest",
        "input_types": ["pdb"],
        "output_types":["fasta", "pdb", "json"],
        "step_count":  3,
        "tools_used":  "scFv-pMPNN, AlphaFold2",
    },
    {
        "name":        "syncraft_synthesizability",
        "filename":    "drug_discovery/syncraft_synthesizability/main.nf",
        "description": (
            "LLM-guided molecular synthesizability optimization using SynCraft. "
            "Uses Chain-of-Thought prompting with Gemini-2.5-Pro to predict atom-level edits "
            "(DEL_ATOM, ADD_BOND, DEL_BOND, CHANGE_BOND) that improve synthetic accessibility. "
            "Input: SMILES string or file. Output: optimized SMILES with SA scores."
        ),
        "annotation":  "SynCraft synthesizability optimization (Gemini-2.5-Pro). Input: SMILES. Output: optimized SMILES CSV.",
        "tags":        "syncraft,synthesizability,synthetic accessibility,SA score,molecule optimization,drug design,SMILES",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest",
        "input_types": ["smiles", "smi"],
        "output_types":["csv", "json"],
        "step_count":  3,
        "tools_used":  "SynCraft, Gemini-2.5-Pro",
    },
    {
        "name":        "protrek_protein_search",
        "filename":    "proteomics/protrek_protein_search/main.nf",
        "description": (
            "Trimodal protein search using ProTrek (Nature Biotechnology 2025). "
            "Unifies sequence, structure, and function through contrastive learning. "
            "Search 5B+ proteins by text description, amino acid sequence, or 3D structure. "
            "Input: text query / FASTA / PDB. Output: ranked protein hits with scores."
        ),
        "annotation":  "ProTrek trimodal protein search. Input: text/sequence/structure. Output: ranked hits JSON+CSV.",
        "tags":        "protrek,protein search,trimodal,sequence search,structure search,function search,proteomics",
        "domain":      "proteomics",
        "category":    "Protein Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest",
        "input_types": ["text", "fasta", "pdb"],
        "output_types":["json", "csv", "npy"],
        "step_count":  3,
        "tools_used":  "ProTrek",
    },
    {
        "name":        "profam_fitness_prediction",
        "filename":    "proteomics/profam_fitness_prediction/main.nf",
        "description": (
            "Protein variant fitness prediction using ProFAM-1 (251M parameter autoregressive model). "
            "State-of-the-art on ProteinGym benchmark (0.47 substitutions, 0.53 indels Spearman rho). "
            "No multiple sequence alignment required at inference. "
            "Input: FASTA with variants or CSV variant table. Output: fitness scores per variant."
        ),
        "annotation":  "ProFAM-1 fitness scoring. Input: variant FASTA or CSV. Output: fitness scores CSV.",
        "tags":        "profam,fitness prediction,protein engineering,variant effect,ProteinGym,directed evolution",
        "domain":      "proteomics",
        "category":    "Protein Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest",
        "input_types": ["fasta", "csv"],
        "output_types":["csv", "json", "npy"],
        "step_count":  2,
        "tools_used":  "ProFAM-1",
    },
    {
        "name":        "state_perturbation_prediction",
        "filename":    "single_cell/state_perturbation_prediction/main.nf",
        "description": (
            "Virtual cell perturbation prediction using STATE (Arc Institute). "
            "Predicts cellular transcriptional responses to genetic or chemical perturbations "
            "without running experiments. Trained on 270M+ cells including Tahoe-100M. "
            "Input: AnnData h5ad + perturbation name. Output: predicted expression profiles + DEGs."
        ),
        "annotation":  "STATE virtual cell model. Input: h5ad + perturbation. Output: predicted h5ad, DEG CSV.",
        "tags":        "state,virtual cell,perturbation,single cell,transcriptomics,Perturb-seq,genetic perturbation,AnnData",
        "domain":      "single_cell",
        "category":    "Single Cell Analysis",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest",
        "input_types": ["h5ad"],
        "output_types":["h5ad", "csv", "json"],
        "step_count":  3,
        "tools_used":  "STATE",
    },
    # ── 14 new gap-filling workflows (2026-04-17) ────────────────────────────
    {
        "name":        "allometric_scaling",
        "filename":    "pharmacology/allometric_scaling/main.nf",
        "description": (
            "Scales pharmacokinetic parameters (CL, Vd, t½) from preclinical species to human "
            "using allometric regression (power law), Rule of Exponents (Mahmood 2003), and MLP/brain-weight "
            "correction factors. Predicts first-in-human dose (MABEL/MRSD) per FDA 2005 Guidance. "
            "Input: JSON array of per-species PK data (rat/dog/monkey). Output: human PK prediction + FIH dose."
        ),
        "annotation":  "Allometric PK scaling + FIH dose prediction. Input: species PK JSON. Output: human_pk.json, fih_dose.json.",
        "tags":        "allometric scaling,PK,pharmacokinetics,first-in-human,MABEL,MRSD,species translation,FIH dose,CL,Vd,half-life",
        "domain":      "pharmacology",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, SciPy, power-law regression, Rule of Exponents",
    },
    {
        "name":        "cns_penetration_prediction",
        "filename":    "pharmacology/cns_penetration_prediction/main.nf",
        "description": (
            "Predicts blood-brain barrier permeability and CNS drug exposure. "
            "Computes CNS MPO score (6 RDKit descriptors per Wager et al. 2010), P-gp/BCRP efflux substrate status, "
            "and Kp,uu,brain (unbound brain-to-plasma ratio). "
            "Input: SMILES (single or batch). Output: cns_properties.csv, brain_penetration.csv with BBB class (HIGH/MEDIUM/LOW)."
        ),
        "annotation":  "CNS MPO + Kpuu brain + P-gp prediction. Input: SMILES. Output: cns_properties.csv, brain_penetration.csv.",
        "tags":        "CNS,blood-brain barrier,BBB,brain penetration,CNS MPO,Kpuu,P-gp,BCRP,efflux ratio,central nervous system",
        "domain":      "pharmacology",
        "category":    "ADMET",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["csv", "json"],
        "step_count":  2,
        "tools_used":  "RDKit, CNS MPO (Wager 2010), Kpuu brain model (Friden 2011)",
    },
    {
        "name":        "dart_toxicity_prediction",
        "filename":    "pharmacology/dart_toxicity_prediction/main.nf",
        "description": (
            "Predicts Developmental And Reproductive Toxicity (DART) risk using structural alerts "
            "(ICH S5/OECD QSAR library, 16 alert classes) and physicochemical placental transfer model. "
            "Returns risk tier (HIGH/MEDIUM/LOW), triggered alerts, and regulatory recommendations (ICH S5A/B). "
            "Input: SMILES. Output: dart_alerts.csv, placental_transfer.csv, dart_risk_tier.json."
        ),
        "annotation":  "DART structural alerts + placental transfer. Input: SMILES. Output: dart_risk_tier.json, dart_alerts.csv.",
        "tags":        "DART,developmental toxicity,reproductive toxicity,teratogenicity,placental transfer,ICH S5,structural alerts,DMPK",
        "domain":      "pharmacology",
        "category":    "Toxicology",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, ICH S5 SMARTS alert library, placental transfer model",
    },
    {
        "name":        "oral_absorption_bcs_model",
        "filename":    "pharmacology/oral_absorption_bcs_model/main.nf",
        "description": (
            "BCS classification and oral absorption modeling. "
            "Predicts solubility (ESOL model), Caco-2 permeability (QSAR), BCS class (I-IV), "
            "dissolution profile (first-order kinetics, fed/fasted), and oral bioavailability (F%). "
            "Recommends formulation strategy (ASD, lipid-based, HCl salt, standard). "
            "Input: SMILES + dose_mg. Output: bcs_classification.json, dissolution_profile.csv, formulation_recommendation.json."
        ),
        "annotation":  "BCS classification + dissolution + F% prediction. Input: SMILES+dose. Output: bcs.json, dissolution.csv.",
        "tags":        "BCS,oral absorption,bioavailability,dissolution,Caco-2,solubility,ESOL,formulation,BCS I II III IV,biopharmaceutics",
        "domain":      "pharmacology",
        "category":    "ADMET",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  3,
        "tools_used":  "RDKit, ESOL (Delaney 2004), Caco-2 QSAR (Hou 2004), BCS FDA 2017",
    },
    {
        "name":        "transporter_ddi_prediction",
        "filename":    "pharmacology/transporter_ddi_prediction/main.nf",
        "description": (
            "Predicts substrate and inhibitor status for 8 FDA-mandated drug transporters "
            "(OATP1B1, OATP1B3, P-gp, BCRP, MATE1, MATE2-K, OAT1, OCT2). "
            "Calculates static DDI AUC ratios per FDA DDI Guidance 2020 basic model. "
            "Flags transporters requiring in vitro mechanistic studies or clinical DDI studies. "
            "Input: SMILES + Cmax_uM. Output: transporter_results.csv, regulatory_summary.json."
        ),
        "annotation":  "8-transporter DDI prediction + FDA static model. Input: SMILES+Cmax. Output: transporter_results.csv, regulatory_summary.json.",
        "tags":        "transporter DDI,OATP1B1,OATP1B3,P-gp,BCRP,MATE1,OCT2,OAT1,drug-drug interaction,FDA DDI guidance,NDA",
        "domain":      "pharmacology",
        "category":    "Drug Interactions",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, FDA DDI Basic Model 2020, Karlgren et al. transporter rules",
    },
    {
        "name":        "repeated_dose_tox_prediction",
        "filename":    "pharmacology/repeated_dose_tox_prediction/main.nf",
        "description": (
            "Predicts organ-level toxicity from repeated dosing using a structural alert library "
            "(>25 ICH M7 + OECD QSAR alerts) covering hepatotoxicity, nephrotoxicity, cardiotoxicity, "
            "and bone marrow suppression. Estimates NOAEL from alert severity and safety margin vs projected Cmax. "
            "Input: SMILES (batch), optional projected_Cmax_nM. Output: tox_alerts.csv, tox_summary.json, safety_margins.csv."
        ),
        "annotation":  "Structural alert-based repeated-dose tox. Input: SMILES. Output: tox_alerts.csv, tox_summary.json.",
        "tags":        "repeated dose toxicity,hepatotoxicity,cardiotoxicity,nephrotoxicity,bone marrow,NOAEL,safety margin,structural alerts,IND-enabling",
        "domain":      "pharmacology",
        "category":    "Toxicology",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, ICH M7 alerts, OECD QSAR alerts, rdkit-toxicophore",
    },
    {
        "name":        "nanoparticle_pk_biodistribution",
        "filename":    "pharmacology/nanoparticle_pk_biodistribution/main.nf",
        "description": (
            "Models in vivo pharmacokinetics of nanoparticle-formulated drugs. "
            "4-compartment ODE model (blood, tumor, liver/MPS, peripheral) with PEG stealth model "
            "and EPR tumor accumulation (Wilhelm et al. 2016 meta-analysis). "
            "Predicts circulation half-life, tumor EPR accumulation, MPS uptake at 24h. "
            "Input: particle_diameter_nm, surface_chemistry, PEG_density. Output: pk_profile.csv, half_life_summary.json."
        ),
        "annotation":  "NP PK 4-compartment ODE + PEG stealth + EPR. Input: particle params. Output: pk_profile.csv, half_life_summary.json.",
        "tags":        "nanoparticle,LNP,PK,biodistribution,EPR,MPS,PEG stealth,tumor accumulation,drug delivery,nanomedicine",
        "domain":      "pharmacology",
        "category":    "Drug Delivery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "SciPy ODE, EPR model (Wilhelm 2016), PEG stealth model (Arvizo 2011)",
    },
    {
        "name":        "membrane_permeability_prediction",
        "filename":    "pharmacology/membrane_permeability_prediction/main.nf",
        "description": (
            "Predicts apparent permeability across intestinal (Caco-2) and artificial (PAMPA) membranes. "
            "Computes P-gp/BCRP efflux substrate status, efflux ratio, and BCS permeability class. "
            "QSAR models from Hou et al. 2004 and Gao et al. 2008. "
            "Input: SMILES. Output: permeability_results.csv with Papp A→B/B→A, efflux ratio, P-gp status."
        ),
        "annotation":  "Caco-2 + PAMPA + P-gp QSAR prediction. Input: SMILES. Output: permeability_results.csv.",
        "tags":        "Caco-2,PAMPA,membrane permeability,P-gp,efflux ratio,BCS permeability,intestinal absorption,oral bioavailability",
        "domain":      "pharmacology",
        "category":    "ADMET",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["csv", "json"],
        "step_count":  2,
        "tools_used":  "RDKit, Caco-2 QSAR (Hou 2004), PAMPA QSAR (Gao 2008), P-gp Seelig model",
    },
    {
        "name":        "lnp_formulation_optimization",
        "filename":    "drug_discovery/lnp_formulation_optimization/main.nf",
        "description": (
            "Optimizes lipid nanoparticle (LNP) formulation for nucleic acid delivery (mRNA/siRNA/ASO/DNA). "
            "Predicts ionizable lipid pKa (RDKit proxy), endosomal escape score (Henderson-Hasselbalch), "
            "and tissue targeting score. Sweeps IL:helper:cholesterol:PEG-lipid molar ratios. "
            "Input: ionizable_lipid_SMILES, cargo_type, target_tissue. Output: recommended_formulation.json."
        ),
        "annotation":  "LNP pKa + endosomal escape + ratio optimization. Input: lipid SMILES+cargo. Output: recommended_formulation.json.",
        "tags":        "LNP,lipid nanoparticle,mRNA delivery,siRNA,ionizable lipid,pKa,endosomal escape,formulation,gene therapy,nucleic acid delivery",
        "domain":      "drug_discovery",
        "category":    "Drug Delivery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  3,
        "tools_used":  "RDKit, Henderson-Hasselbalch, Kulkarni LNP model, Semple formulation data",
    },
    {
        "name":        "target_engagement_kinetics",
        "filename":    "drug_discovery/target_engagement_kinetics/main.nf",
        "description": (
            "Estimates drug-target binding kinetic rate constants (kon, koff) and residence time (RT = 1/koff). "
            "Solves receptor occupancy ODE with time-varying drug concentration from 1-compartment PK model. "
            "Determines whether residence time is adequate for QD/BID dosing. "
            "Input: SMILES, optional IC50_nM and PK params. Output: kinetics_prediction.json, occupancy_profile.csv."
        ),
        "annotation":  "kon/koff estimation + occupancy ODE. Input: SMILES+IC50+PK. Output: kinetics.json, occupancy.csv.",
        "tags":        "target engagement,residence time,kon,koff,receptor occupancy,kinetics,drug-target binding,RT,drug residence time",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, SciPy ODE, Copeland kinetics model (2016)",
    },
    {
        "name":        "proteome_selectivity_profiling",
        "filename":    "drug_discovery/proteome_selectivity_profiling/main.nf",
        "description": (
            "Predicts binding affinity across kinase (468 kinome), GPCR, or nuclear receptor panels. "
            "Uses ChEMBL REST API similarity search + Tanimoto-weighted activity transfer, "
            "with descriptor-based fallback. Computes selectivity entropy and Gini index. "
            "Input: SMILES + target_class. Output: selectivity_panel.csv, selectivity_metrics.json."
        ),
        "annotation":  "Kinome/GPCR selectivity profiling. Input: SMILES+target_class. Output: selectivity_panel.csv, selectivity_metrics.json.",
        "tags":        "selectivity,kinome,GPCR,off-target,Gini index,selectivity entropy,kinase panel,proteome,CDK,EGFR,BTK",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["csv", "json"],
        "step_count":  3,
        "tools_used":  "RDKit, ChEMBL REST API v3, Morgan fingerprints, Tanimoto kNN",
    },
    {
        "name":        "covalent_warhead_design",
        "filename":    "drug_discovery/covalent_warhead_design/main.nf",
        "description": (
            "Evaluates electrophilic warhead reactivity for targeted covalent inhibitors. "
            "Classifies warhead type (acrylamide, chloroacetamide, vinyl sulfone, etc.) via SMARTS, "
            "predicts GSH half-life from literature data, and estimates kinome cysteine selectivity. "
            "Input: SMILES. Output: warhead_profile.json, cys_selectivity.csv, recommendation.json."
        ),
        "annotation":  "Warhead SMARTS + GSH t½ + Cys selectivity. Input: SMILES. Output: warhead_profile.json, recommendation.json.",
        "tags":        "covalent inhibitor,warhead,acrylamide,chloroacetamide,GSH reactivity,targeted covalent,BTK,EGFR,KRAS G12C,cysteine",
        "domain":      "drug_discovery",
        "category":    "Drug Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, CovPDB warhead library, Mah 2014 GSH reactivity data",
    },
    {
        "name":        "pbpk_simulation",
        "filename":    "drug_discovery/pbpk_simulation/main.nf",
        "description": (
            "8-compartment physiologically-based pharmacokinetic (PBPK) model (Rodgers/Rowland method). "
            "Mechanistic organ-level PK: gut wall, liver (first-pass), blood, lung, kidney, peripheral tissues. "
            "Supports healthy adult, pediatric, elderly, and hepatic impairment populations. "
            "Input: physicochemical params + CLint + dose. Output: pk_profile.csv, nca_parameters.json."
        ),
        "annotation":  "8-compartment PBPK ODE model. Input: MW/logP/CLint/dose. Output: pk_profile.csv, nca_parameters.json.",
        "tags":        "PBPK,physiologically-based,pharmacokinetics,organ PK,CLint,hepatic clearance,first-pass,population PK,hepatic impairment,pediatric dose",
        "domain":      "drug_discovery",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  3,
        "tools_used":  "SciPy LSODA ODE, Rodgers/Rowland Kp model, Willmann physiology database",
    },
    {
        "name":        "clinical_trial_simulation",
        "filename":    "drug_discovery/clinical_trial_simulation/main.nf",
        "description": (
            "Simulates Phase I dose escalation and Phase II clinical trials. "
            "Supports 3+3 and BOIN (Liu & Yuan 2015) designs. "
            "Uses 1-compartment PopPK with log-normal IIV and Emax exposure-response model. "
            "Computes MTD operating characteristics and Phase II response rate over n_simulations. "
            "Input: dose levels + PK params + ER model. Output: dose_escalation_results.csv, operating_characteristics.json."
        ),
        "annotation":  "BOIN/3+3 dose escalation + PopPK Phase II simulation. Input: dose+PK+ER params. Output: OC.json, escalation.csv.",
        "tags":        "clinical trial simulation,BOIN,dose escalation,MTD,Phase I,Phase II,PopPK,exposure response,IIV,DLT,oncology dose",
        "domain":      "drug_discovery",
        "category":    "Clinical Development",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  3,
        "tools_used":  "SciPy, NumPy, BOIN algorithm (Liu & Yuan 2015), 1-cmt PopPK",
    },
    {
        "name":        "metabolite_prediction_biotransformer",
        "filename":    "pharmacology/metabolite_prediction_biotransformer/main.nf",
        "description": (
            "Predicts phase I and phase II metabolites of small molecules using "
            "SMARTS-based transformation rules (BioTransformer 3.0 rule-derived). "
            "Phase I: aliphatic/aromatic hydroxylation, N-/O-dealkylation, N-oxidation, "
            "sulfoxidation, ester/amide hydrolysis, ketone reduction. "
            "Phase II: UGT glucuronidation, SULT sulfation, NAT acetylation, "
            "GST glutathione conjugation, COMT methylation. "
            "Gut microbiota transformations (glucuronide hydrolysis, dehydroxylation). "
            "Multi-cycle metabolism (up to 3 generations). "
            "Output: metabolites.csv with SMILES, enzyme, confidence, generation; metabolite tree JSON."
        ),
        "annotation":  "Metabolite prediction (BioTransformer-style). Input: SMILES. Output: metabolites CSV, metabolite tree JSON.",
        "tags":        "metabolite,metabolism,phase1,phase2,biotransformer,SMARTS,drug metabolism,ADME,CYP,UGT,gut microbiota",
        "domain":      "pharmacology",
        "category":    "Drug Metabolism",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles", "json"],
        "output_types":["json", "csv"],
        "step_count":  1,
        "tools_used":  "RDKit AllChem, SMARTS reaction rules (BioTransformer3.0 rule-derived)",
    },
    {
        "name":        "pharmacogenomics_pgx_report",
        "filename":    "pharmacology/pharmacogenomics_pgx_report/main.nf",
        "description": (
            "Generates a pharmacogenomics (PGx) clinical report from diplotype data. "
            "Accepts pre-called star alleles for CYP2D6, CYP2C19, CYP2C9, CYP3A5, "
            "SLCO1B1, TPMT, DPYD, UGT1A1, VKORC1, CYP2B6, NUDT15. "
            "Maps activity scores to CPIC phenotype (Poor/Intermediate/Normal/Ultrarapid Metabolizer). "
            "Reports drug-specific dosing recommendations and contraindications per CPIC 2024 guidelines. "
            "Flags actionable drug-gene pairs: dose reductions, contraindications, alternative recommendations. "
            "Modeled after PharmCAT (Sangkuhl et al. 2021) report structure."
        ),
        "annotation":  "PGx clinical report from star allele diplotypes. Input: diplotype JSON. Output: CPIC drug recommendations CSV.",
        "tags":        "pharmacogenomics,PGx,pharmCAT,CPIC,star allele,CYP2D6,CYP2C19,warfarin,clopidogrel,5-FU,diplotype,metabolizer status,drug-gene interaction",
        "domain":      "pharmacology",
        "category":    "Pharmacogenomics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  1,
        "tools_used":  "CPIC 2024 guidelines, PharmGKB annotations, star allele activity scoring",
    },
    # ── P3: hERG / Cardiac Safety ────────────────────────────────────────────
    {
        "name":        "herg_cardiac_safety_qsar",
        "filename":    "pharmacology/herg_cardiac_safety_qsar/main.nf",
        "description": (
            "Predicts hERG potassium channel inhibition IC50 (µM) and QTc prolongation risk "
            "using a physicochemical QSAR model (Aronov 2005; Sanguinetti 2006). "
            "Computes ICH E14/S7B safety margin (hERG IC50_free / Cmax_free) and risk tier "
            "(HIGH/MEDIUM/LOW/MINIMAL). Scans for Nav1.5 structural alerts (class I "
            "antiarrhythmic scaffolds) that compound cardiac liability. "
            "Input: SMILES, optional measured_hERG_IC50_uM, dose_mg, fup. "
            "Output: herg_risk.json, cardiac_safety_summary.csv, nav15_alerts.csv."
        ),
        "annotation":  "hERG IC50 QSAR + QTc safety margin + Nav1.5 alerts. Input: SMILES. Output: herg_risk.json.",
        "tags":        "hERG,cardiac safety,QTc,ICH E14,ICH S7B,Nav1.5,safety pharmacology,arrhythmia,potassium channel,QSAR",
        "domain":      "pharmacology",
        "category":    "Safety Pharmacology",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, QSAR hERG model (Aronov 2005), ICH E14/S7B framework",
    },
    # ── P4: Genotoxicity / Ames ──────────────────────────────────────────────
    {
        "name":        "genotoxicity_ames_prediction",
        "filename":    "pharmacology/genotoxicity_ames_prediction/main.nf",
        "description": (
            "Predicts Ames mutagenicity and genotoxicity potential using a structural alert "
            "library derived from Derek Nexus rules and ICH S2(R1) guidance (Bailey 2005; "
            "Kazius 2005). Covers 3 ICH categories: direct DNA reactants (Category A: nitro "
            "aromatics, primary aromatic amines, nitrosamines, epoxides), indirect mutagens "
            "via metabolic activation (Category B: PAHs, furans, Michael acceptors, azo dyes), "
            "and clastogenic/aneugenic scaffolds (Category C: topo II inhibitors). "
            "Recommends ICH S2(R1)-compliant genotoxicity battery for IND filing. "
            "Input: SMILES. Output: ames_prediction.json, genotox_alerts.csv, ichs2_summary.json."
        ),
        "annotation":  "ICH S2(R1) Ames + genotoxicity structural alerts. Input: SMILES. Output: ames_prediction.json.",
        "tags":        "Ames,genotoxicity,mutagenicity,ICH S2,nitroaromatic,PAH,aromatic amine,DNA damage,structural alert,DEREK,IND",
        "domain":      "pharmacology",
        "category":    "Safety Pharmacology",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "RDKit, Derek Nexus-derived SMARTS alerts, ICH S2(R1), Kazius 2005 QSAR",
    },
    # ── P9: Target Tractability ──────────────────────────────────────────────
    {
        "name":        "target_tractability_scorer",
        "filename":    "drug_discovery/target_tractability_scorer/main.nf",
        "description": (
            "Scores a protein target's tractability for small molecule and biologic drug discovery. "
            "Combines protein family tractability (kinase/GPCR/nuclear receptor = high; "
            "PPI/transcription factor = low), pocket druggability (volume/hydrophobicity from "
            "fpocket heuristics, Edfeldt 2011), ChEMBL data density (Target Development Level: "
            "Tdark/Tbio/Tchem/Tclin, Oprea 2018), and OpenTargets disease association score. "
            "Outputs separate SM and biologic tractability scores (0–1) with tier labels and "
            "modality recommendation. "
            "Input: target_name, protein_class, pocket_volume_A3, chembl_compound_count, "
            "has_crystal_structure, disease_association_score. "
            "Output: tractability_score.json, evidence_table.csv."
        ),
        "annotation":  "SM + biologic tractability scoring. Input: target metadata. Output: tractability_score.json.",
        "tags":        "target tractability,druggability,TDL,Tdark,kinase,GPCR,PPI,pocket volume,OpenTargets,ChEMBL,Oprea 2018",
        "domain":      "drug_discovery",
        "category":    "Target Assessment",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "Oprea TDL 2018, OpenTargets tractability framework, Edfeldt 2011 pocket scoring",
    },
    # ── P5: Pediatric / Pregnancy PBPK ──────────────────────────────────────
    {
        "name":        "pbpk_pediatric_pregnancy",
        "filename":    "pharmacology/pbpk_pediatric_pregnancy/main.nf",
        "description": (
            "Age-stratified PBPK simulation for pediatric dose prediction and pregnancy PK "
            "changes. Applies CYP maturation Hill functions (CYP3A4/2D6/2C9/1A2) from Bjorkman "
            "2005 and Johnson 2006, with WHO-based age-scaled organ volumes and cardiac output "
            "across 10 age groups (neonate to adult). Simulates pregnancy trimester physiology: "
            "plasma volume expansion (+45%), GFR increase (+50% T3), CYP3A4 induction (1.8x T3), "
            "CYP2D6 induction (2x T3), CYP1A2 downregulation (0.5x T3) per Jeong 2012/Anger 2014. "
            "Generates age-adjusted dose recommendations to match adult AUC target. "
            "Input: physicochemical params (MW, logP, CLint, Vss, fup, CYP substrate). "
            "Output: pediatric_pk.csv (10 age groups), pregnancy_pk.csv (5 trimesters), "
            "dose_recommendation.json."
        ),
        "annotation":  "Pediatric CYP maturation PBPK + pregnancy PK changes. Input: drug params. Output: pediatric_pk.csv.",
        "tags":        "pediatric PBPK,pregnancy PK,CYP maturation,dose adjustment,allometric scaling,neonatal,CYP3A4 induction,Bjorkman,Jeong 2012",
        "domain":      "pharmacology",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "SciPy ODE, Bjorkman 2005/Johnson 2006 maturation functions, WHO growth data, Jeong 2012",
    },
    # ── P7: Antibody Developability ──────────────────────────────────────────
    {
        "name":        "antibody_developability",
        "filename":    "pharmacology/antibody_developability/main.nf",
        "description": (
            "In silico developability assessment for antibody and biologic drug candidates. "
            "Predicts: (1) aggregation propensity using CamSol-inspired hydrophobicity patch "
            "scoring (Sormanni 2015) over CDR sequences; (2) deamidation liabilities from "
            "NG/NS/DG motifs in CDRs (Vlasak 2009; Yan 2009); (3) oxidation liabilities at "
            "Met/Trp/Tyr residues (Houde 2011); (4) isoelectric point (pI) via "
            "Henderson-Hasselbalch titration; (5) FcRn-predicted serum half-life from pI "
            "(Deng 2012); (6) viscosity risk for SC formulation. "
            "Input: full_sequence or CDR sequences (HCDR1/2/3, LCDR1/2/3), antibody_format "
            "(IgG1/IgG4/scFv), target_indication. "
            "Output: developability_scores.json, liability_scan.csv."
        ),
        "annotation":  "Antibody aggregation + deamidation + FcRn t½ + pI prediction. Input: CDRs/sequence. Output: developability_scores.json.",
        "tags":        "antibody,developability,aggregation,deamidation,oxidation,FcRn,pI,CamSol,IgG,biologic,CDR,half-life",
        "domain":      "pharmacology",
        "category":    "Biologics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "CamSol proxy (Sormanni 2015), Vlasak 2009 deamidation, Deng 2012 FcRn model",
    },
    # ── P8: HTS Plate QC + Hit Calling ───────────────────────────────────────
    {
        "name":        "hts_plate_qc_hit_calling",
        "filename":    "drug_discovery/hts_plate_qc_hit_calling/main.nf",
        "description": (
            "High-Throughput Screening (HTS) plate quality control and hit identification. "
            "Computes Z-factor and Z'-factor (Zhang 1999) from positive/negative controls. "
            "Normalizes raw signals to percent inhibition/activation. Applies configurable "
            "hit threshold (default ≥50%) with n-sigma statistics. Fits 4-parameter logistic "
            "(4PL/Hill equation) dose-response curves when replicate concentration data are "
            "provided (Sebaugh 2011). "
            "Accepts plate_data_json array of {well, compound_id, signal, is_pos_ctrl, "
            "is_neg_ctrl, concentration_uM} or generates synthetic 96-well demo data. "
            "Output: qc_metrics.json (Z', CV, signal window), hit_list.csv, dose_response_curves.csv."
        ),
        "annotation":  "HTS Z' QC + hit calling + 4PL dose-response fitting. Input: plate JSON. Output: qc_metrics.json, hit_list.csv.",
        "tags":        "HTS,high-throughput screening,Z-factor,hit calling,dose response,4PL,Hill equation,plate QC,Z-prime,IC50",
        "domain":      "drug_discovery",
        "category":    "Hit Discovery",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "SciPy curve_fit, Zhang 1999 Z-factor, Sebaugh 2011 4PL",
    },
    # ── P10: Exposure-Response Modelling ─────────────────────────────────────
    {
        "name":        "exposure_response_modelling",
        "filename":    "pharmacology/exposure_response_modelling/main.nf",
        "description": (
            "Fits Emax/Emin exposure-response (E-R) models to clinical or preclinical PK-PD "
            "data. Supports Emax (sigmoid Hill equation), linear, and power-law E-R models. "
            "Estimates EC50, Emax, Hill coefficient with confidence from SciPy curve_fit. "
            "Computes E-R safety margin (TEC / EC50_target) and provides dose recommendations "
            "to achieve E50, target effect %, and E90. Follows FDA E-R analysis guidance (2019) "
            "for Phase I/II go/no-go decisions and benefit-risk assessment. "
            "Input: er_data_json [{exposure_metric, effect, dose_mg}], er_model, "
            "target_effect_pct, safety_exposure_uM. "
            "Output: er_parameters.json (EC50, Emax, Hill, R²), er_curve.csv, dose_recommendation.json."
        ),
        "annotation":  "Emax Hill E-R model fit + EC50 + safety margin + dose recommendation. Input: PK-PD data. Output: er_parameters.json.",
        "tags":        "exposure response,ER modelling,Emax,EC50,Hill equation,PK-PD,dose optimization,FDA ER guidance,Phase I,benefit-risk",
        "domain":      "pharmacology",
        "category":    "PK-PD",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "SciPy curve_fit, Mager & Jusko 2001, FDA E-R guidance 2019",
    },
    # ── P11: Phase II → III Dose Justification Brief ─────────────────────────
    {
        "name":        "phase2_dose_justification",
        "filename":    "pharmacology/phase2_dose_justification/main.nf",
        "description": (
            "Generates an FDA-format Phase II → Phase III dose justification brief "
            "from upstream exposure-response (E-R) modelling and PopPK outputs. "
            "Computes therapeutic window (EC10–EC90), predicted % responders at each "
            "candidate dose via Monte Carlo log-normal PK variability simulation, "
            "safety margin ratio (AUC_MTD / AUC_efficacious), and Probability of "
            "Technical Success (PTS) using the Lalonde 2007 three-component framework. "
            "Produces a structured JSON report and a plain-text FDA-format narrative "
            "document with four sections matching the FDA 2023 E-R guidance: "
            "§1 E-R relationship (model, fit quality, EC50, Hill), "
            "§2 Dose selection rationale (therapeutic window, candidate dose table), "
            "§3 Population variability and special populations (renal/hepatic/paediatric/elderly), "
            "§4 Benefit-risk conclusion for proposed Phase III dose(s). "
            "Input: er_params_json (from exposure_response_modelling), candidate_doses_mg, "
            "target_effect_pct (default 80%), population_cv_pct (default 40%), compound_name, "
            "optional mtd_auc_ug_L_h (from Phase I PopPK). "
            "Output: dose_justification_brief.json, dose_justification_narrative.txt, "
            "er_dose_summary.csv."
        ),
        "annotation":  (
            "FDA Phase II→III dose justification: TW, % responders, safety margin, PTS. "
            "Input: E-R params JSON + candidate doses. "
            "Output: dose_justification_brief.json, dose_justification_narrative.txt, er_dose_summary.csv."
        ),
        "tags":        (
            "dose justification,Phase II,Phase III,FDA E-R guidance 2023,exposure response,"
            "therapeutic window,EC50,Emax,Hill,probability of technical success,PTS,"
            "safety margin,responders,PopPK,IIV,NDA,BLA,clinical pharmacology,"
            "benefit-risk,dose selection,End-of-Phase meeting,Type B meeting"
        ),
        "domain":      "pharmacology",
        "category":    "Clinical Development",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "txt", "csv"],
        "step_count":  2,
        "tools_used":  (
            "SciPy (Hill inversion, log-normal Monte Carlo), NumPy, "
            "FDA 2023 E-R Guidance, Lalonde 2007 PTS framework, Thomas 2014 Phase II→III priors"
        ),
    },
    # ── CMC: Polymorph Risk + Solid-State Stability ──────────────────────────
    {
        "name":        "polymorph_stability_screening",
        "filename":    "pharmacology/polymorph_stability_screening/main.nf",
        "description": (
            "Pharmaceutical polymorph risk scoring and solid-state stability prediction "
            "for CMC (Chemistry, Manufacturing & Control) package preparation. "
            "Computes: (1) Polymorph risk score (LOW/MEDIUM/HIGH) from H-bond capacity, "
            "rotatable bonds, and conformational flexibility using the Fleming (2010) heuristic "
            "and Blagden/Davey (Chem Soc Rev 2003) structural alerts; "
            "(2) Solid-state stability assessment per ICH Q1A/Q1B — hygroscopicity (PSA + "
            "H-bond features), photostability risk (UV chromophore detection: conjugated "
            "carbonyls, polycyclic aromatics), chemical degradation pathways (hydrolysis of "
            "ester/lactam/amide, oxidation of sulfur/amine/benzylic CH, epimerisation of "
            "chiral centres alpha to carbonyls), and thermal stability (MW + flexibility heuristic); "
            "(3) Excipient compatibility risk — flags Maillard reaction (lactose + primary/secondary "
            "amine), MgSt salt formation with acidic APIs, MCC moisture-catalysed hydrolysis, "
            "and PVP peroxide-driven oxidation; "
            "(4) ICH Q6A-aligned screening protocol recommendation with number of solvents, "
            "temperature points, crystallisation methods, and characterisation battery scaled "
            "to risk tier; "
            "(5) ICH Q1A(R2) accelerated and long-term stability condition recommendations "
            "with packaging guidance and link to the accelerated stability workflow. "
            "Applications: IND/NDA §3.2.S.3 polymorph control strategy, salt/cocrystal "
            "selection, API manufacturing process risk assessment, ICH Q6A documentation. "
            "Input: smiles, drug_name, intended_route (oral/parenteral/topical/inhalation), "
            "excipients (comma-separated). "
            "Output: polymorph_stability_report.json, polymorph_stability_summary.txt "
            "(ICH Q6A narrative), screening_protocol_recommendation.json."
        ),
        "annotation":  (
            "Polymorph risk (Fleming 2010) + ICH Q1A/Q1B stability + excipient compatibility. "
            "Input: SMILES + drug name + route + excipients. "
            "Output: polymorph_stability_report.json, screening_protocol_recommendation.json."
        ),
        "tags":        (
            "polymorph,solid-state,CMC,ICH Q6A,ICH Q1A,ICH Q1B,crystal form,crystal packing,"
            "hygroscopicity,photostability,hydrolysis,oxidation,epimerisation,thermal stability,"
            "excipient compatibility,Maillard,lactose,MgSt,MCC,XRPD,DSC,TGA,DVS,"
            "polymorph screen,solid form screen,salt selection,cocrystal,IND filing,"
            "NDA CMC,drug substance stability,pharmaceutical manufacturing,API stability"
        ),
        "domain":      "pharmacology",
        "category":    "CMC / Solid-State",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["smiles"],
        "output_types":["json", "txt"],
        "step_count":  5,
        "tools_used":  (
            "RDKit (Descriptors, rdMolDescriptors, SMARTS pattern matching), "
            "Fleming 2010 polymorph heuristic, Blagden & Davey 2003 structural alerts, "
            "ICH Q6A Table 1, ICH Q1A(R2) stability conditions, ICH Q1B photostability"
        ),
    },
    # ── P6: Adaptive Trial Design ─────────────────────────────────────────────
    {
        "name":        "adaptive_trial_design",
        "filename":    "drug_discovery/adaptive_trial_design/main.nf",
        "description": (
            "Simulates adaptive clinical trial designs for Phase II/III. "
            "Implements Response-Adaptive Randomization (RAR) via Thompson sampling "
            "(Thall & Wathen 2007) and Multi-Arm Multi-Stage (MAMS) designs with interim "
            "analyses (Royston 2011). Applies O'Brien-Fleming efficacy stopping boundaries "
            "and Pocock futility stopping (Lan & DeMets 1983 alpha/beta spending). "
            "Reports operating characteristics (power, correct arm selection %, early stop "
            "rates, mean N enrolled) from Monte Carlo simulation (default 1000 trials). "
            "Input: n_arms, true_response_rates, n_interim_analyses, alpha, power, n_simulations, "
            "design_type (MAMS | RAR). "
            "Output: adaptive_design.json (OC table), arm_allocation.csv, stopping_boundaries.csv."
        ),
        "annotation":  "MAMS/RAR adaptive trial design simulation. Input: design params. Output: adaptive_design.json (power, OC table).",
        "tags":        "adaptive trial,MAMS,RAR,Thompson sampling,interim analysis,OBrien-Fleming,futility,Phase II,Phase III,dose escalation,operating characteristics",
        "domain":      "drug_discovery",
        "category":    "Clinical Development",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "csv"],
        "step_count":  3,
        "tools_used":  "SciPy, NumPy, Thall & Wathen 2007 RAR, Royston 2011 MAMS, Lan & DeMets 1983",
    },
    # ── P12: Biomarker-Driven Patient Enrichment ─────────────────────────────
    {
        "name":        "biomarker_patient_enrichment",
        "filename":    "pharmacology/biomarker_patient_enrichment/main.nf",
        "description": (
            "Biomarker-driven patient enrichment analysis for the Phase II → III transition. "
            "Identifies predictive biomarkers from Phase II clinical trial data to determine "
            "which patients should be enrolled in the pivotal trial. "
            "Step 1: screens each biomarker via logistic (binary response) or linear "
            "(continuous) regression, reporting OR/HR with 95% CI, p-value, and "
            "FDR-adjusted q-value (Benjamini-Hochberg). "
            "Step 2: finds the optimal cut-point per continuous biomarker using Youden's "
            "J statistic (maximises sensitivity + specificity − 1). "
            "Step 3: computes per-biomarker enrichment metrics — Enrichment Ratio (ER), "
            "Number Needed to Treat (NNT), Predictive Enrichment Factor (PEF, % of "
            "responders captured), and Number Needed to Screen (NNS). "
            "Step 4: performs Phase III power analysis using two-proportion z-test to "
            "compute sample size required with vs without biomarker-based enrichment, "
            "showing absolute patient-count savings. "
            "Output: structured JSON, plain-English regulatory narrative per FDA 2019 "
            "Enrichment Strategies Guidance, and a Phase III sample-size comparison CSV."
        ),
        "annotation":  (
            "Predictive biomarker screening + Youden cut-point + enrichment metrics "
            "(ER, NNT, PEF, NNS) + Phase III sample-size savings. "
            "Input: patient_data_json, response_type, alpha, phase3_power. "
            "Output: biomarker_enrichment_results.json, enrichment_summary.txt, "
            "phase3_sample_size_comparison.csv."
        ),
        "tags":        (
            "biomarker enrichment,predictive biomarker,patient selection,Phase II Phase III,"
            "enrichment ratio,NNT,PEF,NNS,Youden J,cut-point,logistic regression,"
            "FDR correction,Benjamini-Hochberg,sample size,two-proportion z-test,"
            "FDA enrichment strategy,companion diagnostic,CDx,clinical trial design,"
            "precision oncology,biomarker-driven trial,IND,NDA"
        ),
        "domain":      "pharmacology",
        "category":    "Clinical Development",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "txt", "csv"],
        "step_count":  4,
        "tools_used":  (
            "SciPy (logistic/linear regression, z-test), NumPy, "
            "Sargent 2005 JNCI, Simon 2010, FDA Enrichment Strategies Guidance 2019, "
            "Youden 1950, Benjamini & Hochberg 1995 FDR, Fleiss 1981 sample size"
        ),
    },
    # ── P13: PBPK Disease-State (Renal + Hepatic Impairment) ─────────────────
    {
        "name":        "pbpk_disease_state",
        "filename":    "pharmacology/pbpk_disease_state/main.nf",
        "description": (
            "Mechanistic PBPK disease-state submodels for renal and hepatic impairment, "
            "required for all IND/NDA submissions involving renally or hepatically cleared drugs. "
            "Renal model (FDA Guidance 2010 / ICH E7): classifies Normal/Mild/Moderate/Severe/ESRD "
            "by eGFR; scales CLr via power-law (GFR_patient/GFR_normal)^0.75 (Nolin 2010); "
            "corrects fu for hypoalbuminemia and Vd for oedema (hydrophilic drugs, logP<1). "
            "Hepatic model (FDA Guidance 2003, Child-Pugh A/B/C): applies hepatocyte fraction "
            "(0.80/0.60/0.35) and LBF fraction (0.90/0.80/0.65) per class; computes CLH via "
            "well-stirred model (Wilkinson 2005); corrects fu via albumin-mediated binding. "
            "Flags CONTRAINDICATED when AUC_ratio >5. Generates FDA-format '8.6 Renal Impairment' "
            "and '8.7 Hepatic Impairment' label sections and a CTD §5.2.4 (M4S) exposure-ratio "
            "summary table across all impairment grades. "
            "Input: cl_renal_fraction, cl_hepatic_fraction, fu_plasma, vd_lkg, logP, "
            "high_extraction_ratio, drug_name, primary_indication. "
            "Output: disease_state_pk_report.json, specific_populations_label_text.txt, "
            "exposure_ratio_table.csv."
        ),
        "annotation":  (
            "Renal (eGFR power-law) + Hepatic (Child-Pugh well-stirred) PBPK impairment models; "
            "FDA label §8.6/§8.7 generator; CTD §5.2.4 exposure table. "
            "Input: PK fractions + drug params. "
            "Output: disease_state_pk_report.json, specific_populations_label_text.txt, "
            "exposure_ratio_table.csv."
        ),
        "tags":        (
            "renal impairment,hepatic impairment,PBPK disease state,IND NDA submission,"
            "FDA renal guidance 2010,FDA hepatic guidance 2003,ICH E7,Child-Pugh,"
            "eGFR,GFR,CLr scaling,well-stirred model,fu hypoalbuminemia,albumin,"
            "AUC ratio,Cmax ratio,dose adjustment,contraindicated,special populations,"
            "use in specific populations,FDA label language,CTD 5.2.4,M4S,"
            "renal clearance,hepatic clearance,drug label,NDA regulatory,clinical pharmacology,"
            "renal insufficiency,hepatic insufficiency,ESRD dialysis,liver disease"
        ),
        "domain":      "pharmacology",
        "category":    "Pharmacokinetics",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["json"],
        "output_types":["json", "txt", "csv"],
        "step_count":  3,
        "tools_used":  (
            "NumPy, SciPy, "
            "FDA Guidance Renal Impairment 2010, FDA Guidance Hepatic Impairment 2003, "
            "ICH E7, Nolin 2010 CLr power-law, Wilkinson 2005 well-stirred model, "
            "Rowland & Tozer Ch.11-12, Pugh 1973 Child-Pugh, "
            "FDA Use in Specific Populations label templates"
        ),
    },
    # ── P14: Exposure-Response Modeling (scipy Emax/Hill, bootstrap CI) ───────
    {
        "name":        "exposure_response_modeling",
        "filename":    "pharmacology/exposure_response_modeling/main.nf",
        "description": (
            "Fits a sigmoid Emax/Hill exposure-response (E-R) model to patient "
            "concentration-effect (AUC vs effect%) data and produces parameters "
            "that feed directly into phase2_dose_justification. "
            "Chain: nlmixr2_population_pk → exposure_response_modeling → phase2_dose_justification. "
            "Fitting: scipy.optimize.curve_fit (LM/TRR) + bootstrap CI (n=200 replicates). "
            "Outputs ec50_uM, emax_pct, hill coefficient, R², and 95% CI bounds. "
            "Fixed-Emax mode available when Emax is pre-specified (--emax_fixed). "
            "Identifiability check: warns when AUC_max/EC50 < 2.0 (sparse data). "
            "Input: patient_data_csv (columns: patient_id, AUC_uM_h, effect_pct). "
            "Output: er_params.json (ec50_uM, emax_pct, hill, r_squared, 95%CI), "
            "er_curve.csv (predicted E-R curve for plotting). "
            "References: Holford & Sheiner 1982, FDA E-R Guidance 2023."
        ),
        "annotation":  "Emax/Hill E-R fit + bootstrap CI. Input: AUC-effect CSV. Output: er_params.json for phase2_dose_justification.",
        "tags":        "exposure response,Emax,Hill equation,EC50,PK-PD,dose optimization,FDA ER guidance,phase2,bootstrap CI,scipy",
        "domain":      "pharmacology",
        "category":    "PK-PD",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86",
        "input_types": ["csv"],
        "output_types":["json", "csv"],
        "step_count":  2,
        "tools_used":  "SciPy, Holford & Sheiner 1982, FDA E-R Guidance 2023",
    },
    # ── P15: Population PK/PD — nlmixr2 (SAEM/FOCE+, R) ─────────────────────
    {
        "name":        "nlmixr2_population_pk",
        "filename":    "pharmacology/nlmixr2_population_pk/main.nf",
        "description": (
            "Population pharmacokinetic / pharmacodynamic (PopPK/PD) analysis using nlmixr2 "
            "(SAEM + FOCE+, equivalent to Monolix/NONMEM). Validated against NONMEM "
            "(Fidler et al. 2019 CPT:PSP). Open-source, Nextflow-native R container. "
            "Supports 1- and 2-compartment oral/IV models with covariate testing (WT, AGE, CRCL, ALB). "
            "Outputs: parameter_estimates.csv (THETA, OMEGA, SIGMA), "
            "individual_estimates.csv (EBEs), VPC plot, GOF diagnostics. "
            "Individual AUC estimates from this workflow feed directly into "
            "exposure_response_modeling for the full PK→E-R→dose chain. "
            "Input: pk_data_csv (columns: ID, TIME, DV, AMT, EVID, CMT + optional covariates). "
            "Output: popPK_report.html, nlmixr2_results.json (OFV, AIC, RSE%), VPC + GOF PDFs. "
            "References: Fidler et al. 2019, Beal & Sheiner NONMEM, Monolix 2023."
        ),
        "annotation":  "nlmixr2 PopPK SAEM/FOCE+. Input: PK concentration-time CSV. Output: parameter estimates, individual EBEs, VPC.",
        "tags":        "population PK,nlmixr2,NONMEM,SAEM,FOCE,pharmacokinetics,PopPK,covariate,VPC,GOF,IND,NDA,clinical pharmacology",
        "domain":      "pharmacology",
        "category":    "Population PK",
        "docker_image":"399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/r-pharma:x86",
        "input_types": ["csv"],
        "output_types":["html", "csv", "json", "pdf"],
        "step_count":  4,
        "tools_used":  "nlmixr2, rxode2, PKNCA, R 4.3.1",
    },
]


def _hash(name: str, filename: str) -> str:
    return hashlib.sha256(f"{name}:{filename}".encode()).hexdigest()[:16]


def register(db_path: Path, dry_run: bool = False) -> None:
    conn = sqlite3.connect(db_path)
    cur  = conn.cursor()

    added = 0
    skipped = 0

    for wf in WORKFLOWS:
        wf_hash = _hash(wf["name"], wf["filename"])

        cur.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
        if cur.fetchone():
            print(f"  [skip] {wf['name']} already registered")
            skipped += 1
            continue

        # Read main.nf for workflow_json
        nf_path = NF_BASE / wf["filename"]
        nf_content = nf_path.read_text() if nf_path.exists() else ""

        if dry_run:
            print(f"  [dry-run] would register: {wf['name']}")
            added += 1
            continue

        cur.execute("""
            INSERT INTO workflows
                (name, filename, description, annotation, tags, domain,
                 workflow_json, step_count, tools_used, source, format,
                 executable, docker_image, category, workflow_hash, indexed_at,
                 input_types, output_types)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            wf["name"],
            wf["filename"],
            wf["description"],
            wf["annotation"],
            wf["tags"],
            wf["domain"],
            nf_content,                 # store full main.nf content
            wf["step_count"],
            wf["tools_used"],
            "nextflow",
            "nextflow",
            1,                           # executable
            wf["docker_image"],
            wf["category"],
            wf_hash,
            datetime.utcnow().isoformat(),
            json.dumps(wf["input_types"]),
            json.dumps(wf["output_types"]),
        ))
        print(f"  [added]  {wf['name']} (id={cur.lastrowid})")
        added += 1

    if not dry_run:
        # Rebuild FTS index
        cur.execute("INSERT INTO workflows_fts(workflows_fts) VALUES('rebuild')")
        conn.commit()
        print(f"\nFTS index rebuilt.")

    conn.close()
    print(f"\nDone: {added} added, {skipped} skipped.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db",      default=str(REPO_ROOT / "database" / "galaxy_ai_tools.db"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db_path = Path(args.db)
    if not db_path.exists():
        sys.exit(f"DB not found: {db_path}")

    print(f"Registering AI tool workflows into {db_path}")
    register(db_path, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
