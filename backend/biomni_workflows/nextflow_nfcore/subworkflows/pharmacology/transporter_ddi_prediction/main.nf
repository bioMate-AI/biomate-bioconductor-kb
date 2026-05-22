#!/usr/bin/env nextflow
/*
 * pharmacology/transporter_ddi_prediction
 *
 * Predicts substrate and inhibitor status for 8 FDA-mandated drug transporters
 * (OATP1B1, OATP1B3, P-gp, BCRP, MATE1, MATE2-K, OAT1, OCT2).
 * Calculates static DDI AUC ratios per FDA DDI Guidance 2020 basic model.
 * Flags which transporters require in vitro or clinical DDI studies.
 *
 * Transporter substrate/inhibitor models: rule-based from physicochemical
 * descriptors + SMARTS (Karlgren et al. 2012; Brouwer et al. 2013 review;
 * Giacomini et al. Nat Rev Drug Discov 2010).
 *
 * Input:  SMILES, Cmax_uM (unbound plasma)
 * Output: transporter_results.csv, static_ddi_model.csv, regulatory_summary.json
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.smiles_list   = '["CC(C)(C)OC(=O)N1CC(O)(CC1)c1ccc(cc1)C(F)(F)F"]'  // example
params.Cmax_uM       = '1.0'
params.transporters  = 'all'  // all | OATP1B1,Pgp,BCRP,...

process TRANSPORTER_DDI_PREDICTION {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("transporter_ddi_results.json"),   emit: results
    tuple val(meta), path("transporter_ddi_output.txt"),     emit: output
    tuple val(meta), path("transporter_results.csv"),        emit: transporter_csv
    tuple val(meta), path("static_ddi_model.csv"),           emit: ddi_model
    tuple val(meta), path("regulatory_summary.json"),        emit: regulatory
    path "versions.yml",                                     emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_CMAX_UM='${params.Cmax_uM}'
    export PARAM_TRANSPORTERS='${params.transporters}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen

def auto_convert(v):
    if v in (None,'','null','None'): return None
    try: return float(v)
    except: return v

def parse_smiles_input(raw):
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i, s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# -- Transporter substrate/inhibitor models ------------------------------------
# Based on physicochemical rules from literature meta-analyses.
# Each model returns (substrate_prob, inhibitor_IC50_uM_predicted)

def oatp1b1_model(mw, logp, tpsa, hba, charge_state):
    '''
    OATP1B1: liver influx. Substrates: anionic (acid/zwitterion), MW 400-900, logP -2 to 5.
    Inhibitors: strongly lipophilic (logP>3) + MW>400 (Varma et al. 2012).
    '''
    substrate_prob = 0.0
    if tpsa > 100 and 400 < mw < 1000 and -2 <= logp <= 5: substrate_prob = 0.75
    elif tpsa > 75 and mw > 350: substrate_prob = 0.4

    # Inhibitor: lipophilic large molecules
    if logp > 3 and mw > 400: inh_ic50 = max(0.1, 10 / (logp * mw / 400))
    elif logp > 2 and mw > 300: inh_ic50 = 20.0
    else: inh_ic50 = 100.0
    return round(substrate_prob,2), round(inh_ic50,1)

def oatp1b3_model(mw, logp, tpsa, hba, charge_state):
    '''Similar to OATP1B1 but higher MW tolerance (bile acid substrates).'''
    sub_p = 0.6 if (tpsa > 100 and mw > 400) else (0.3 if tpsa > 60 and mw > 300 else 0.1)
    if logp > 3.5 and mw > 500: inh_ic50 = max(0.5, 15 / (logp * mw / 500))
    else: inh_ic50 = 50.0
    return round(sub_p,2), round(inh_ic50,1)

def pgp_model(mw, logp, tpsa, hba, charge_state):
    '''
    P-gp: efflux. Substrates: lipophilic, MW 200-1200, Seelig model (H-bond pattern).
    '''
    substrate_prob = 0.0
    if mw > 400 and logp > 2 and hba > 4: substrate_prob = 0.8
    elif mw > 300 and hba > 6: substrate_prob = 0.6
    elif logp > 4: substrate_prob = 0.45
    else: substrate_prob = 0.2

    # Inhibitor: highly lipophilic + H-bond acceptors (Seelig IC50 model)
    if logp > 3 and hba > 4: inh_ic50 = max(0.1, 5 / (logp * hba / 10))
    elif logp > 2: inh_ic50 = 15.0
    else: inh_ic50 = 80.0
    return round(substrate_prob,2), round(inh_ic50,1)

def bcrp_model(mw, logp, tpsa, hba, charge_state):
    '''BCRP: efflux; flat aromatic substrates, MW < 500.'''
    substrate_prob = 0.5 if (mw < 500 and logp < 3 and hba > 3) else 0.2
    inh_ic50 = max(0.5, 8 / max(1, logp)) if logp > 1 else 30.0
    return round(substrate_prob,2), round(inh_ic50,1)

def mate_model(mw, logp, tpsa, hba, charge_state):
    '''MATE1/2-K: renal efflux. Substrates: cationic, moderate MW.'''
    # Cationic compounds (basic nitrogen, low tPSA from N)
    substrate_prob = 0.6 if (logp < 4 and mw < 400 and charge_state in ('cation','zwitterion')) else 0.15
    inh_ic50 = max(1.0, 20 / max(0.5, logp)) if logp > 0 else 50.0
    return round(substrate_prob,2), round(inh_ic50,1)

def oat_model(mw, logp, tpsa, hba, charge_state):
    '''OAT1/3: renal uptake. Substrates: anionic organic acids, MW < 500.'''
    substrate_prob = 0.65 if (tpsa > 60 and mw < 500 and charge_state in ('anion','zwitterion')) else 0.1
    inh_ic50 = max(1.0, 30 / max(0.5, logp*tpsa/80)) if logp > 0 else 60.0
    return round(substrate_prob,2), round(inh_ic50,1)

def oct2_model(mw, logp, tpsa, hba, charge_state):
    '''OCT2: renal uptake, organic cations. Substrates: small cations MW < 400.'''
    substrate_prob = 0.55 if (mw < 400 and logp < 3 and charge_state in ('cation','zwitterion')) else 0.1
    inh_ic50 = max(0.5, 12 / max(0.5, logp+1)) if logp > -1 else 40.0
    return round(substrate_prob,2), round(inh_ic50,1)

TRANSPORTER_MODELS = {
    'OATP1B1': oatp1b1_model, 'OATP1B3': oatp1b3_model,
    'Pgp': pgp_model, 'BCRP': bcrp_model,
    'MATE1': mate_model, 'MATE2-K': mate_model,
    'OAT1': oat_model, 'OCT2': oct2_model,
}

# FDA basic model DDI thresholds (2020 Guidance Table 2)
FDA_INHIBITOR_THRESHOLDS = {
    'OATP1B1': {'R_value_threshold': 1.1, 'clinical_ddi_threshold': 0.02},
    'OATP1B3': {'R_value_threshold': 1.1, 'clinical_ddi_threshold': 0.02},
    'Pgp':     {'R_value_threshold': 1.25,'clinical_ddi_threshold': 0.1},
    'BCRP':    {'R_value_threshold': 1.1, 'clinical_ddi_threshold': 0.1},
    'MATE1':   {'R_value_threshold': 1.25,'clinical_ddi_threshold': 0.02},
    'MATE2-K': {'R_value_threshold': 1.25,'clinical_ddi_threshold': 0.02},
    'OAT1':    {'R_value_threshold': 1.25,'clinical_ddi_threshold': 0.04},
    'OCT2':    {'R_value_threshold': 1.1, 'clinical_ddi_threshold': 0.1},
}

def charge_state(mol):
    '''Rough charge state from SMARTS.'''
    has_acid = mol.HasSubstructMatch(Chem.MolFromSmarts('[\$([OH]C(=O)),\$([OH]S(=O)(=O)),\$([OH]P(=O))]'))
    has_base = mol.HasSubstructMatch(Chem.MolFromSmarts('[\$([NH2]),\$([NH]),\$([n])]'))
    if has_acid and has_base: return 'zwitterion'
    if has_acid: return 'anion'
    if has_base: return 'cation'
    return 'neutral'

def fda_basic_ddi(cmax_uM, inh_ic50_uM, threshold_r, clinical_threshold):
    '''
    FDA Basic Model (static): R = 1 + Imax,u / IC50
    Imax,u ~ Cmax_u (unbound plasma at portal entry).
    Trigger for in vitro study: R >= threshold.
    Trigger for clinical study: Imax,u / IC50 >= clinical_threshold.
    '''
    if cmax_uM is None or inh_ic50_uM is None:
        return None, 'unknown', 'insufficient_data'

    R = 1 + cmax_uM / inh_ic50_uM
    ratio = cmax_uM / inh_ic50_uM

    if ratio >= clinical_threshold:
        fda_recommendation = 'Conduct_clinical_DDI_study'
    elif R >= threshold_r:
        fda_recommendation = 'Conduct_in_vitro_mechanistic_study'
    else:
        fda_recommendation = 'No_action_required'

    return round(R, 3), fda_recommendation, round(ratio, 4)

# -- Process -------------------------------------------------------------------
raw_smiles  = os.environ.get('PARAM_SMILES_LIST','["C"]')
cmax_uM     = auto_convert(os.environ.get('PARAM_CMAX_UM')) or 1.0
transporters_param = os.environ.get('PARAM_TRANSPORTERS','all')

if transporters_param == 'all':
    selected_transporters = list(TRANSPORTER_MODELS.keys())
else:
    selected_transporters = [t.strip() for t in transporters_param.split(',')]

smiles_pairs = parse_smiles_input(raw_smiles)
trans_rows, ddi_rows = [], []
regulatory_compounds = []

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr); continue

    mw    = Descriptors.ExactMolWt(mol)
    logp  = Crippen.MolLogP(mol)
    tpsa  = rdMolDescriptors.CalcTPSA(mol)
    hba   = rdMolDescriptors.CalcNumHBA(mol)
    cs    = charge_state(mol)

    requires_in_vitro, requires_clinical, no_action = [], [], []
    ddi_compound = []

    for tname in selected_transporters:
        model_fn = TRANSPORTER_MODELS.get(tname)
        if not model_fn: continue

        sub_prob, inh_ic50 = model_fn(mw, logp, tpsa, hba, cs)
        fda_thresh = FDA_INHIBITOR_THRESHOLDS.get(tname, {})
        r_val, fda_rec, ratio = fda_basic_ddi(
            cmax_uM, inh_ic50,
            fda_thresh.get('R_value_threshold',1.1),
            fda_thresh.get('clinical_ddi_threshold',0.02)
        )

        risk_flag = 'HIGH' if fda_rec == 'Conduct_clinical_DDI_study' else \
                    'MEDIUM' if fda_rec == 'Conduct_in_vitro_mechanistic_study' else 'LOW'

        trans_rows.append({'compound':cid,'transporter':tname,
                           'substrate_probability':sub_prob,
                           'inhibitor_IC50_uM_predicted':inh_ic50,
                           'FDA_risk_flag':risk_flag})
        ddi_rows.append({'compound':cid,'transporter':tname,
                         'R_value':r_val, 'Cmax_IC50_ratio':ratio,
                         'FDA_recommendation':fda_rec})
        ddi_compound.append({'transporter':tname, 'recommendation':fda_rec, 'R':r_val})

        if fda_rec == 'Conduct_clinical_DDI_study': requires_clinical.append(tname)
        elif fda_rec == 'Conduct_in_vitro_mechanistic_study': requires_in_vitro.append(tname)
        else: no_action.append(tname)

    nda_labeling = bool(requires_clinical)
    regulatory_compounds.append({
        'compound': cid, 'charge_state': cs,
        'requires_in_vitro_study': requires_in_vitro,
        'requires_clinical_DDI_study': requires_clinical,
        'no_action_required': no_action,
        'NDA_labeling_needed': nda_labeling,
        'highest_risk_transporter': requires_clinical[0] if requires_clinical else (requires_in_vitro[0] if requires_in_vitro else 'none')
    })

# Write outputs
def write_csv_rows(path, rows, fields):
    with open(path,'w',newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader(); w.writerows(rows)

write_csv_rows('transporter_results.csv', trans_rows,
               ['compound','transporter','substrate_probability','inhibitor_IC50_uM_predicted','FDA_risk_flag'])
write_csv_rows('static_ddi_model.csv', ddi_rows,
               ['compound','transporter','R_value','Cmax_IC50_ratio','FDA_recommendation'])

with open('regulatory_summary.json','w') as f:
    out = regulatory_compounds[0] if len(regulatory_compounds)==1 else regulatory_compounds
    json.dump(out, f, indent=2)

summary = {'status':'completed','Cmax_uM_used':cmax_uM,'compounds':len(regulatory_compounds),
           'regulatory': regulatory_compounds}
with open('transporter_ddi_results.json','w') as f:
    json.dump(summary, f, indent=2)

report = ["=== TRANSPORTER DDI PREDICTION REPORT ===",
          f"Compound Cmax (unbound): {cmax_uM} uM  |  Transporters assessed: {', '.join(selected_transporters)}", ""]
for r in regulatory_compounds:
    report.append(f"Compound {r['compound']} [{r['charge_state']}]:")
    if r['requires_clinical_DDI_study']:
        report.append(f"  WARNING CLINICAL DDI required: {', '.join(r['requires_clinical_DDI_study'])}")
    if r['requires_in_vitro_study']:
        report.append(f"  In vitro study required: {', '.join(r['requires_in_vitro_study'])}")
    if r['no_action_required']:
        report.append(f"  No action: {', '.join(r['no_action_required'])}")
    report.append(f"  NDA labeling needed: {r['NDA_labeling_needed']}")
    report.append("")
with open('transporter_ddi_output.txt','w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
transporter_ddi_prediction:
  python: "3.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow TRANSPORTER_DDI_WORKFLOW {
    take: meta_ch
    main: TRANSPORTER_DDI_PREDICTION(meta_ch)
    emit:
        results    = TRANSPORTER_DDI_PREDICTION.out.results
        regulatory = TRANSPORTER_DDI_PREDICTION.out.regulatory
}

workflow {
    meta = [id: 'transporter_ddi_run', single_end: false]
    Channel.value(meta) | TRANSPORTER_DDI_WORKFLOW
}
