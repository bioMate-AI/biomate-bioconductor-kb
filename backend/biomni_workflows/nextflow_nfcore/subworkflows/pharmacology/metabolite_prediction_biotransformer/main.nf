#!/usr/bin/env nextflow
/*
 * pharmacology/metabolite_prediction_biotransformer
 *
 * Predicts phase I and phase II metabolites of small molecules using
 * SMARTS-based transformation rules (BioTransformer-style).
 *
 * Phase I:  CYP-mediated reactions -- aliphatic/aromatic hydroxylation,
 *           N-/O-dealkylation, N-oxidation, epoxidation, sulfoxidation,
 *           reduction (ketone/nitro), hydrolysis (ester/amide).
 * Phase II: UGT glucuronidation, SULT sulfation, NAT acetylation,
 *           GST glutathione conjugation, COMT methylation.
 * Gut MBT:  Gut microbiota hydrolyse glucuronides, dehydroxylate,
 *           demethylate.
 *
 * Rule library derived from BioTransformer 3.0 transformation rules
 * (Djoumbou-Feunang et al. J Cheminform 2019) and MetaboPredict.
 *
 * Input:  SMILES (single or JSON array), metabolism_type
 * Output: metabolites.csv, metabolite_tree.json
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.smiles_list     = '["CC(=O)Oc1ccccc1C(=O)O"]'  // aspirin
params.metabolism_type = 'phase1_2'  // phase1 | phase2 | gutmbt | phase1_2 | allHuman
params.max_cycles      = '2'         // number of metabolic cycles (1-3)
params.min_confidence  = '0.5'       // minimum reaction confidence to include

process METABOLITE_PREDICTION_BIOTRANSFORMER {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("metabolite_results.json"),  emit: results
    tuple val(meta), path("metabolites.csv"),          emit: metabolites
    tuple val(meta), path("metabolite_tree.json"),     emit: tree
    tuple val(meta), path("metabolism_output.txt"),    emit: output
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_SMILES='${params.smiles_list}'
    export PARAM_MET_TYPE='${params.metabolism_type}'
    export PARAM_MAX_CYCLES='${params.max_cycles}'
    export PARAM_MIN_CONF='${params.min_confidence}'

    python3 << 'PYEOF'
import json, os, csv, sys, hashlib
from rdkit import Chem
from rdkit.Chem import AllChem, Descriptors, rdMolDescriptors

def auto_convert(v, default=None):
    if v in (None,'','null','None'): return default
    try: return int(v)
    except:
        try: return float(v)
        except: return v

def parse_smiles_input(raw):
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i,s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# -- Reaction SMARTS library (BioTransformer 3.0 rule-derived) ---------------
# Format: (reaction_name, substrate_SMARTS, product_SMARTS, CYP/enzyme, confidence, type)
PHASE1_RXNS = [
    # Aliphatic hydroxylation
    ('aliphatic_hydroxylation',
     '[CX4;!\$(C=O);!\$(C[OH])][H]',
     '[CX4:1][OH]',
     'CYP3A4/CYP2D6', 0.70, 'phase1'),
    # Aromatic hydroxylation
    ('aromatic_hydroxylation',
     '[cH:1]1[cH][cH][cH][cH][cH]1',
     '[c:1]1[cH][cH][cH][cH][c]([OH])1',
     'CYP1A2/CYP2C9', 0.75, 'phase1'),
    # N-demethylation
    ('N_demethylation',
     '[N;!\$(N=O):1][CH3]',
     '[NH:1]',
     'CYP3A4/CYP1A2', 0.85, 'phase1'),
    # O-demethylation
    ('O_demethylation',
     '[O:1][CH3]',
     '[OH:1]',
     'CYP2D6/CYP3A4', 0.80, 'phase1'),
    # N-oxidation (tertiary amines)
    ('N_oxidation',
     '[N:1]([CX4])([CX4])[CX4]',
     '[N+:1]([CX4])([CX4])[CX4][O-]',
     'CYP3A4/FMO', 0.65, 'phase1'),
    # Sulfoxidation
    ('sulfoxidation',
     '[#16:1]([CX4])[CX4]',
     '[#16:1](=[O])([CX4])[CX4]',
     'CYP3A4/FMO', 0.70, 'phase1'),
    # Ester hydrolysis -- produces the alcohol/phenol fragment attached to original carbon
    ('ester_hydrolysis',
     '[CX3](=[O])[O:2][#6:3]',
     '[OH:2][#6:3]',
     'CES1/CES2', 0.90, 'phase1'),
    # Amide hydrolysis -- generates free acid
    ('amide_hydrolysis',
     '[CX3:1](=[O])[NX3H]',
     '[CX3:1](=[O])[OH]',
     'CES1', 0.65, 'phase1'),
    # Ketone reduction
    ('ketone_reduction',
     '[CX3:1](=[O])[CX4]',
     '[CX4:1]([OH])[CX4]',
     'AKR/CBR', 0.60, 'phase1'),
    # Epoxidation (phenyl)
    ('epoxidation',
     'c1ccccc1',
     'C1CC(O1)c1ccccc1',
     'CYP1A2', 0.55, 'phase1'),
]

PHASE2_RXNS = [
    # O-glucuronidation (phenols, alcohols)
    ('O_glucuronidation',
     '[OH:1][c,CX4]',
     '[O:1]C1OC(C(O)C(O)C1O)C(=O)O',
     'UGT', 0.85, 'phase2'),
    # N-glucuronidation (secondary amines)
    ('N_glucuronidation',
     '[NH:1][c,CX4]',
     '[N:1]C1OC(C(O)C(O)C1O)C(=O)O',
     'UGT1A4', 0.70, 'phase2'),
    # O-sulfation (phenols)
    ('O_sulfation',
     '[OH:1][c]',
     '[O:1]S(=O)(=O)[OH]',
     'SULT1A1', 0.80, 'phase2'),
    # N-acetylation (primary aromatic amines)
    ('N_acetylation',
     '[NH2:1][c]',
     '[NH:1]C(=O)C',
     'NAT1/NAT2', 0.75, 'phase2'),
    # O-methylation (catechols)
    ('O_methylation',
     '[OH:1]c1cc([OH])ccc1',
     '[O:1](C)c1cc([OH])ccc1',
     'COMT', 0.80, 'phase2'),
    # GSH conjugation (Michael acceptors)
    ('GSH_conjugation',
     '[CX3:1]=[CX3][CX3]=[O]',
     '[CX4:1](SCC(NC(=O)CCC(N)C(=O)O)C(=O)O)',
     'GST', 0.70, 'phase2'),
]

GUT_RXNS = [
    # Glucuronide hydrolysis
    ('glucuronide_hydrolysis',
     '[O,N:1]C1OC(C(O)C(O)C1O)C(=O)O',
     '[OH,NH:1]',
     'BetaGlucuronidase', 0.90, 'gutmbt'),
    # O-dehydroxylation
    ('dehydroxylation',
     '[OH:1][c]',
     '[H:1][c]',
     'BacterialDehydroxylase', 0.55, 'gutmbt'),
    # De-methylation (gut microbiota)
    ('gut_demethylation',
     '[O:1][CH3]',
     '[OH:1]',
     'BacterialDemethylase', 0.60, 'gutmbt'),
]

ALL_RXNS = PHASE1_RXNS + PHASE2_RXNS + GUT_RXNS

def apply_reaction(mol, rxn_smarts_substr, rxn_smarts_prod, rxn_name):
    '''Try to apply a single-step reaction SMARTS. Returns list of product molecules.'''
    try:
        rxn_str = f'{rxn_smarts_substr}>>{rxn_smarts_prod}'
        rxn = AllChem.ReactionFromSmarts(rxn_str)
        if rxn is None:
            return []
        products = rxn.RunReactants((mol,))
        result = []
        for prod_tuple in products:
            for p in prod_tuple:
                try:
                    Chem.SanitizeMol(p)
                    smi = Chem.MolToSmiles(p)
                    if smi and smi != Chem.MolToSmiles(mol):
                        result.append(smi)
                except: pass
        return list(set(result))
    except: return []

def compute_metabolite(smi, met_type, max_cycles, min_conf):
    '''
    Run BioTransformer-style metabolite prediction.
    Returns list of metabolite dicts with SMILES, pathway, enzyme, confidence.
    '''
    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        return []

    # Select reaction set based on metabolism type
    rxn_pool = []
    if met_type in ('phase1', 'phase1_2', 'allHuman'):
        rxn_pool += PHASE1_RXNS
    if met_type in ('phase2', 'phase1_2', 'allHuman'):
        rxn_pool += PHASE2_RXNS
    if met_type in ('gutmbt', 'allHuman'):
        rxn_pool += GUT_RXNS

    seen  = {Chem.MolToSmiles(mol)}
    queue = [(mol, smi, 0, 'parent', 'none', 1.0)]
    all_metabolites = []

    while queue:
        cur_mol, cur_smi, depth, parent_smi, parent_rxn, parent_conf = queue.pop(0)
        if depth >= max_cycles:
            continue
        for (rxn_name, substr_smarts, prod_smarts, enzyme, confidence, rtype) in rxn_pool:
            if confidence < min_conf:
                continue
            try:
                products = apply_reaction(cur_mol, substr_smarts, prod_smarts, rxn_name)
            except:
                products = []
            for psmi in products:
                if psmi in seen:
                    continue
                seen.add(psmi)
                combined_conf = round(parent_conf * confidence, 3)
                pmol = Chem.MolFromSmiles(psmi)
                if pmol is None:
                    continue
                mw = round(Descriptors.ExactMolWt(pmol), 2)
                entry = {
                    'metabolite_smiles': psmi,
                    'parent_smiles': cur_smi,
                    'reaction': rxn_name,
                    'enzyme': enzyme,
                    'reaction_type': rtype,
                    'confidence': combined_conf,
                    'generation': depth + 1,
                    'MW': mw
                }
                all_metabolites.append(entry)
                if combined_conf >= min_conf and depth + 1 < max_cycles:
                    try:
                        queue.append((pmol, psmi, depth+1, cur_smi, rxn_name, combined_conf))
                    except: pass

    return all_metabolites

# -- Main ----------------------------------------------------------------------
raw_smiles = os.environ.get('PARAM_SMILES', '["C"]')
met_type   = os.environ.get('PARAM_MET_TYPE', 'phase1_2')
max_cycles = int(os.environ.get('PARAM_MAX_CYCLES', '2'))
min_conf   = float(os.environ.get('PARAM_MIN_CONF', '0.5'))

smiles_pairs = parse_smiles_input(raw_smiles)
all_rows = []
trees    = {}

for cid, smi in smiles_pairs:
    mets = compute_metabolite(smi, met_type, max_cycles, min_conf)
    for m in mets:
        all_rows.append({'compound': cid, 'parent_smiles': smi, **m})
    trees[cid] = {
        'parent': smi, 'metabolism_type': met_type,
        'n_metabolites': len(mets),
        'metabolites': mets
    }

# Write metabolites CSV
with open('metabolites.csv', 'w', newline='') as f:
    fieldnames = ['compound','parent_smiles','metabolite_smiles','reaction','enzyme',
                  'reaction_type','confidence','generation','MW']
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    for row in all_rows:
        w.writerow({k: row.get(k,'') for k in fieldnames})

# Write metabolite tree JSON
with open('metabolite_tree.json', 'w') as f:
    json.dump(trees, f, indent=2)

# Write summary results
summary = {
    'status': 'completed',
    'compounds_processed': len(smiles_pairs),
    'total_metabolites': len(all_rows),
    'metabolism_type': met_type,
    'max_cycles': max_cycles,
    'per_compound': {cid: {'n_metabolites': len([r for r in all_rows if r['compound']==cid]),
                            'reactions_applied': list(set(r['reaction'] for r in all_rows if r['compound']==cid))}
                     for cid, _ in smiles_pairs}
}
with open('metabolite_results.json', 'w') as f:
    json.dump(summary, f, indent=2)

# Write text report
report = [f"=== METABOLITE PREDICTION REPORT ===",
          f"Metabolism type: {met_type} | Max cycles: {max_cycles}", ""]
for cid, smi in smiles_pairs:
    cid_rows = [r for r in all_rows if r['compound'] == cid]
    report.append(f"Compound {cid}: {smi}")
    report.append(f"  Total metabolites predicted: {len(cid_rows)}")
    for rtype in ('phase1','phase2','gutmbt'):
        rt_rows = [r for r in cid_rows if r['reaction_type'] == rtype]
        if rt_rows:
            report.append(f"  {rtype}: {len(rt_rows)} metabolite(s)")
            for m in sorted(rt_rows, key=lambda x: -x['confidence'])[:5]:
                report.append(f"    [{m['reaction']} via {m['enzyme']}, conf={m['confidence']:.2f}] -> {m['metabolite_smiles']}")
    report.append("")

with open('metabolism_output.txt', 'w') as f:
    f.write('\\n'.join(report))
print('\\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
metabolite_prediction_biotransformer:
  python: "3.10"
  rdkit: ">=2023.9"
  rule_source: "BioTransformer3.0 rule-derived SMARTS"
EOF
    """
}

workflow METABOLITE_PREDICTION_WORKFLOW {
    take: meta_ch
    main: METABOLITE_PREDICTION_BIOTRANSFORMER(meta_ch)
    emit:
        results    = METABOLITE_PREDICTION_BIOTRANSFORMER.out.results
        metabolites = METABOLITE_PREDICTION_BIOTRANSFORMER.out.metabolites
        tree       = METABOLITE_PREDICTION_BIOTRANSFORMER.out.tree
}

workflow {
    meta = [id: 'metabolite_run', single_end: false]
    Channel.value(meta) | METABOLITE_PREDICTION_WORKFLOW
}
