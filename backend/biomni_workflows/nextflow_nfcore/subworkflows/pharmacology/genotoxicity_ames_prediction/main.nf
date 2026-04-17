#!/usr/bin/env nextflow
/*
 * pharmacology/genotoxicity_ames_prediction
 *
 * Predicts Ames mutagenicity and genotoxicity potential using a structural
 * alert library derived from Derek Nexus rules and ICH S2(R1) guidance.
 * Also evaluates micronucleus and chromosomal aberration risk from
 * clastogenic/aneugenic SMARTS alerts.
 *
 * Alert library references:
 *   - Bailey et al. Mutat Res 2005 (Derek-derived alerts)
 *   - Kazius et al. J Med Chem 2005 (QSAR Ames model)
 *   - ICH S2(R1) structural categories
 *   - OECD QSAR toolbox genotoxicity filters
 *
 * Input:  SMILES (single or batch)
 * Output: ames_prediction.json, genotox_alerts.csv, ichs2_summary.json
 */

nextflow.enable.dsl = 2

params.outdir       = './results'
params.smiles_list  = '["Nc1ccc([N+](=O)[O-])cc1"]'

process GENOTOXICITY_AMES_PREDICTION {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("genotox_results.json"),         emit: results
    tuple val(meta), path("genotox_output.txt"),           emit: output
    tuple val(meta), path("ames_prediction.json"),         emit: ames
    tuple val(meta), path("genotox_alerts.csv"),           emit: alerts
    tuple val(meta), path("ichs2_summary.json"),           emit: ichs2
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'

    python3 << 'PYEOF'
import json, os, csv, sys
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors

def parse_smiles_input(raw):
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i, s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# -- Ames mutagenicity structural alert library --------------------------------
# Category assignments follow ICH S2(R1) + Kazius 2005 + Bailey 2005
AMES_ALERTS = [
    # Category A -- Direct DNA reactants (always flag HIGH)
    ('nitro_aromatic',       '[c][N+](=O)[O-]',           'A', 'HIGH',  'Aromatic nitro -- DNA adduct former, Ames-positive'),
    ('nitro_aliphatic',      '[CX4][N+](=O)[O-]',         'A', 'HIGH',  'Aliphatic nitro -- potent mutagen (alpha-nitro activation)'),
    ('primary_aromatic_amine','Nc1ccccc1',                 'A', 'HIGH',  'Primary aromatic amine -- CYP/acetyltransferase activation -> DNA adduct'),
    ('aromatic_amine_meta',  'Nc1cccnc1',                 'A', 'HIGH',  'Heteroaromatic amine -- metabolic activation mutagenicity'),
    ('nitroso',              '[N;!\$(NC=O)]=[O]',           'A', 'HIGH',  'Nitroso compound -- DNA alkylation'),
    ('nitrosamine',          '[NH]N=O',                   'A', 'HIGH',  'N-Nitrosamine -- strong mutagen / IARC Group 1'),
    ('diazonium',            '[N+]#N',                    'A', 'HIGH',  'Diazonium ion -- direct DNA alkylator'),
    ('epoxide',              '[C@@H]1OC1',                'A', 'HIGH',  'Epoxide -- DNA strand break'),
    ('alkyl_epoxide',        'C1OC1',                     'A', 'HIGH',  'Alkyl epoxide -- electrophilic DNA alkylator'),
    ('aziridine',            'C1CN1',                     'A', 'HIGH',  'Aziridine -- nitrogen mustard analogue'),
    ('propiolactone',        'C1CC(=O)O1',                'A', 'HIGH',  'Propiolactone -- reactive alkylating agent'),
    ('n_methylol',           '[NX3][CH2]O',               'A', 'HIGH',  'N-methylol -- formaldehyde releaser, DNA crosslinker'),
    # Category B -- Indirect mutagens (flag MEDIUM)
    ('polycyclic_aromatic',  'c1ccc2ccccc2c1',            'B', 'MEDIUM','PAH scaffold -- metabolic diol-epoxide activation'),
    ('furan_oxidizable',     'c1ccoc1',                   'B', 'MEDIUM','Furan ring -- CYP-mediated enedial metabolite'),
    ('alkenyl_aldehyde',     'C=CC=O',                    'B', 'MEDIUM','alpha,beta-unsaturated aldehyde -- Michael acceptor'),
    ('michael_acceptor',     'C=CC(=O)',                  'B', 'MEDIUM','Enone Michael acceptor -- covalent DNA modification'),
    ('halogen_alkyl',        '[F,Cl,Br,I][CX4]',          'B', 'MEDIUM','Alkyl halide -- DNA alkylation potential'),
    ('5_nitroimidazole',     '[n]c([N+](=O)[O-])cn',      'B', 'MEDIUM','5-Nitroimidazole -- nitroreductase activation (metronidazole class)'),
    ('aromatic_azo',         'c-N=N-c',                   'B', 'MEDIUM','Azo dye scaffold -- azo reductase cleavage -> aromatic amine'),
    ('aromatic_hydroxylamine','Nc1ccccc1O',               'B', 'MEDIUM','N-OH amine -- direct-acting mutagen in activated form'),
    # Category C -- Clastogenicity / aneugenicity
    ('podophyllotoxin_like', 'c1cc2c(cc1OC)C3CC(=O)',    'C', 'MEDIUM','Topoisomerase II inhibitor scaffold -- DNA strand breaks'),
    ('anthraquinone',        'O=C1c2ccccc2C(=O)c2ccccc21','C', 'MEDIUM','Anthraquinone -- intercalation + topo II inhibition'),
    # Category D -- Negative QSAR indicators (reduce concern if present)
]
ALERT_PATTERNS = []
for entry in AMES_ALERTS:
    name, smarts, cat, severity, desc = entry
    patt = Chem.MolFromSmarts(smarts)
    if patt:
        ALERT_PATTERNS.append((name, patt, cat, severity, desc))

# -- ICH S2(R1) category definitions ------------------------------------------
ICH_S2_CATS = {
    'A': 'ICH S2(R1) Cat A -- Structural alert for direct DNA interaction; expect positive standard genotox battery',
    'B': 'ICH S2(R1) Cat B -- Indirect mutagen via metabolic activation; further genotox testing required',
    'C': 'ICH S2(R1) Cat C -- Clastogenic/aneugenic concern; in vitro micronucleus required',
}

def ames_verdict(alerts):
    '''Overall Ames prediction from alert list.'''
    if any(a[3] == 'HIGH' for a in alerts):
        return 'POSITIVE', 'HIGH', 'Predicted Ames-positive: Cat A structural alert(s) found'
    if any(a[3] == 'MEDIUM' for a in alerts):
        return 'SUSPECT', 'MEDIUM', 'Predicted Ames-suspect: Cat B metabolic activation alert(s)'
    return 'NEGATIVE', 'LOW', 'No structural alerts detected -- predicted Ames-negative'

def ichs2_genotox_battery(verdict, alerts):
    '''
    ICH S2(R1) compliant testing recommendation based on alert findings.
    Standard battery: (1) Ames test, (2) in vitro MN/CA, (3) in vivo comet or MN if 2 positives.
    '''
    has_A = any(a[2] == 'A' for a in alerts)
    has_B = any(a[2] == 'B' for a in alerts)
    has_C = any(a[2] == 'C' for a in alerts)
    battery = []
    if has_A or has_B:
        battery.append('Ames test (TA98, TA100, TA1535, TA1537 +/- S9)')
    if has_B or has_C:
        battery.append('In vitro micronucleus test (human lymphocytes +/- S9)')
    if has_A:
        battery.append('In vitro chromosomal aberration (if Ames +)')
    if (has_A or has_B) and verdict == 'POSITIVE':
        battery.append('In vivo bone marrow micronucleus (if 2 in vitro positives)')
    if not battery:
        battery.append('Standard ICH S2(R1) battery (Ames + 1 in vitro clastogenicity test)')
    return battery

# -- Process -------------------------------------------------------------------
raw_smiles   = os.environ.get('PARAM_SMILES_LIST', '["C"]')
smiles_pairs = parse_smiles_input(raw_smiles)

all_records  = []
alerts_rows  = [['compound', 'alert_name', 'category', 'severity', 'SMILES', 'description']]
ichs2_recs   = []

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr)
        continue

    # Run all alerts
    triggered = []
    for name, patt, cat, severity, desc in ALERT_PATTERNS:
        if mol.HasSubstructMatch(patt):
            triggered.append((name, cat, severity, desc))
            alerts_rows.append([cid, name, cat, severity, smi, desc])

    verdict, concern_level, verdict_text = ames_verdict(triggered)
    battery = ichs2_genotox_battery(verdict, triggered)

    ichs2_cats_triggered = sorted(set(a[1] for a in triggered))
    ichs2_statements = [ICH_S2_CATS[c] for c in ichs2_cats_triggered if c in ICH_S2_CATS]

    rec = {
        'compound': cid,
        'SMILES': smi,
        'ames_prediction': verdict,
        'genotox_concern_level': concern_level,
        'verdict_text': verdict_text,
        'alerts_triggered': [{'name': a[0], 'category': a[1], 'severity': a[2], 'description': a[3]} for a in triggered],
        'n_alerts': len(triggered),
        'high_priority_alerts': sum(1 for a in triggered if a[2] == 'HIGH'),
        'ichs2_categories': ichs2_cats_triggered,
        'recommended_genotox_battery': battery,
    }
    all_records.append(rec)

    ichs2_recs.append({
        'compound': cid,
        'prediction': verdict,
        'concern_level': concern_level,
        'ichs2_categories_triggered': ichs2_cats_triggered,
        'ichs2_statements': ichs2_statements,
        'recommended_tests': battery,
    })

