#!/usr/bin/env nextflow
/*
 * drug_discovery/transporter_ddi_pgp_bcrp
 *
 * Transporter-Mediated Drug-Drug Interaction Assessment
 * P-glycoprotein (P-gp/ABCB1), BCRP (ABCG2), OATP1B1/1B3, OCT1/2, OAT1/3, MATE1/2
 *
 * Covers FDA 2020 DDI Guidance + EMA 2012 DDI Guideline transporter section:
 *   - P-gp inhibition: R-value criterion (1 + Igut/Ki > 10 or 1 + Iin/Ki > 1.1)
 *   - BCRP inhibition: R2-value criterion (1 + Igut/Ki > 10)
 *   - OATP1B1/1B3 inhibition: R-value (1 + [I]/IC50 > 1.1)
 *   - OCT/OAT/MATE: basic risk flag (1 + [I]u,max/IC50 > 1.1)
 *   - Substrate assessment: efflux ratio (ER > 2 → P-gp substrate; > 2 → BCRP substrate)
 *   - GI concentration estimate: Igut = Dose / 250 mL (FDA default volume)
 *
 * Clinical study triggers per FDA 2020:
 *   P-gp/BCRP inhibition R > 10 (gut) → clinical DDI study with digoxin/rosuvastatin probe
 *   OATP R > 1.1 → clinical study with rosuvastatin/atorvastatin probe
 *
 * Inputs use IC50 values from in vitro vesicle or cell-based assays
 * (Caco-2 bidirectional assay for ER; LLC-PK1/MDCK-MDR1 for P-gp substrate)
 */

nextflow.enable.dsl = 2

params.compound_name        = 'test_compound'
params.smiles               = null
params.molecular_weight     = null          // g/mol (required for Igut calculation)
params.dose_mg              = null          // clinical dose in mg (for Igut = dose/250mL)
params.cmax_total_ng_ml     = null          // total plasma Cmax at therapeutic dose (ng/mL)
params.fu_p                 = 0.1           // unbound plasma fraction
params.fa                   = 0.9           // fraction absorbed (for Iin max)

// In vitro IC50 values (µM) - null = not tested
params.pgp_ic50_um          = null          // P-gp inhibition IC50 (vesicle ATPase or substrate probe)
params.bcrp_ic50_um         = null          // BCRP inhibition IC50
params.oatp1b1_ic50_um      = null          // OATP1B1 inhibition IC50
params.oatp1b3_ic50_um      = null          // OATP1B3 inhibition IC50
params.oct1_ic50_um         = null          // OCT1 inhibition IC50
params.oct2_ic50_um         = null          // OCT2 inhibition IC50
params.oat1_ic50_um         = null          // OAT1 inhibition IC50
params.oat3_ic50_um         = null          // OAT3 inhibition IC50
params.mate1_ic50_um        = null          // MATE1 inhibition IC50
params.mate2k_ic50_um       = null          // MATE2-K inhibition IC50

// Efflux ratio from Caco-2 or MDCK-MDR1 bidirectional assay
params.efflux_ratio_pgp     = null          // Papp B→A / Papp A→B
params.efflux_ratio_bcrp    = null          // from MDCK-BCRP cell line

params.outdir               = 'results/transporter_ddi'

