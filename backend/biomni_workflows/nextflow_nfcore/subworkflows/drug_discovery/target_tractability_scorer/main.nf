#!/usr/bin/env nextflow
/*
 * drug_discovery/target_tractability_scorer
 *
 * Scores a protein target's tractability for small molecule and biologic
 * drug discovery. Combines protein family tractability (kinase/GPCR/NHR
 * favourable; PPI/transcription factor challenging), pocket druggability
 * (volume/hydrophobicity heuristics), and literature/ChEMBL data density.
 *
 * Framework: Oprea et al. 2018 Target Development Level (TDL);
 *            Edfeldt et al. 2011 pocket druggability scoring;
 *            OpenTargets tractability framework (Llabres et al. 2019).
 *
 * Input:  target_name, UniProt_id or sequence, optional pocket_volume_A3,
 *         optional chembl_compound_count
 * Output: tractability_score.json, tractability_report.txt, evidence_table.csv
 */

nextflow.enable.dsl = 2

params.outdir                  = './results'
params.target_name             = 'EGFR'
params.uniprot_id              = 'P00533'
params.protein_class           = 'kinase'
params.pocket_volume_A3        = '800'
params.pocket_druggability_score = 'null'
params.chembl_compound_count   = 'null'
params.has_crystal_structure   = 'true'
params.has_endogenous_ligand   = 'false'
params.disease_association_score = '0.8'

