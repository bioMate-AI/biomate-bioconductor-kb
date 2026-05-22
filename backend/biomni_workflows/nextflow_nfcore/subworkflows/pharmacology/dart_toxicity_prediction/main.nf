#!/usr/bin/env nextflow
/*
 * pharmacology/dart_toxicity_prediction
 *
 * Predicts Developmental And Reproductive Toxicity (DART) risk for small
 * molecules using structural alerts (ICH S5 / OECD QSAR-derived SMARTS
 * library) and physicochemical placental transfer model.
 *
 * Alert library derived from:
 *   - ICH S5(R3) reproductive toxicity guideline structural alerts
 *   - Sutter & Amberg, Toxicol Lett 2014 (63 ICH M7 alerts adapted for DART)
 *   - EPA DSSTox DART categories
 *
 * Input:  SMILES (single or JSON array)
 * Output: dart_alerts.csv, placental_transfer.csv, dart_risk_tier.json
 */

nextflow.enable.dsl = 2

params.outdir                  = './results'
params.smiles_list             = '["O=C1CC(N2C(=O)c3ccccc3C2=O)C(=O)N1"]'   // thalidomide (known teratogen)
params.indication_population   = 'all'    // all | women_cbp | pediatric
params.run_placental_transfer  = 'true'

process DART_TOXICITY_PREDICTION {
    tag { meta.id }
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("dart_results.json"),           emit: results
    tuple val(meta), path("dart_output.txt"),             emit: output
    tuple val(meta), path("dart_alerts.csv"),             emit: alerts
    tuple val(meta), path("placental_transfer.csv"),      emit: placental
    tuple val(meta), path("dart_risk_tier.json"),         emit: risk_tier
    path "versions.yml",                                  emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_POPULATION='${params.indication_population}'
    export PARAM_PLACENTAL='${params.run_placental_transfer}'

    python3 << 'PYEOF'
import json, os, csv, sys
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen

def auto_convert(v):
    if v in (None, '', 'null', 'None'): return None
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

# -- DART structural alert library --------------------------------------------
# (name, SMARTS, mechanism, severity: HIGH/MEDIUM/LOW, evidence)
DART_ALERTS = [
    # Teratogens / embryotoxins
    ('thalidomide_glutarimide', 'O=C1CCC(=O)N1', 'thalidomide-type glutarimide ring', 'HIGH', 'ICH S5; thalidomide class'),
    ('nitrosamine', 'N-N=O', 'DNA alkylation -> embryotoxicity', 'HIGH', 'ICH M7 / DART alert'),
    ('aromatic_amine_primary', 'c1ccccc1N', 'hydroxylamine metabolite -> DNA damage', 'HIGH', 'ICH M7 adapted'),
    ('epoxide_reactive', 'C1OC1', 'epoxide alkylating agent -> embryotoxicity', 'HIGH', 'OECD QSAR DART'),
    ('michael_acceptor', 'C=CC(=O)', 'covalent protein/DNA modification', 'HIGH', 'EPA DSSTox DART'),
    ('azide_reactive', '[N-]=[N+]=N', 'reactive nitrogen -> reproductive toxicity', 'HIGH', 'OECD QSAR DART'),
    # Reproductive toxins
    ('antimetabolite_folate', 'c1cnc(N)nc1N', 'folate antagonism -> neural tube defects', 'HIGH', 'methotrexate class'),
    ('heavy_metal_chelator', 'SCC(N)C(=O)O', 'metal chelation -> reproductive toxicity', 'MEDIUM', 'RepDose DB'),
    ('peroxide_organic', 'OO', 'oxidative stress -> germ cell toxicity', 'MEDIUM', 'EPA DART'),
    ('halogenated_aromatic', 'c1ccccc1[F,Cl,Br,I]', 'halogenated aromatic -> endocrine disruption', 'MEDIUM', 'EPA EDC DART'),
    # Endocrine disruptors
    ('bisphenol_like', 'Oc1ccc(cc1)C(c2ccc(O)cc2)', 'estrogenic bisphenol -> reproductive toxicity', 'HIGH', 'REACH SVHC'),
    ('phthalate_ester', 'C(=O)OCC', 'PPAR-alpha agonism -> testicular toxicity', 'MEDIUM', 'DART/reproductive toxin'),
    ('steroid_skeleton', 'C1CC2CCCC3CC1(CC23)', 'steroidal structure -> hormone disruption', 'MEDIUM', 'endocrine DART'),
    # Lower concern
    ('acrylamide', 'C=CC(N)=O', 'nerve/germ cell toxicity', 'MEDIUM', 'IARC 2A; EFSA DART'),
    ('quinone', 'O=C1C=CC(=O)C=C1', 'oxidative stress', 'MEDIUM', 'OECD QSAR'),
    ('formaldehyde_releaser', 'OCN', 'in situ formaldehyde -> DNA damage', 'LOW', 'OECD QSAR adapted'),
]

def check_alerts(mol):
    hits = []
    for (name, sma, mech, sev, evidence) in DART_ALERTS:
        try:
            patt = Chem.MolFromSmarts(sma)
            if patt and mol.HasSubstructMatch(patt):
                hits.append({'alert': name, 'mechanism': mech,
                             'severity': sev, 'evidence': evidence, 'SMARTS': sma})
        except: pass
    return hits

def placental_transfer_risk(mol):
    '''
    Simplified placental transfer model.
    High transfer: MW < 500, LogP 0-5, low ionization (no strong acid/base).
    Reference: Hutson et al. Placenta 2011 meta-analysis.
    '''
    mw   = Descriptors.ExactMolWt(mol)
    logp = Crippen.MolLogP(mol)
    tpsa = rdMolDescriptors.CalcTPSA(mol)
    hbd  = rdMolDescriptors.CalcNumHBD(mol)

    score = 0
    if mw < 300: score += 3
    elif mw < 500: score += 2
    elif mw < 700: score += 1
    if 0 < logp < 5: score += 2
    if tpsa < 80: score += 1
    if hbd <= 2: score += 1

    if score >= 6: likelihood = 'HIGH'
    elif score >= 4: likelihood = 'MODERATE'
    elif score >= 2: likelihood = 'LOW'
    else: likelihood = 'MINIMAL'

    return {
        'MW': round(mw,1), 'LogP': round(logp,2), 'TPSA': round(tpsa,1),
        'HBD': hbd, 'transfer_likelihood': likelihood,
        'mw_threshold_exceeded': mw < 500,
        'logp_favorable': 0 < logp < 5
    }

def overall_risk(alert_hits, pt_likelihood):
    '''Compute overall DART risk tier.'''
    high_alerts  = [a for a in alert_hits if a['severity']=='HIGH']
    med_alerts   = [a for a in alert_hits if a['severity']=='MEDIUM']
    if high_alerts:
        return 'HIGH', f"Contains {len(high_alerts)} HIGH-severity structural alert(s)"
    if med_alerts and pt_likelihood in ('HIGH','MODERATE'):
        return 'MEDIUM', f"{len(med_alerts)} MEDIUM alert(s) + {pt_likelihood} placental transfer"
    if med_alerts:
        return 'MEDIUM', f"{len(med_alerts)} MEDIUM alert(s)"
    if pt_likelihood == 'HIGH' and not alert_hits:
        return 'LOW-WATCH', "No structural alerts but high placental transfer"
    return 'LOW', "No structural alerts; low placental transfer"

# -- Process compounds ---------------------------------------------------------
raw_smiles = os.environ.get('PARAM_SMILES_LIST', '["C"]')
run_pt     = os.environ.get('PARAM_PLACENTAL', 'true').lower() in ('true','1','yes')

smiles_pairs = parse_smiles_input(raw_smiles)
alert_rows, pt_rows, risk_tiers = [], [], []

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES for {cid}", file=sys.stderr)
        continue

    alerts = check_alerts(mol)
    for a in alerts:
        alert_rows.append({'compound': cid, 'SMILES': smi, **a})

    pt = placental_transfer_risk(mol) if run_pt else {}
    pt_rows.append({'compound': cid, 'SMILES': smi, **pt})

    risk, reason = overall_risk(alerts, pt.get('transfer_likelihood','UNKNOWN'))
    rec_map = {
        'HIGH': 'Conduct ICH S5(A+B) fertility + embryo-fetal development studies before Phase I',
        'MEDIUM': 'Run ICH S5(A) fertility study before Phase II; include WOCBP restriction in protocol',
        'LOW-WATCH': 'No alerts detected but high placental transfer; monitor embryo-fetal endpoints',
        'LOW': 'Standard ICH S5 package; no pre-Phase I DART studies required'
    }
    risk_tiers.append({
        'compound': cid, 'SMILES': smi,
        'DART_risk': risk, 'reason': reason,
        'alert_count': len(alerts),
        'HIGH_alerts': [a['alert'] for a in alerts if a['severity']=='HIGH'],
        'placental_transfer': pt.get('transfer_likelihood','UNKNOWN'),
        'recommendation': rec_map.get(risk, '')
    })

# -- Write outputs --------------------------------------------------------------
def write_csv(path, rows, fields):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader(); w.writerows(rows)

write_csv('dart_alerts.csv', alert_rows,
          ['compound','SMILES','alert','mechanism','severity','evidence','SMARTS'])
write_csv('placental_transfer.csv', pt_rows,
          ['compound','SMILES','MW','LogP','TPSA','HBD','transfer_likelihood','mw_threshold_exceeded','logp_favorable'])

# risk tier JSON
with open('dart_risk_tier.json', 'w') as f:
    json.dump(risk_tiers if len(risk_tiers) > 1 else (risk_tiers[0] if risk_tiers else {}), f, indent=2)

summary = {
    'status': 'completed',
    'compounds_analyzed': len(risk_tiers),
    'high_risk': sum(1 for r in risk_tiers if r['DART_risk']=='HIGH'),
    'medium_risk': sum(1 for r in risk_tiers if r['DART_risk']=='MEDIUM'),
    'low_risk': sum(1 for r in risk_tiers if 'LOW' in r['DART_risk']),
    'total_alerts': len(alert_rows),
    'risk_tiers': risk_tiers
}
with open('dart_results.json', 'w') as f:
    json.dump(summary, f, indent=2)

report = ["=== DART TOXICITY PREDICTION REPORT ===",
          f"Compounds: {summary['compounds_analyzed']}  HIGH={summary['high_risk']}  MEDIUM={summary['medium_risk']}  LOW={summary['low_risk']}",
          f"Total structural alerts triggered: {summary['total_alerts']}", ""]
for r in risk_tiers:
    report.append(f"  [{r['compound']}] DART={r['DART_risk']} | alerts={r['alert_count']} | placental={r['placental_transfer']}")
    if r['HIGH_alerts']:
        report.append(f"    HIGH alerts: {', '.join(r['HIGH_alerts'])}")
    report.append(f"    -> {r['recommendation']}")
with open('dart_output.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
dart_toxicity_prediction:
  python: "3.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow DART_TOXICITY_WORKFLOW {
    take: meta_ch
    main: DART_TOXICITY_PREDICTION(meta_ch)
    emit:
        results  = DART_TOXICITY_PREDICTION.out.results
        risk_tier = DART_TOXICITY_PREDICTION.out.risk_tier
}

workflow {
    meta = [id: 'dart_tox_run', single_end: false]
    Channel.value(meta) | DART_TOXICITY_WORKFLOW
}