process CALCULATE_R_VALUES {
    tag "${params.compound_name}"
    publishDir "${params.outdir}", mode: 'copy'

    output:
    path 'transporter_r_values.json'
    path 'transporter_ddi_flags.tsv'

    script:
    def mw_val   = params.molecular_weight ?: 400.0
    def dose_val = params.dose_mg ?: 100.0
    def cmax_val = params.cmax_total_ng_ml ?: 200.0
    """
    python3 - << 'PYEOF'
import json, math

compound = "${params.compound_name}"
mw       = float("${mw_val}")
dose_mg  = float("${dose_val}")
cmax_ng  = float("${cmax_val}")
fu_p     = float("${params.fu_p}")
fa       = float("${params.fa}")

# Convert Cmax ng/mL → µM
cmax_um = (cmax_ng / mw) * 1000.0

# Unbound Cmax (for uptake transporter R-value)
cmax_u_um = cmax_um * fu_p

# Igut (intestinal inhibitor concentration) = Dose / 250 mL per FDA 2020 §2.3.1
dose_umol = (dose_mg / mw) * 1e6
igut_um   = dose_umol / 250.0  # mL → µM (= nmol/mL = µM assuming density ≈1)

# Iin,max (portal vein concentration for hepatic uptake transporters)
# FDA 2020: Iin,max = fu_p * (Fa * ka * Dose / Qh) + Cmax_u
# Approximate with ka ≈ 0.1/min, Qh = 1500 mL/min
ka    = 0.1
Qh    = 1500.0
iin_max_um = fu_p * (fa * ka * (dose_mg / mw * 1e6) / Qh) + cmax_u_um

# Parse IC50 values (null → not tested → skip)
def parse_ic50(val_str):
    s = val_str.strip().lower()
    if s in ('null', '', 'none', 'not tested'):
        return None
    try:
        return float(s)
    except ValueError:
        return None

transporters = {
    "P-gp (ABCB1)": {
        "ic50": parse_ic50("${params.pgp_ic50_um}"),
        "i_inhibitor": igut_um,        # gut epithelium
        "i_label": "Igut",
        "r_threshold": 10.0,           # FDA 2020 Table 4: basic R ≥ 10 → clinical study
        "study_trigger": "clinical DDI study (probe: digoxin or fexofenadine)",
        "also_check_iin": True,
        "iin_threshold": 1.1,
    },
    "BCRP (ABCG2)": {
        "ic50": parse_ic50("${params.bcrp_ic50_um}"),
        "i_inhibitor": igut_um,
        "i_label": "Igut",
        "r_threshold": 10.0,
        "study_trigger": "clinical DDI study (probe: rosuvastatin or sulfasalazine)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OATP1B1 (SLCO1B1)": {
        "ic50": parse_ic50("${params.oatp1b1_ic50_um}"),
        "i_inhibitor": iin_max_um,     # portal vein / hepatic inlet
        "i_label": "Iin,max",
        "r_threshold": 1.1,            # FDA 2020: R ≥ 1.1 → clinical study
        "study_trigger": "clinical DDI study (probe: rosuvastatin or atorvastatin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OATP1B3 (SLCO1B3)": {
        "ic50": parse_ic50("${params.oatp1b3_ic50_um}"),
        "i_inhibitor": iin_max_um,
        "i_label": "Iin,max",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: cholecystokinin octapeptide or pitavastatin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OCT1 (SLC22A1)": {
        "ic50": parse_ic50("${params.oct1_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: metformin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OCT2 (SLC22A2)": {
        "ic50": parse_ic50("${params.oct2_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: metformin or creatinine)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OAT1 (SLC22A6)": {
        "ic50": parse_ic50("${params.oat1_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: tenofovir or furosemide)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "OAT3 (SLC22A8)": {
        "ic50": parse_ic50("${params.oat3_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: furosemide or benzylpenicillin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "MATE1 (SLC47A1)": {
        "ic50": parse_ic50("${params.mate1_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: metformin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
    "MATE2-K (SLC47A2)": {
        "ic50": parse_ic50("${params.mate2k_ic50_um}"),
        "i_inhibitor": cmax_u_um,
        "i_label": "Cmax,u",
        "r_threshold": 1.1,
        "study_trigger": "clinical DDI study (probe: metformin)",
        "also_check_iin": False,
        "iin_threshold": None,
    },
}

results = {}
flags = []
for name, t in transporters.items():
    ic50 = t["ic50"]
    if ic50 is None:
        results[name] = {"status": "not_tested", "r_value": None, "flag": False}
        continue
    I = t["i_inhibitor"]
    R = 1.0 + I / ic50
    flag = R >= t["r_threshold"]
    r_iin = None
    flag_iin = False
    if t["also_check_iin"]:
        r_iin = 1.0 + iin_max_um / ic50
        flag_iin = r_iin >= t["iin_threshold"]
    overall_flag = flag or flag_iin
    results[name] = {
        "ic50_um": ic50,
        "inhibitor_conc_um": round(I, 4),
        "inhibitor_type": t["i_label"],
        "r_value": round(R, 3),
        "r_threshold": t["r_threshold"],
        "flag": overall_flag,
        "r_iin": round(r_iin, 3) if r_iin else None,
        "clinical_study_required": overall_flag,
        "probe_substrate": t["study_trigger"] if overall_flag else None,
    }
    if overall_flag:
        flags.append({"transporter": name, "R": round(R, 3), "threshold": t["r_threshold"],
                      "action": t["study_trigger"]})

# Substrate assessment
substrate_flags = {}
efflux_pgp = "${params.efflux_ratio_pgp}".strip()
if efflux_pgp not in ('null', '', 'none'):
    er = float(efflux_pgp)
    substrate_flags["P-gp_substrate"] = {
        "efflux_ratio": er,
        "is_substrate": er > 2.0,
        "note": "ER > 2 → P-gp substrate; monitor CNS penetration and oral bioavailability"
    }
efflux_bcrp = "${params.efflux_ratio_bcrp}".strip()
if efflux_bcrp not in ('null', '', 'none'):
    er = float(efflux_bcrp)
    substrate_flags["BCRP_substrate"] = {
        "efflux_ratio": er,
        "is_substrate": er > 2.0,
        "note": "ER > 2 → BCRP substrate; may affect oral absorption and biliary excretion"
    }

out = {
    "compound": compound,
    "concentrations": {
        "cmax_total_ng_ml": cmax_ng,
        "cmax_um": round(cmax_um, 4),
        "cmax_u_um": round(cmax_u_um, 4),
        "igut_um": round(igut_um, 4),
        "iin_max_um": round(iin_max_um, 4),
    },
    "transporter_inhibition": results,
    "substrate_assessment": substrate_flags,
    "clinical_study_flags": flags,
    "total_flags": len(flags),
    "fda_guidance": "FDA 2020 Drug Interaction Studies Guidance",
    "ema_guidance": "EMA 2012 DDI Guideline",
}

with open("transporter_r_values.json", "w") as f:
    json.dump(out, f, indent=2)

with open("transporter_ddi_flags.tsv", "w") as f:
    f.write("transporter\\tIC50_uM\\tI_uM\\tR_value\\tthreshold\\tflag\\taction\\n")
    for name, r in results.items():
        if r.get("status") == "not_tested":
            f.write("{}\\tnot_tested\\t-\\t-\\t-\\tFALSE\\t-\\n".format(name))
        else:
            action = r.get("probe_substrate") or "-"
            f.write("{}\\t{}\\t{}\\t{}\\t{}\\t{}\\t{}\\n".format(name, r['ic50_um'], r['inhibitor_conc_um'], r['r_value'], r['r_threshold'], r['flag'], action))

print("Transporter DDI complete: {} flags requiring clinical study".format(len(flags)))
for fl in flags:
    print("  FLAGGED: {} R={} >= {} → {}".format(fl['transporter'], fl['R'], fl['threshold'], fl['action']))
PYEOF
    """
}

