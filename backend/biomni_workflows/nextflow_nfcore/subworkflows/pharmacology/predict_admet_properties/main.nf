#!/usr/bin/env nextflow
/*
 * pharmacology/predict_admet_properties
 *
 * Predicts ADMET (Absorption, Distribution, Metabolism, Excretion, Toxicity)
 * properties for a list of compounds using:
 *   1. RDKit molecular descriptors (hERG IC50 estimate, DILI risk) — always runs
 *   2. DeepPurpose MPNN/CNN/Morgan pretrained models (ClinTox, solubility, etc.)
 *      — optional; runs when DeepPurpose is installed in the container.
 *
 * Always produces toxicity_report.json with structured QC-gate-ready fields.
 * nf-core style module generated from tested Galaxy wrapper.
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: aspirin (safe control) + terfenadine (known hERG risk — withdrawn from market)
// Demonstrates QC gate triggering for hERG cardiotoxicity risk.
params.smiles_list = '["CC(=O)OC1=CC=CC=C1C(=O)O", "OC(CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1)(c1ccc(cc1)C(C)(C)C)CC"]'
params.ADMET_model_type = 'MPNN'

process PREDICT_ADMET_PROPERTIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // biomni-admet: dedicated ADMET container (admet-ai/Chemprop, mordred, PyTDC)
    // Starts from biomate-nextflow-base directly — lean, not biomni-tools
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-admet:x86' : 'biomate/biomni-admet:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_admet_properties_results.json"), emit: results
    tuple val(meta), path("predict_admet_properties_output.txt"), emit: output
    tuple val(meta), path("toxicity_report.json"), emit: toxicity_report
    tuple val(meta), path("pk_summary.json"), emit: pk_summary
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SMILES_LIST="${params.smiles_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ADMET_MODEL_TYPE="${params.ADMET_model_type?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper — self-contained implementation
# Phase 1: RDKit structural safety (always runs, no heavy dependencies)
# Phase 2: DeepPurpose MPNN predictions (optional, runs when installed)
import subprocess
import sys
import json
import os
import re

def auto_convert(val):
    if val is None or val == '' or val == 'null':
        return None
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def compute_structural_safety(smiles_list):
    '''
    Estimate toxicity flags from molecular descriptors (RDKit).

    Provides literature-backed heuristic estimates for:
      - hERG IC50 (μM):  quadratic logP model (Sander et al. 2009 J Chem Inf Model
                          49(8):1807; R²=0.52 on N=806 compounds)
      - DILI risk:        Lipophilicity + MW model (Lammert et al. 2010
                          Toxicol Sci 116:536; Fontana et al. 2010 Hepatology)

    Returns worst-case metrics across all compounds, or {} if RDKit unavailable.
    '''
    try:
        from rdkit import Chem
        from rdkit.Chem import Descriptors
    except ImportError:
        return {}

    items = smiles_list if isinstance(smiles_list, list) else [str(smiles_list)]
    compound_results = []

    for smiles in items:
        smiles = str(smiles).strip()
        if not smiles:
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            compound_results.append({
                "smiles": smiles,
                "error": "Invalid SMILES — could not parse structure",
            })
            continue

        logp = Descriptors.MolLogP(mol)
        mw = Descriptors.MolWt(mol)

        # ── hERG IC50 heuristic ──────────────────────────────────────────────
        # Sander et al. 2009 J Chem Inf Model 49(8):1807 quadratic logP model
        # R²=0.52 (vs 0.38 for linear model) on 806-compound dataset
        # Includes parabolic correction for mid-range logP compounds
        # Valid range: logP -2 to 8 (covers most drug-like space)
        log10_ic50 = 1.81 - 0.36 * logp + 0.08 * (logp - 3.5) ** 2
        herg_ic50 = round(max(0.01, 10 ** log10_ic50), 3)

        # ── DILI risk ────────────────────────────────────────────────────────
        # Lammert et al. (2010): LogP > 3 AND daily dose > threshold → DILI risk
        # Without dose information, use LogP + MW as proxy:
        if logp > 4.0 and mw > 400:
            dili_risk = "high"
            dili_prob = round(min(0.90, 0.55 + 0.05 * (logp - 4.0)), 3)
        elif logp > 2.5 or mw > 350:
            dili_risk = "medium"
            dili_prob = round(min(0.70, 0.30 + 0.04 * max(0, logp)), 3)
        else:
            dili_risk = "low"
            dili_prob = round(max(0.05, 0.08 + 0.02 * max(0, logp)), 3)

        compound_results.append({
            "smiles": smiles,
            "logP": round(logp, 2),
            "mw": round(mw, 1),
            "herg_ic50_uM": herg_ic50,
            "dili_risk": dili_risk,
            "dili_probability": dili_prob,
        })

    valid = [r for r in compound_results if "error" not in r]
    if not valid:
        return {}

    min_herg_ic50 = min(r["herg_ic50_uM"] for r in valid)
    worst_dili = max(valid, key=lambda r: r["dili_probability"])

    return {
        "herg_ic50_uM": min_herg_ic50,
        "dili_risk": worst_dili["dili_risk"],
        "dili_probability": worst_dili["dili_probability"],
        "per_compound": compound_results,
    }


def compute_ames_alerts(smiles_input):
    '''
    Ames mutagenicity prediction via structural alerts.

    Kazius et al. 2005 J Med Chem 48:312-320 — 13 principal mechanistic
    classes of mutagens in the Salmonella Ames assay (TA98, TA100, TA1535, TA1537).
    Benigni & Bossa 2011 Chem Rev 111:2507-2536 — expanded alert set.

    Returns ames_positive (bool), ames_probability (0–1), and the list of
    structural alerts triggered. Probability is an estimate from alert severity;
    ICH S2(R1) requires confirmatory experimental testing regardless.
    '''
    try:
        from rdkit import Chem
    except ImportError:
        return {}

    # (alert_name, SMARTS, severity_weight)
    # Weights derived from Kazius 2005 Table 1 sensitivity/specificity data
    ALERTS = [
        ("n_nitroso",               "[NX3]-N=O",                                   0.90),
        ("aromatic_nitro",          "c[N+](=O)[O-]",                               0.85),
        ("primary_aromatic_amine",  "[NH2]c",                                       0.80),
        ("organic_azide",           "[NX2]=[NX2+]=[NX1-]",                         0.80),
        ("azo_aromatic",            "c-[NX2]=[NX2]-c",                             0.70),
        ("alkyl_nitrite",           "[OX2][NX2]=O",                                 0.65),
        ("alkylating_epoxide",      "[O;r3]",                                       0.65),
        ("haloacetyl",              "[F,Cl,Br,I][CH2][CX3]=O",                      0.60),
        ("furan",                   "c1ccoc1",                                      0.60),
        ("beta_lactone",            "C1(=O)CCO1",                                  0.60),
        ("michael_acceptor",        "[CX3]=[CX3][CX3](=O)[#6]",                    0.55),
        ("hydroxamic_acid",         "[CX3](=O)[NX3][OH]",                           0.55),
        ("alpha_haloketone",        "[F,Cl,Br,I][CX4][CX3](=O)",                   0.55),
    ]

    items = smiles_input if isinstance(smiles_input, list) else [smiles_input]
    triggered = []
    alert_lookup = {name: w for name, _s, w in ALERTS}

    for smiles in items:
        smiles = str(smiles).strip()
        if not smiles:
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            continue
        for name, smarts, _w in ALERTS:
            if name in triggered:
                continue
            try:
                pattern = Chem.MolFromSmarts(smarts)
                if pattern and mol.HasSubstructMatch(pattern):
                    triggered.append(name)
            except Exception:
                continue

    if not triggered:
        return {
            "ames_positive": False,
            "ames_probability": 0.10,
            "structural_alerts": [],
            "n_alerts_triggered": 0,
            "ames_method": "kazius_structural_alerts",
        }

    max_w = max(alert_lookup.get(a, 0.5) for a in triggered)
    prob = round(min(0.95, max_w + 0.05 * (len(triggered) - 1)), 3)
    return {
        "ames_positive": True,
        "ames_probability": prob,
        "structural_alerts": triggered,
        "n_alerts_triggered": len(triggered),
        "ames_method": "kazius_structural_alerts",
    }


def predict_admet_properties(smiles_list, ADMET_model_type="MPNN"):
    # ── Phase 1: RDKit structural safety ────────────────────────────────────
    structural_safety = compute_structural_safety(smiles_list)

    # ── Phase 1b: Ames mutagenicity structural alerts ────────────────────────
    ames_result = compute_ames_alerts(smiles_list)

    items = smiles_list if isinstance(smiles_list, list) else [smiles_list]
    per_compound = structural_safety.pop("per_compound", None)

    tox = dict(structural_safety)
    if ames_result:
        tox["ames_positive"] = ames_result.get("ames_positive", False)
        tox["ames_probability"] = ames_result.get("ames_probability", 0.10)
        tox["ames_structural_alerts"] = ames_result.get("structural_alerts", [])
        tox["ames_method"] = ames_result.get("ames_method", "kazius_structural_alerts")

    tox_report = {
        "compounds_assessed": len(items),
        "model_type": ADMET_model_type,
        "estimation_method": "rdkit_descriptors",
        "toxicity": tox,
    }
    if per_compound:
        tox_report["per_compound"] = per_compound

    research_log = ""

    # ── Phase 2: ADMET-AI (Chemprop-backed, bundled pre-trained models) ────
    # Swanson et al. 2023, Bioinformatics. doi:10.1093/bioinformatics/btae416
    # 41 TDC ADMET endpoints; AUROC >0.85 on 20/31 classification tasks.
    # Models ship inside the admet-ai package — no separate download.
    try:
        from admet_ai import ADMETModel

        model = ADMETModel()
        valid_smiles = [s for s in items if s and s.strip()]
        df = model.predict(smiles=valid_smiles)

        # ADMET-AI column → BioMate key mapping (TDC canonical names)
        _COL = {
            'hERG':                              'hERG_prob',
            'DILI':                              'DILI_prob',
            'PPBR_AZ':                           'ppbr_pct',
            'Caco2_Wang':                        'caco2_logPapp',
            'HIA_Hou':                           'hia_prob',
            'BBB_Martins':                       'bbb_prob',
            'Bioavailability_Ma':                'oral_bioavailability_prob',
            'Pgp_Broccatelli':                   'pgp_inhibitor_prob',
            'CYP2C19_Veith':                     'cyp2c19_inhibitor_prob',
            'CYP2D6_Veith':                      'cyp2d6_inhibitor_prob',
            'CYP3A4_Substrate_CarbonMangels':    'cyp3a4_substrate_prob',
            'CYP2C9_Veith':                      'cyp2c9_inhibitor_prob',
            'CYP1A2_Veith':                      'cyp1a2_inhibitor_prob',
            'Solubility_AqSolDB':                'aqueous_solubility_log',
            'Lipophilicity_AstraZeneca':         'lipophilicity_logD',
            'HalfLife_Obach':                    'half_life_h',
            'Clearance_Hepatocyte_AZ':           'hepatocyte_clearance_uLminmg',
            'LD50_Zhu':                          'ld50_log_mol_kg',
            'ClinTox':                           'clintox_prob',
        }

        per_compound_admet = []
        research_log = (
            "ADMET-AI Predictions (Chemprop-RDKit; Swanson et al. 2023 Bioinformatics)\\n"
            + "=" * 65 + "\\n"
        )

        for smiles_val, row in zip(valid_smiles, df.itertuples(index=False)):
            compound = {'smiles': smiles_val}
            for admet_col, bm_key in _COL.items():
                val = getattr(row, admet_col, None)
                if val is not None:
                    try:
                        compound[bm_key] = round(float(val), 4)
                    except (ValueError, TypeError):
                        pass
            per_compound_admet.append(compound)

            research_log += f"\\nCompound: {smiles_val}\\n"
            for label, key, fmt in [
                ("hERG inhibition",       "hERG_prob",               ".3f"),
                ("DILI probability",      "DILI_prob",               ".3f"),
                ("Plasma protein bind %", "ppbr_pct",                ".1f"),
                ("Caco-2 logPapp",        "caco2_logPapp",           ".3f"),
                ("BBB penetration",       "bbb_prob",                ".3f"),
                ("Oral bioavailability",  "oral_bioavailability_prob",".3f"),
                ("CYP2D6 inhibitor",      "cyp2d6_inhibitor_prob",   ".3f"),
                ("CYP3A4 substrate",      "cyp3a4_substrate_prob",   ".3f"),
                ("ClinTox",               "clintox_prob",            ".3f"),
                ("Half-life (h)",         "half_life_h",             ".1f"),
            ]:
                v = compound.get(key)
                if v is not None:
                    research_log += f"  {label:<28}: {v:{fmt}}\\n"
            research_log += "-" * 40 + "\\n"

        # Update toxicity_report with ADMET-AI results (override heuristics)
        if per_compound_admet:
            worst_herg    = max(per_compound_admet, key=lambda x: x.get('hERG_prob',    0) or 0)
            worst_dili    = max(per_compound_admet, key=lambda x: x.get('DILI_prob',    0) or 0)
            worst_clintox = max(per_compound_admet, key=lambda x: x.get('clintox_prob', 0) or 0)

            herg_p    = worst_herg.get('hERG_prob',    0) or 0
            dili_p    = worst_dili.get('DILI_prob',    0) or 0
            clintox_p = worst_clintox.get('clintox_prob', 0) or 0

            tox_report["toxicity"]["hERG_probability"]   = round(herg_p, 3)
            tox_report["toxicity"]["clintox_probability"] = round(clintox_p, 3)

            # hERG: TDC defines positive as IC50 < 10 µM
            # Convert probability back to approximate IC50 (odds = P/(1-P))
            if herg_p > 0.01:
                ic50_est = round(10.0 * (1.0 - herg_p) / herg_p, 2)
                tox_report["toxicity"]["herg_ic50_uM"] = max(0.01, min(ic50_est, 10000.0))

            # DILI: override heuristic when ADMET-AI gives clearer signal
            if dili_p >= 0.65:
                tox_report["toxicity"]["dili_risk"]        = "high"
                tox_report["toxicity"]["dili_probability"] = round(dili_p, 3)
            elif dili_p >= 0.40 and tox_report["toxicity"].get("dili_risk") != "high":
                tox_report["toxicity"]["dili_risk"]        = "medium"
                tox_report["toxicity"]["dili_probability"] = round(dili_p, 3)

            # PPBR from ADMET-AI (Chemprop MAE ~8.4% vs Lobell 2003 heuristic ~15-20%)
            ppbr_vals = [c.get('ppbr_pct') for c in per_compound_admet
                         if c.get('ppbr_pct') is not None]
            if ppbr_vals:
                tox_report["toxicity"]["ppbr_pct_admet_ai"] = round(max(ppbr_vals), 1)

            tox_report["per_compound_admet_ai"] = per_compound_admet
            tox_report["estimation_method"]     = "admet_ai_chemprop"

            # Phase-1 per_compound rows still carry RDKit heuristic DILI; ADMET-AI
            # overwrites the aggregate `toxicity` block above — sync each compound so
            # dashboards and auditors do not see "high" in `toxicity` vs "low" in
            # `per_compound` for the same SMILES when Chemprop DILI_prob is high.
            def _dili_bucket_from_prob(dp):
                dp = float(dp)
                if dp >= 0.65:
                    return "high", round(dp, 3)
                if dp >= 0.40:
                    return "medium", round(dp, 3)
                return "low", round(dp, 3)

            for pc in tox_report.get("per_compound") or []:
                smi = pc.get("smiles")
                if not smi:
                    continue
                match = next(
                    (x for x in per_compound_admet if x.get("smiles") == smi),
                    None,
                )
                if not match or match.get("DILI_prob") is None:
                    continue
                dr, dpr = _dili_bucket_from_prob(match["DILI_prob"])
                pc["dili_risk"] = dr
                pc["dili_probability"] = dpr
                pc["dili_source"] = "admet_ai"

            tox_report["toxicity"]["dili_aggregation"] = "worst_compound_in_panel"

    except ImportError:
        research_log = (
            "ADMET-AI not available — using RDKit structural safety estimates (Phase 1 only).\\n"
            "Container: ensure biomni-admet:x86 is used for Chemprop-backed predictions.\\n"
        )
    except Exception as _admet_err:
        research_log = f"ADMET-AI error: {_admet_err}\\nFalling back to RDKit structural estimates.\\n"
        print(f"ADMET-AI error: {_admet_err}", file=sys.stderr)

    # ── Always write toxicity_report.json ───────────────────────────────────
    with open("toxicity_report.json", "w") as f:
        json.dump(tox_report, f, indent=2, default=str)

    return research_log if research_log else "Structural safety estimates computed. See toxicity_report.json."


def compute_pk_properties(smiles_list):
    '''
    Predict PK properties for use in downstream PBPK workflows.

    Produces best-available estimates using:
      - fu_plasma:         Lobell & Sivarajah 2003 J Med Chem (PPB sigmoid vs logP)
                           fu = 1 / (1 + 10^(0.92*logP - 1.54)); or DeepPurpose PPBR if available
      - cl_renal_fraction: BCS/logP heuristic (Benet 2011 BCS; Custodio 2008 Pharm Res)
      - vd_lkg:            Lombardo 2002 J Med Chem model: log(Vd) = 0.45*logP − 0.46*(MW/1000) + 0.11

    These are PREDICTED values for hypothesis generation only.
    Experimental measurement is required for regulatory submissions.
    '''
    import re as _re

    try:
        from rdkit import Chem
        from rdkit.Chem import Descriptors
        _HAS_RDKIT = True
    except ImportError:
        _HAS_RDKIT = False

    _AW = {'C': 12.011, 'N': 14.007, 'O': 15.999, 'S': 32.06,
           'F': 19.00, 'P': 30.97, 'I': 126.9, 'B': 10.81}
    _AW2 = {'Cl': 35.45, 'Br': 79.9, 'Si': 28.09}

    def _smiles_logp_mw(smi):
        '''Rough logP and MW from SMILES when RDKit unavailable.
        Uses Crippen-inspired atomic contributions (simplified).
        '''
        # MW by atom type
        mw = 0.0
        i = 0
        while i < len(smi):
            if i+1 < len(smi) and smi[i:i+2] in _AW2:
                mw += _AW2[smi[i:i+2]]; i += 2
            elif smi[i] in _AW:
                mw += _AW[smi[i]]; i += 1
            else:
                i += 1
        mw += mw * 0.08   # rough H correction
        # logP: C/halogen lipophilic, N/O/P hydrophilic (Ghose-Crippen sign)
        n_C  = smi.count('C') + smi.count('c')
        n_N  = smi.count('N') + smi.count('n')
        n_O  = smi.count('O') + smi.count('o')
        n_Cl = smi.count('Cl')
        n_F  = smi.count('F')
        n_S  = smi.count('S') + smi.count('s')
        logp = 0.5 * n_C - 1.0 * n_N - 1.0 * n_O + 0.5 * n_Cl + 0.14 * n_F + 0.4 * n_S
        return round(logp, 2), round(mw, 1)

    items = smiles_list if isinstance(smiles_list, list) else [smiles_list]
    compound_pks = []

    for smiles in items:
        smiles = str(smiles).strip()
        if _HAS_RDKIT:
            mol = Chem.MolFromSmiles(smiles)
            if mol is None:
                compound_pks.append({"smiles": smiles, "error": "invalid SMILES"})
                continue
            logp = Descriptors.MolLogP(mol)
            mw   = Descriptors.MolWt(mol)
            _src = "rdkit"
        else:
            logp, mw = _smiles_logp_mw(smiles)
            _src = "smiles_heuristic"

        # fu_plasma: Lobell & Sivarajah 2003 sigmoid model (N=255 compounds)
        #   PPB (%) = 100 / (1 + 10^(-(0.92*logP - 1.54)))
        #   fu = 1 - PPB/100
        import math
        try:
            fu = round(1.0 / (1.0 + 10.0 ** (0.92 * logp - 1.54)), 4)
            fu = max(0.01, min(0.99, fu))   # clamp to [0.01, 0.99]
        except Exception:
            fu = None

        # cl_renal_fraction: logP heuristic (BCS classification basis)
        #   Hydrophilic (logP<0): renally dominant; lipophilic: hepatically dominant
        if logp < 0:
            clr_frac = 0.70
        elif logp < 2:
            clr_frac = 0.40
        elif logp < 4:
            clr_frac = 0.15
        else:
            clr_frac = 0.05

        # vd_lkg: Lombardo 2002 J Med Chem 45:2867
        #   log(Vd [L/kg]) = 0.45*logP − 0.46*(MW/1000) + 0.11
        try:
            vd = round(10.0 ** (0.45 * logp - 0.46 * (mw / 1000.0) + 0.11), 3)
            vd = max(0.04, min(100.0, vd))  # physiological range
        except Exception:
            vd = None

        compound_pks.append({
            "smiles": smiles,
            "logP": round(logp, 3),
            "mw_Da": round(mw, 1),
            "fu_plasma_predicted": fu,
            "cl_renal_fraction_estimated": clr_frac,
            "vd_lkg_estimated": vd,
            "descriptor_source": _src,
        })

    valid = [c for c in compound_pks if "error" not in c]
    if not valid:
        return {"status": "no_valid_compounds", "fu_plasma": None, "cl_renal_fraction": None, "vd_lkg": None}

    # Worst-case / representative values (use compound with highest risk = lowest fu)
    worst = min(valid, key=lambda x: x.get("fu_plasma_predicted") or 1.0)
    _method = ("rdkit_lobell2003_ppb + lombardo2002_vd + bcs_logp_clr" if _HAS_RDKIT
               else "smiles_heuristic_logp + lobell2003_ppb + lombardo2002_vd + bcs_logp_clr")
    return {
        "status": "predicted",
        "estimation_method": _method,
        "disclaimer": (
            "These values are computational predictions for hypothesis generation only. "
            "fu_plasma by Lobell & Sivarajah 2003 J Med Chem (RMSE~0.15 log units on training set); "
            "cl_renal_fraction by BCS/logP heuristic (directional only); "
            "vd_lkg by Lombardo 2002 (RMSE~0.48 log-units). "
            "All values require experimental confirmation before use in regulatory PBPK submissions."
        ),
        "references": [
            "Lobell M, Sivarajah V. J Med Chem 2003;46(20):4296-4303",
            "Lombardo F et al. J Med Chem 2002;45(13):2867-2876",
            "Benet LZ et al. Pharm Res 2011;28:1774-1791 (BCS classification)",
        ],
        "fu_plasma": worst.get("fu_plasma_predicted"),
        "cl_renal_fraction": worst.get("cl_renal_fraction_estimated"),
        "cl_hepatic_fraction": round(1.0 - worst.get("cl_renal_fraction_estimated", 0) - 0.05, 2),
        "vd_lkg": worst.get("vd_lkg_estimated"),
        "logP": worst.get("logP"),
        "mw_Da": worst.get("mw_Da"),
        "per_compound": compound_pks,
    }


# ── Execute ──────────────────────────────────────────────────────────────────
try:
    result = predict_admet_properties(
        smiles_list=auto_convert(os.environ.get("PARAM_SMILES_LIST", "")),
        ADMET_model_type=auto_convert(os.environ.get("PARAM_ADMET_MODEL_TYPE", "MPNN")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# ── Save main results JSON ───────────────────────────────────────────────────
output_data = {
    "success": success,
    "function": "predict_admet_properties",
    "domain": "pharmacology",
}
if success:
    output_data["result"] = str(result) if not isinstance(result, (dict, list)) else result
else:
    output_data["error"] = error_msg

with open("predict_admet_properties_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# ── Save human-readable output ───────────────────────────────────────────────
NL = chr(10)
with open("predict_admet_properties_output.txt", "w") as f:
    f.write("Biomni: Predict ADMET Properties" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

# ── Guarantee toxicity_report.json always exists ─────────────────────────────
if not os.path.exists("toxicity_report.json"):
    with open("toxicity_report.json", "w") as f:
        json.dump({
            "compounds_assessed": 0,
            "toxicity": {},
            "note": "No structural data available — check SMILES input",
        }, f, indent=2)

# ── PK property predictions for downstream PBPK workflows ────────────────────
smiles_input = auto_convert(os.environ.get("PARAM_SMILES_LIST", ""))
try:
    pk_summary = compute_pk_properties(smiles_input)
    # Upgrade fu_plasma with ADMET-AI PPBR when available (much better than Lobell heuristic)
    # tox_report["toxicity"]["ppbr_pct_admet_ai"] is set by Phase 2 when ADMET-AI ran
    if os.path.exists("toxicity_report.json"):
        try:
            with open("toxicity_report.json") as _tf:
                _tr = json.load(_tf)
            ppbr_ai = _tr.get("toxicity", {}).get("ppbr_pct_admet_ai")
            if ppbr_ai is not None:
                fu_from_ai = round(max(0.01, min(0.99, 1.0 - ppbr_ai / 100.0)), 4)
                pk_summary["fu_plasma"]    = fu_from_ai
                pk_summary["fu_source"]    = "admet_ai_chemprop_ppbr"
                pk_summary["ppbr_pct"]     = round(ppbr_ai, 1)
                pk_summary["estimation_method"] = pk_summary.get("estimation_method","").replace(
                    "smiles_heuristic_logp", "admet_ai_ppbr").replace(
                    "rdkit_lobell2003_ppb", "admet_ai_ppbr")
        except Exception:
            pass
except Exception as pk_err:
    pk_summary = {"status": "error", "error": str(pk_err),
                  "fu_plasma": None, "cl_renal_fraction": None, "vd_lkg": None}

with open("pk_summary.json", "w") as f:
    json.dump(pk_summary, f, indent=2, default=str)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "predict_admet_properties"
    END_VERSIONS
    """
}

workflow PREDICT_ADMET_PROPERTIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    PREDICT_ADMET_PROPERTIES(ch_input)

    emit:
    results        = PREDICT_ADMET_PROPERTIES.out.results
    output         = PREDICT_ADMET_PROPERTIES.out.output
    toxicity_report = PREDICT_ADMET_PROPERTIES.out.toxicity_report
    pk_summary     = PREDICT_ADMET_PROPERTIES.out.pk_summary
    versions       = PREDICT_ADMET_PROPERTIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_ADMET_PROPERTIES_WORKFLOW(ch_input)

    PREDICT_ADMET_PROPERTIES_WORKFLOW.out.output.view { "Output: $it" }
}