# -- Write outputs --------------------------------------------------------------
with open('ames_prediction.json', 'w') as f:
    out = all_records[0] if len(all_records) == 1 else all_records
    json.dump(out, f, indent=2)

with open('genotox_alerts.csv', 'w', newline='') as f:
    csv.writer(f).writerows(alerts_rows)

with open('ichs2_summary.json', 'w') as f:
    out = ichs2_recs[0] if len(ichs2_recs) == 1 else ichs2_recs
    json.dump(out, f, indent=2)

full = {
    'status': 'completed',
    'n_compounds': len(all_records),
    'positive_count': sum(1 for r in all_records if r['ames_prediction'] == 'POSITIVE'),
    'suspect_count': sum(1 for r in all_records if r['ames_prediction'] == 'SUSPECT'),
    'negative_count': sum(1 for r in all_records if r['ames_prediction'] == 'NEGATIVE'),
    'results': all_records
}
with open('genotox_results.json', 'w') as f:
    json.dump(full, f, indent=2)

report = ['=== GENOTOXICITY / AMES PREDICTION REPORT ===', '']
for r in all_records:
    report += [
        f"Compound {r['compound']}:  {r['ames_prediction']} (concern: {r['genotox_concern_level']})",
        f"  {r['verdict_text']}",
        f"  Alerts: {r['n_alerts']} ({r['high_priority_alerts']} Cat A high-priority)",
    ]
    if r['alerts_triggered']:
        for a in r['alerts_triggered']:
            report.append(f"    - [{a['category']}] {a['name']}: {a['description']}")
    report += [f"  Recommended tests: {'; '.join(r['recommended_genotox_battery'])}", '']

with open('genotox_output.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
genotoxicity_ames_prediction:
  python: "3.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow GENOTOXICITY_AMES_WORKFLOW {
    take: meta_ch
    main: GENOTOXICITY_AMES_PREDICTION(meta_ch)
    emit:
        results = GENOTOXICITY_AMES_PREDICTION.out.results
        ames    = GENOTOXICITY_AMES_PREDICTION.out.ames
        alerts  = GENOTOXICITY_AMES_PREDICTION.out.alerts
}

workflow {
    meta = [id: 'genotox_run', single_end: false]
    Channel.value(meta) | GENOTOXICITY_AMES_WORKFLOW
}