process TARGET_TRACTABILITY_SCORER {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("tractability_results.json"),    emit: results
    tuple val(meta), path("tractability_output.txt"),      emit: output
    tuple val(meta), path("tractability_score.json"),      emit: score
    tuple val(meta), path("evidence_table.csv"),           emit: evidence
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_TARGET='${params.target_name}'
    export PARAM_UNIPROT='${params.uniprot_id}'
    export PARAM_CLASS='${params.protein_class}'
    export PARAM_POCKET_VOL='${params.pocket_volume_A3}'
    export PARAM_POCKET_DS='${params.pocket_druggability_score}'
    export PARAM_CHEMBL_COUNT='${params.chembl_compound_count}'
    export PARAM_HAS_CRYSTAL='${params.has_crystal_structure}'
    export PARAM_HAS_LIGAND='${params.has_endogenous_ligand}'
    export PARAM_DISEASE_SCORE='${params.disease_association_score}'

    python3 << 'PYEOF'
import json, os, csv, sys

def auto_bool(v, default=False):
    if v in (None,'','null','None'): return default
    return v.lower() in ('true','1','yes')

def auto_float(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

def auto_int(v, default=None):
    if v in (None,'','null','None'): return default
    try: return int(float(v))
    except: return default

# -- Protein class tractability (Llabres 2019 + OpenTargets framework) ---------
# Scores 0-1 for small molecule (SM) and biologic (BIO) tractability

SM_CLASS_SCORES = {
    'kinase':           0.95,
    'gpcr':             0.90,
    'nuclear_receptor': 0.88,
    'ion_channel':      0.82,
    'phosphodiesterase':0.80,
    'protease':         0.78,
    'transferase':      0.75,
    'oxidoreductase':   0.70,
    'epigenetic':       0.72,
    'transporter':      0.65,
    'phosphatase':      0.60,
    'ubiquitin_ligase': 0.55,
    'deubiquitinase':   0.52,
    'ppi':              0.30,
    'transcription_factor': 0.28,
    'rna_binding':      0.35,
    'structural':       0.40,
    'unknown':          0.45,
}
BIO_CLASS_SCORES = {
    'kinase':           0.60,
    'gpcr':             0.70,
    'nuclear_receptor': 0.40,
    'ion_channel':      0.50,
    'phosphodiesterase':0.45,
    'protease':         0.75,
    'transferase':      0.55,
    'oxidoreductase':   0.50,
    'epigenetic':       0.40,
    'transporter':      0.65,
    'phosphatase':      0.60,
    'ubiquitin_ligase': 0.70,
    'deubiquitinase':   0.65,
    'ppi':              0.85,
    'transcription_factor': 0.50,
    'rna_binding':      0.60,
    'structural':       0.55,
    'unknown':          0.50,
}

# -- Pocket druggability scoring (Edfeldt 2011 / fpocket heuristics) -----------
def pocket_score_from_volume(vol_A3, has_crystal, has_ligand):
    """
    Druggability score 0-1 from pocket volume.
    Optimal pocket: 300-1000 A3, hydrophobic, well-defined.
    Very large (>1500) or small (<100) = poor druggability.
    """
    if vol_A3 is None:
        return 0.5  # unknown

    if vol_A3 < 100:
        base = 0.15
    elif vol_A3 < 300:
        base = 0.45
    elif vol_A3 < 600:
        base = 0.75
    elif vol_A3 < 1000:
        base = 0.90
    elif vol_A3 < 1500:
        base = 0.80
    elif vol_A3 < 2500:
        base = 0.55
    else:
        base = 0.30  # too large -- flat/open binding site

    # Bonuses
    if has_crystal:
        base = min(1.0, base + 0.05)
    if has_ligand:
        base = min(1.0, base + 0.08)
    return round(base, 3)

# -- ChEMBL data density proxy -------------------------------------------------
def chembl_tractability(n_compounds, has_crystal):
    """
    TDL-based tractability from compound count.
    Tdark: 0; Tbio: 1-10; Tclin: >100; Tchem: >10
    """
    if n_compounds is None:
        return 0.40 if has_crystal else 0.25  # unknown but has structure
    if n_compounds == 0:
        return 0.15
    if n_compounds < 10:
        return 0.40
    if n_compounds < 100:
        return 0.65
    if n_compounds < 1000:
        return 0.82
    return 0.95  # well-validated target

def tdl_from_chembl(n_compounds):
    if n_compounds is None: return 'Tunknown'
    if n_compounds == 0: return 'Tdark'
    if n_compounds < 10: return 'Tbio'
    if n_compounds < 100: return 'Tchem'
    return 'Tclin'

# -- Overall tractability score ------------------------------------------------
# Weighted combination: class=0.35, pocket=0.30, chembl=0.25, disease=0.10
def compute_tractability(class_score, pocket_score, chembl_score, disease_score):
    weights = {'class': 0.35, 'pocket': 0.30, 'chembl': 0.25, 'disease': 0.10}
    return round(
        weights['class'] * class_score +
        weights['pocket'] * pocket_score +
        weights['chembl'] * chembl_score +
        weights['disease'] * disease_score,
        3
    )

def tractability_tier(score):
    if score >= 0.80: return 'HIGH -- Primary target recommendation'
    if score >= 0.65: return 'MEDIUM-HIGH -- Strong follow-up candidate'
    if score >= 0.50: return 'MEDIUM -- Consider with backup target'
    if score >= 0.35: return 'LOW -- Challenging; specialised approaches needed'
    return 'VERY LOW -- Unlikely tractable by conventional means'

# -- Process -------------------------------------------------------------------
target_name  = os.environ.get('PARAM_TARGET', 'unknown')
uniprot_id   = os.environ.get('PARAM_UNIPROT', '')
prot_class   = os.environ.get('PARAM_CLASS', 'unknown').lower().replace(' ','_').replace('-','_')
pocket_vol   = auto_float(os.environ.get('PARAM_POCKET_VOL'))
pocket_ds    = auto_float(os.environ.get('PARAM_POCKET_DS'))
chembl_count = auto_int(os.environ.get('PARAM_CHEMBL_COUNT'))
has_crystal  = auto_bool(os.environ.get('PARAM_HAS_CRYSTAL'), True)
has_ligand   = auto_bool(os.environ.get('PARAM_HAS_LIGAND'), False)
disease_sc   = auto_float(os.environ.get('PARAM_DISEASE_SCORE'), 0.5)

# Score each dimension
sm_class_score = SM_CLASS_SCORES.get(prot_class, SM_CLASS_SCORES['unknown'])
bio_class_score = BIO_CLASS_SCORES.get(prot_class, BIO_CLASS_SCORES['unknown'])

if pocket_ds is not None:
    pocket_sc = min(1.0, max(0.0, pocket_ds))
else:
    pocket_sc = pocket_score_from_volume(pocket_vol, has_crystal, has_ligand)

chembl_sc = chembl_tractability(chembl_count, has_crystal)
tdl       = tdl_from_chembl(chembl_count)

sm_total  = compute_tractability(sm_class_score, pocket_sc, chembl_sc, disease_sc)
bio_total = compute_tractability(bio_class_score, pocket_sc, chembl_sc, disease_sc)

sm_tier   = tractability_tier(sm_total)
bio_tier  = tractability_tier(bio_total)

# Overall recommendation
if sm_total >= bio_total:
    modality_rec = f'Small molecule preferred (score {sm_total:.2f} > biologic {bio_total:.2f})'
else:
    modality_rec = f'Biologic preferred (score {bio_total:.2f} > SM {sm_total:.2f})'

# Challenges and opportunities
challenges = []
opportunities = []
if prot_class in ('ppi', 'transcription_factor'):
    challenges.append('PPI/TF targets require fragment-based or macrocyclic approaches')
if pocket_vol and pocket_vol > 2000:
    challenges.append('Large pocket -- consider PROTACs or degrader strategies')
if pocket_vol and pocket_vol < 200:
    challenges.append('Small/shallow pocket -- limited to covalent or allosteric approaches')
if chembl_count is not None and chembl_count == 0:
    challenges.append('No known ligands -- high chemical biology risk, phenotypic approaches may be needed')
if has_crystal:
    opportunities.append('Crystal structure available -- structure-based drug design feasible')
if has_ligand:
    opportunities.append('Endogenous ligand known -- template for starting point')
if prot_class in ('kinase', 'gpcr', 'nuclear_receptor'):
    opportunities.append(f'{prot_class.upper()} target class -- well-understood pharmacology, known binders')
if tdl in ('Tchem', 'Tclin'):
    opportunities.append(f'ChEMBL TDL {tdl} -- validated binding pocket, chemical matter available')

score_rec = {
    'target': target_name,
    'uniprot_id': uniprot_id,
    'protein_class': prot_class,
    'target_development_level': tdl,
    'tractability_scores': {
        'small_molecule': {
            'overall': sm_total,
            'tier': sm_tier,
            'components': {
                'protein_class_score': sm_class_score,
                'pocket_druggability': pocket_sc,
                'chembl_data_density': chembl_sc,
                'disease_association': disease_sc,
            }
        },
        'biologic': {
            'overall': bio_total,
            'tier': bio_tier,
            'components': {
                'protein_class_score': bio_class_score,
                'pocket_druggability': pocket_sc,
                'chembl_data_density': chembl_sc,
                'disease_association': disease_sc,
            }
        }
    },
    'modality_recommendation': modality_rec,
    'challenges': challenges,
    'opportunities': opportunities,
    'evidence': {
        'pocket_volume_A3': pocket_vol,
        'has_crystal_structure': has_crystal,
        'has_endogenous_ligand': has_ligand,
        'chembl_compound_count': chembl_count,
        'disease_association_score': disease_sc,
    }
}

evidence_rows = [
    ['dimension', 'value', 'score', 'weight_in_SM', 'note'],
    ['Protein class', prot_class, sm_class_score, 0.35, f'From {len(SM_CLASS_SCORES)}-class lookup table'],
    ['Pocket druggability', f'{pocket_vol} A3' if pocket_vol else 'unknown', pocket_sc, 0.30,
     'Volume heuristic (Edfeldt 2011)' if pocket_ds is None else 'User-provided score'],
    ['ChEMBL data density', f'{chembl_count} compounds' if chembl_count is not None else 'unknown', chembl_sc, 0.25,
     f'TDL: {tdl}'],
    ['Disease association', disease_sc, disease_sc, 0.10, 'OpenTargets-scale (0-1)'],
    ['OVERALL SM tractability', '', sm_total, 1.0, sm_tier],
    ['OVERALL biologic tractability', '', bio_total, 1.0, bio_tier],
]

# Write outputs
with open('tractability_score.json', 'w') as f:
    json.dump(score_rec, f, indent=2)

with open('evidence_table.csv', 'w', newline='') as f:
    csv.writer(f).writerows(evidence_rows)

full = {'status': 'completed', 'target': target_name, **score_rec}
with open('tractability_results.json', 'w') as f:
    json.dump(full, f, indent=2)

report = [
    f'=== TARGET TRACTABILITY SCORER: {target_name} ({uniprot_id}) ===', '',
    f'Protein class:    {prot_class.upper()} | TDL: {tdl}',
    f'Crystal struct:   {"YES" if has_crystal else "NO"} | Endogenous ligand: {"YES" if has_ligand else "NO"}',
    f'Pocket volume:    {pocket_vol} A3' if pocket_vol else 'Pocket volume:    unknown',
    f'ChEMBL compounds: {chembl_count if chembl_count is not None else "unknown"}', '',
    f'SMALL MOLECULE:   {sm_total:.2f} -- {sm_tier}',
    f'BIOLOGIC:         {bio_total:.2f} -- {bio_tier}', '',
    f'-> {modality_rec}', '',
    'Opportunities:',
]
for o in opportunities:
    report.append(f'  OK {o}')
if challenges:
    report.append('Challenges:')
    for c in challenges:
        report.append(f'  WARNING {c}')

with open('tractability_output.txt', 'w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
target_tractability_scorer:
  python: "3.10"
  framework: "Oprea TDL 2018 + OpenTargets tractability"
EOF
    """
}

workflow TARGET_TRACTABILITY_WORKFLOW {
    take: meta_ch
    main: TARGET_TRACTABILITY_SCORER(meta_ch)
    emit:
        results = TARGET_TRACTABILITY_SCORER.out.results
        score   = TARGET_TRACTABILITY_SCORER.out.score
}

workflow {
    meta = [id: 'tractability_run', single_end: false]
    Channel.value(meta) | TARGET_TRACTABILITY_WORKFLOW
}