process GENERATE_TRANSPORTER_REPORT {
    tag "${params.compound_name}"
    publishDir "${params.outdir}", mode: 'copy'

    input:
    path r_values_json

    output:
    path 'transporter_ddi_report.json'
    path 'transporter_ddi_summary.txt'

    script:
    """
    python3 - << 'PYEOF'
import json

with open("${r_values_json}") as f:
    data = json.load(f)

flags = data["clinical_study_flags"]
n_tested = sum(1 for v in data["transporter_inhibition"].values() if v.get("status") != "not_tested")
n_flagged = len(flags)

if n_flagged == 0:
    overall = "GREEN - no transporter DDI risk above FDA threshold"
elif n_flagged <= 2:
    overall = "YELLOW - {} transporter(s) flagged; clinical DDI studies required".format(n_flagged)
else:
    overall = "RED - {} transporters flagged; extensive clinical DDI package required".format(n_flagged)

report = {
    "compound": data["compound"],
    "overall_assessment": overall,
    "transporters_tested": n_tested,
    "transporters_flagged": n_flagged,
    "clinical_study_flags": flags,
    "substrate_assessment": data["substrate_assessment"],
    "key_concentrations": data["concentrations"],
    "guidance": [data["fda_guidance"], data["ema_guidance"]],
}

with open("transporter_ddi_report.json", "w") as f:
    json.dump(report, f, indent=2)

summary = (
    "Transporter DDI Assessment - " + data['compound'] + "\\n" +
    "=" * 50 + "\\n" +
    "Overall: " + overall + "\\n\\n" +
    "Concentrations used:\\n" +
    "  Cmax,total: " + str(data['concentrations']['cmax_total_ng_ml']) + " ng/mL (" + str(round(data['concentrations']['cmax_um'], 4)) + " uM)\\n" +
    "  Cmax,u: " + str(round(data['concentrations']['cmax_u_um'], 4)) + " uM\\n" +
    "  Igut: " + str(round(data['concentrations']['igut_um'], 4)) + " uM (FDA 2020: dose/250mL)\\n" +
    "  Iin,max: " + str(round(data['concentrations']['iin_max_um'], 4)) + " uM\\n\\n" +
    "Clinical Study Triggers:\\n"
)
if flags:
    for fl in flags:
        summary += "  FLAGGED: {} R={} ≥ {} → {}\\n".format(fl['transporter'], fl['R'], fl['threshold'], fl['action'])
else:
    summary += "  None - all R-values below FDA thresholds\\n"

if data["substrate_assessment"]:
    summary += "\\nSubstrate Assessment:\\n"
    for k, v in data["substrate_assessment"].items():
        substrate_flag = "SUBSTRATE" if v["is_substrate"] else "non-substrate"
        summary += "  {}: ER={} → {}. {}\\n".format(k, round(v['efflux_ratio'], 1), substrate_flag, v['note'])

with open("transporter_ddi_summary.txt", "w") as f:
    f.write(summary)
print(summary)
PYEOF
    """
}

workflow {
    CALCULATE_R_VALUES()
    GENERATE_TRANSPORTER_REPORT(CALCULATE_R_VALUES.out[0])
}
