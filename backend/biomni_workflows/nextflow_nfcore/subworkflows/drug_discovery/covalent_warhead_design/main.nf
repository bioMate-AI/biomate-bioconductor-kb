#!/usr/bin/env nextflow
/*
 * drug_discovery/covalent_warhead_design
 *
 * Evaluates electrophilic warhead reactivity for targeted covalent inhibitors.
 * Predicts warhead class via SMARTS, GSH half-life (t1/2 in h) from empirical
 * data, thiol selectivity, and promiscuous covalent modification risk.
 *
 * GSH half-life data from: Mah et al. JACS 2014; McAulay et al. J Med Chem 2019;
 * Flanagan et al. Drug Discov Today 2020. CovPDB-derived warhead inventory.
 *
 * Input:  SMILES (covalent inhibitor)
 * Output: warhead_profile.json, cys_selectivity.csv, recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir       = './results'
params.smiles_list  = '["C#CCN1CC(=O)Nc2ccc(F)cc21"]'   // ibrutinib-like acrylamide
params.warhead_type = 'auto'
params.run_gsh      = 'true'
params.run_kinome_selectivity = 'false'

process COVALENT_WARHEAD_DESIGN {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("warhead_results.json"),      emit: results
    tuple val(meta), path("warhead_output.txt"),        emit: output
    tuple val(meta), path("warhead_profile.json"),      emit: profile
    tuple val(meta), path("cys_selectivity.csv"),       emit: cys_selectivity
    tuple val(meta), path("recommendation.json"),       emit: recommendation
    path "versions.yml",                                emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_WARHEAD_TYPE='${params.warhead_type}'
    export PARAM_RUN_GSH='${params.run_gsh}'

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

# -- Warhead SMARTS library ----------------------------------------------------
# (name, SMARTS, gsh_t_half_h_typical, reactivity_class, mechanism)
WARHEADS = [
    ('acrylamide',          'C=CC(=O)N',     2.5,   'MODERATE',    'Michael addition to Cys-SH'),
    ('acrylamide_vinyl',    'C=CC(=O)',       1.5,   'MODERATE',    'Michael addition'),
    ('propiolamide',        'C#CC(=O)N',     0.5,   'HIGH',        'Michael addition (activated alkyne)'),
    ('cyanoacrylamide',     'C(=CC#N)C(=O)', 5.0,   'MODERATE',    'Reversible Michael addition'),
    ('chloroacetamide',     'ClCC(=O)N',     0.1,   'HIGH',        'SN2 alkylation'),
    ('epoxide',             'C1OC1',         0.05,  'VERY_HIGH',   'SN2 / acid-catalyzed ring opening'),
    ('vinyl_sulfone',       'C=CS(=O)(=O)',  0.8,   'HIGH',        'Michael addition to Cys-SH'),
    ('alpha_halo_ketone',   '[F,Cl,Br]CC=O', 0.05,  'VERY_HIGH',  'SN2 alkylation'),
    ('maleimide',           'N1C(=O)C=CC1=O', 0.1,  'HIGH',       'Michael addition (maleimide)'),
    ('boronic_acid',        'B(O)O',         None,  'REVERSIBLE',  'Reversible covalent; Ser/Thr/Tyr'),
    ('aldehyde',            '[CX3H1](=O)',   None,  'REVERSIBLE',  'Schiff base with Lys-NH2'),
    ('fluorosulfate',       'FS(=O)(=O)O',   None,  'HIGH',        'SuFEx chemistry; tyrosine labeling'),
    ('fluorophosphonate',   'FP(=O)(O)O',    0.001, 'VERY_HIGH',  'Serine hydrolase inhibitor'),
    ('disulfide',           'SSC',           None,  'REVERSIBLE',  'Thiol exchange; reversible Cys'),
    ('nitrile_electrophile','C#N',           None,  'LOW',         'Reversible nitrile warhead'),
    ('vinyl_heteroaromatic','c1ccc(C=C)cc1', 3.0,   'MODERATE',   'Michael addition; aryl-vinyl'),
]

# Non-reactive scaffold check
NON_REACTIVE_ALERTS = [
    ('pan_assay_electrophile', '[#6;!R]([F,Cl,Br,I])=O', 'acyl halide -- pan-assay interference'),
    ('isocyanate',             'N=C=O',                  'isocyanate -- pan-assay interference'),
    ('anhydride',              'OC(=O)OC(=O)',            'anhydride -- pan-assay interference'),
]

def classify_warhead(mol):
    hits = []
    for (name, sma, gsh_t, reac, mech) in WARHEADS:
        try:
            p = Chem.MolFromSmarts(sma)
            if p and mol.HasSubstructMatch(p):
                hits.append({'warhead_type': name, 'mechanism': mech,
                             'reactivity_class': reac, 'GSH_t_half_h': gsh_t,
                             'SMARTS': sma})
        except: pass
    pan_hits = []
    for (name, sma, concern) in NON_REACTIVE_ALERTS:
        try:
            p = Chem.MolFromSmarts(sma)
            if p and mol.HasSubstructMatch(p):
                pan_hits.append({'flag': name, 'concern': concern})
        except: pass
    return hits, pan_hits

def gsh_reactivity_class(t_half):
    """Optimal warhead window: 2-5 h."""
    if t_half is None: return 'UNKNOWN (reversible or not measured)'
    if t_half < 0.2:   return 'TOO_REACTIVE -- pan-assay interference risk'
    if t_half < 2.0:   return 'REACTIVE -- border of optimal range'
    if t_half <= 5.0:  return 'OPTIMAL -- in targeted covalent inhibitor window'
    if t_half <= 24:   return 'MILD -- slow reaction; may need extended binding time'
    return 'VERY_MILD -- consider more reactive warhead'

def promiscuity_risk(warhead_name, reactivity_class, mw):
    """Estimate off-target covalent modification risk."""
    if reactivity_class == 'VERY_HIGH': return 'HIGH'
    if reactivity_class == 'HIGH' and mw < 300: return 'HIGH'
    if reactivity_class == 'HIGH': return 'MEDIUM'
    if reactivity_class == 'MODERATE': return 'LOW'
    return 'VERY_LOW'

def cys_selectivity_estimate(mol, warhead_hits):
    """
    Simplified kinome Cys accessibility scoring.
    Lists 10 clinically-relevant kinases with known reactive Cys residues.
    """
    KINASE_CYS = [
        ('BTK',  'C481', 'acrylamide | chloroacetamide', 'HIGH'),
        ('EGFR', 'C797', 'acrylamide | cyanoacrylamide', 'HIGH'),
        ('JAK3', 'C909', 'acrylamide | vinyl_sulfone',   'HIGH'),
        ('KRAS_G12C', 'C12_mut', 'acrylamide',           'HIGH'),
        ('ITK',  'C442', 'acrylamide',                   'MEDIUM'),
        ('RSK2', 'C436', 'vinyl_sulfone | acrylamide',   'MEDIUM'),
        ('FGFR1','C488', 'acrylamide',                   'MEDIUM'),
        ('HER2', 'C805', 'acrylamide',                   'MEDIUM'),
        ('PI3Kd','C604', 'acrylamide | chloroacetamide', 'LOW'),
        ('MKK7', 'C218', 'acrylamide',                   'LOW'),
    ]
    wh_names = set(h['warhead_type'] for h in warhead_hits)
    rows = []
    for (kinase, cys, compatible_whs, accessibility) in KINASE_CYS:
        compatible = any(wh in compatible_whs for wh in wh_names)
        labeling_eff = {'HIGH':0.8,'MEDIUM':0.4,'LOW':0.1}.get(accessibility,0) if compatible else 0.0
        rows.append({'kinase': kinase, 'cysteine': cys, 'compatible_warhead': compatible,
                     'predicted_labeling_pct': round(labeling_eff*100,0)})
    return rows

# -- Process compounds ---------------------------------------------------------
raw_smiles = os.environ.get('PARAM_SMILES_LIST', '["C"]')
run_gsh    = os.environ.get('PARAM_RUN_GSH', 'true').lower() in ('true','1','yes')

smiles_pairs = parse_smiles_input(raw_smiles)
all_profiles, all_recommendations = [], []

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES {cid}", file=sys.stderr); continue

    mw = Descriptors.ExactMolWt(mol)
    warhead_hits, pan_hits = classify_warhead(mol)

    if not warhead_hits:
        profile = {'compound': cid, 'SMILES': smi, 'warhead_detected': False,
                   'note': 'No electrophilic warhead detected -- may be non-covalent or novel scaffold'}
        rec = {'compound': cid, 'verdict': 'NO_WARHEAD', 'recommendation': 'No electrophilic warhead found -- classify as non-covalent or submit for expert review'}
    else:
        wh = warhead_hits[0]  # primary warhead
        gsh_t = wh.get('GSH_t_half_h')
        reac_class = gsh_reactivity_class(gsh_t)
        prom_risk = promiscuity_risk(wh['warhead_type'], wh['reactivity_class'], mw)

        profile = {
            'compound': cid, 'SMILES': smi, 'warhead_detected': True,
            'warhead_type': wh['warhead_type'], 'mechanism': wh['mechanism'],
            'reactivity_class': wh['reactivity_class'],
            'GSH_t_half_h': gsh_t, 'GSH_reactivity_class': reac_class,
            'promiscuity_risk': prom_risk,
            'pan_assay_flags': pan_hits
        }

        if wh['reactivity_class'] == 'VERY_HIGH' or pan_hits:
            verdict = 'DO_NOT_PROCEED'
            recommendation = 'Warhead too reactive or pan-assay electrophile -- redesign before advancing'
        elif 'OPTIMAL' in reac_class and prom_risk in ('LOW','VERY_LOW'):
            verdict = 'PROCEED'
            recommendation = f"GSH t1/2={gsh_t}h in optimal window (2-5h); low promiscuity risk -> advance to selectivity profiling"
        elif 'MILD' in reac_class:
            verdict = 'PROCEED_WITH_MONITORING'
            recommendation = f"Mild warhead (GSH t1/2={gsh_t}h); sufficient for targeted covalent but verify on-target engagement"
        else:
            verdict = 'OPTIMIZE'
            recommendation = f"Warhead reactivity borderline ({reac_class}) -- consider cyanoacrylamide or modulated electrophile"

        rec = {'compound': cid, 'verdict': verdict, 'recommendation': recommendation,
               'warhead_type': wh['warhead_type'], 'GSH_t_half_h': gsh_t}

    all_profiles.append(profile)
    all_recommendations.append(rec)

# Cys selectivity from first compound
cys_rows = []
if smiles_pairs:
    mol0 = Chem.MolFromSmiles(smiles_pairs[0][1])
    if mol0:
        wh0, _ = classify_warhead(mol0)
        cys_rows = cys_selectivity_estimate(mol0, wh0)

# -- Write outputs --------------------------------------------------------------
with open('warhead_profile.json','w') as f:
    json.dump(all_profiles if len(all_profiles)>1 else (all_profiles[0] if all_profiles else {}), f, indent=2)
with open('recommendation.json','w') as f:
    json.dump(all_recommendations if len(all_recommendations)>1 else (all_recommendations[0] if all_recommendations else {}), f, indent=2)

with open('cys_selectivity.csv','w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['kinase','cysteine','compatible_warhead','predicted_labeling_pct'])
    w.writeheader(); w.writerows(cys_rows)

summary = {'status':'completed', 'compounds':len(all_profiles),
           'profiles': all_profiles, 'recommendations': all_recommendations}
with open('warhead_results.json','w') as f:
    json.dump(summary, f, indent=2)

report = ["=== COVALENT WARHEAD DESIGN REPORT ===", ""]
for p, r in zip(all_profiles, all_recommendations):
    report.append(f"Compound {p['compound']}:")
    if p.get('warhead_detected'):
        report.append(f"  Warhead: {p['warhead_type']} | Reactivity: {p['reactivity_class']}")
        report.append(f"  GSH t1/2: {p.get('GSH_t_half_h','N/A')} h -> {p.get('GSH_reactivity_class','')}")
        report.append(f"  Promiscuity risk: {p.get('promiscuity_risk','')}")
    report.append(f"  -> [{r['verdict']}] {r['recommendation']}")
    report.append("")
with open('warhead_output.txt','w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
covalent_warhead_design:
  python: "3.10"
  rdkit: ">=2023.9"
EOF
    """
}

workflow COVALENT_WARHEAD_WORKFLOW {
    take: meta_ch
    main: COVALENT_WARHEAD_DESIGN(meta_ch)
    emit:
        results     = COVALENT_WARHEAD_DESIGN.out.results
        profile     = COVALENT_WARHEAD_DESIGN.out.profile
        recommendation = COVALENT_WARHEAD_DESIGN.out.recommendation
}

workflow {
    meta = [id: 'covalent_warhead_run', single_end: false]
    Channel.value(meta) | COVALENT_WARHEAD_WORKFLOW
}
