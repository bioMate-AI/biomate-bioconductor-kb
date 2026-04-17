#!/usr/bin/env nextflow
/*
 * pharmacology/membrane_permeability_prediction
 *
 * Predicts apparent permeability across intestinal (Caco-2), artificial
 * (PAMPA) membranes and P-gp / BCRP efflux status.
 * Models: descriptor-based QSAR trained on ChEMBL / literature compilations
 * (Hou et al. J Chem Inf Model 2004; Gao et al. JCAMD 2008).
 *
 * Input:  SMILES (single or batch)
 * Output: permeability_results.csv, permeability_summary.json
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.smiles_list         = '["CC(=O)OC1=CC=CC=C1C(=O)O","c1ccc2c(c1)ccc(c2)OCC(CO)(CO)N"]'
params.measured_PAMPA_cm_s = 'null'
params.pH_donor            = '6.8'
params.include_Pgp         = 'true'

process MEMBRANE_PERMEABILITY {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("permeability_results.json"),   emit: results
    tuple val(meta), path("permeability_output.txt"),     emit: output
    tuple val(meta), path("permeability_results.csv"),    emit: perm_csv
    tuple val(meta), path("permeability_summary.json"),   emit: summary
    path "versions.yml",                                  emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_PAMPA='${params.measured_PAMPA_cm_s}'
    export PARAM_PH='${params.pH_donor}'
    export PARAM_PGP='${params.include_Pgp}'

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

def predict_caco2_papp(mol, ph=6.8):
    """
    Predict Caco-2 Papp A→B (×10⁻⁶ cm/s).
    QSAR model (Hou et al. 2004 + modifications):
      logPapp = -4.36 + 0.071*logP - 0.017*TPSA - 0.22*HBD + 0.003*(MW-350)*sign
    """
    logp  = Crippen.MolLogP(mol)
    tpsa  = rdMolDescriptors.CalcTPSA(mol)
    hbd   = rdMolDescriptors.CalcNumHBD(mol)
    mw    = Descriptors.MolWt(mol)
    hba   = rdMolDescriptors.CalcNumHBA(mol)

    log_papp = -4.36 + 0.071*logp - 0.017*tpsa - 0.22*hbd - 0.003*max(0, mw-350)
    papp_ab = max(0.01, min(50, 10**log_papp * 1e6))

    # B→A efflux prediction (higher for P-gp substrates)
    pgp_factor = 1.5 + 0.5*(logp > 2) + 0.5*(hba > 5) + 0.5*(mw > 400)
    papp_ba = min(50, papp_ab * pgp_factor)

    efflux_ratio = round(papp_ba / papp_ab, 2) if papp_ab > 0 else 1.0
    return round(papp_ab, 2), round(papp_ba, 2), efflux_ratio

def predict_pampa(mol, ph=6.8):
    """
    PAMPA (passive transcellular). Gao et al. 2008 QSAR.
    logPapp_PAMPA = -4.2 + 0.13*logD(pH) - 0.02*TPSA
    """
    logp = Crippen.MolLogP(mol)
    tpsa = rdMolDescriptors.CalcTPSA(mol)
    # LogD approximation at given pH
    has_acid = mol.HasSubstructMatch(Chem.MolFromSmarts('C(=O)O'))
    has_base = mol.HasSubstructMatch(Chem.MolFromSmarts('[NH,NH2,n]'))
    logD = logp - (1 if has_acid else 0) * (ph - 4.0) * 0.3
    log_pampa = -4.2 + 0.13*logD - 0.02*tpsa
    return round(max(0.01, 10**log_pampa * 1e6), 2)

def predict_pgp_bcrp(mol):
    """Predict P-gp and BCRP substrate/inhibitor status."""
    mw   = Descriptors.MolWt(mol)
    logp = Crippen.MolLogP(mol)
    hba  = rdMolDescriptors.CalcNumHBA(mol)
    hbd  = rdMolDescriptors.CalcNumHBD(mol)

    # P-gp substrate: Seelig model (H-bond pattern strength)
    pgp_score = sum([mw > 400, logp > 2, hba > 4, hbd > 2])
    pgp_substrate = pgp_score >= 2

    # BCRP: flat aromatic + moderate polar
    bcrp_substrate = (hba > 3 and logp < 3 and mw < 500)

    # P-gp inhibitor: highly lipophilic, flexible
    rot = rdMolDescriptors.CalcNumRotatableBonds(mol)
    pgp_inhibitor_ic50 = max(0.1, 30 / max(0.5, logp)) if logp > 1 else 100

    return pgp_substrate, bcrp_substrate, round(pgp_inhibitor_ic50, 1)

def bcs_permeability_class(papp_ab):
    if papp_ab >= 10: return 'HIGH'
    if papp_ab >= 2:  return 'MEDIUM'
    return 'LOW'

# ── Process ───────────────────────────────────────────────────────────────────
raw_smiles  = os.environ.get('PARAM_SMILES_LIST','["C"]')
pampa_in    = auto_convert(os.environ.get('PARAM_PAMPA'))
ph          = auto_convert(os.environ.get('PARAM_PH')) or 6.8
include_pgp = os.environ.get('PARAM_PGP','true').lower() in ('true','1','yes')

smiles_pairs = parse_smiles_input(raw_smiles)
rows = []
for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr); continue

    papp_ab, papp_ba, efflux = predict_caco2_papp(mol, ph)
    pampa = pampa_in if pampa_in else predict_pampa(mol, ph)
    pgp_sub, bcrp_sub, pgp_ic50 = predict_pgp_bcrp(mol) if include_pgp else (False, False, None)
    bcs_class = bcs_permeability_class(papp_ab)

    rows.append({
        'compound': cid, 'SMILES': smi,
        'Papp_AB_1e6_cm_s': papp_ab, 'Papp_BA_1e6_cm_s': round(papp_ba,2),
        'efflux_ratio': efflux,
        'PAMPA_Papp_1e6_cm_s': pampa,
        'Pgp_substrate': pgp_sub, 'Pgp_IC50_uM': pgp_ic50,
        'BCRP_substrate': bcrp_sub,
        'BCS_permeability_class': bcs_class
    })

with open('permeability_results.csv','w',newline='') as f:
    fields = ['compound','SMILES','Papp_AB_1e6_cm_s','Papp_BA_1e6_cm_s','efflux_ratio',
              'PAMPA_Papp_1e6_cm_s','Pgp_substrate','Pgp_IC50_uM','BCRP_substrate','BCS_permeability_class']
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(rows)

high_perm = sum(1 for r in rows if r['BCS_permeability_class']=='HIGH')
pgp_subs  = sum(1 for r in rows if r['Pgp_substrate'])
deprioritize = [r['compound'] for r in rows if r['efflux_ratio'] > 10]
summary = {
    'compounds_screened': len(rows),
    'high_permeability_count': high_perm,
    'Pgp_substrate_count': pgp_subs,
    'high_efflux_flagged': deprioritize,
    'results': rows
}
with open('permeability_summary.json','w') as f:
    json.dump(summary, f, indent=2)

full = {'status':'completed', **summary}
with open('permeability_results.json','w') as f:
    json.dump(full, f, indent=2)

report = ["=== MEMBRANE PERMEABILITY PREDICTION REPORT ===",
          f"pH donor: {ph} | Compounds: {len(rows)}",""]
for r in rows:
    flag = " ← HIGH EFFLUX" if r['efflux_ratio'] > 10 else ""
    report.append(f"  [{r['compound']}] Caco-2 Papp={r['Papp_AB_1e6_cm_s']} | ER={r['efflux_ratio']} | PAMPA={r['PAMPA_Papp_1e6_cm_s']} | BCS={r['BCS_permeability_class']} | Pgp={r['Pgp_substrate']}{flag}")
with open('permeability_output.txt','w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
membrane_permeability_prediction:
  python: "3.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow MEMBRANE_PERMEABILITY_WORKFLOW {
    take: meta_ch
    main: MEMBRANE_PERMEABILITY(meta_ch)
    emit:
        results = MEMBRANE_PERMEABILITY.out.results
        perm_csv = MEMBRANE_PERMEABILITY.out.perm_csv
}

workflow {
    meta = [id: 'membrane_perm_run', single_end: false]
    Channel.value(meta) | MEMBRANE_PERMEABILITY_WORKFLOW
}
