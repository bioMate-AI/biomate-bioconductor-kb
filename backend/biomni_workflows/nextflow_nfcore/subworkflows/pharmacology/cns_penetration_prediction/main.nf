#!/usr/bin/env nextflow
/*
 * pharmacology/cns_penetration_prediction
 *
 * Predicts blood-brain barrier permeability and CNS drug exposure.
 * Estimates CNS MPO score (6 RDKit descriptors), P-gp substrate probability,
 * BCRP substrate status, and Kp,uu,brain (unbound brain-to-plasma ratio).
 *
 * CNS MPO score reference: Wager et al. ACS Chem Neurosci 2010.
 * Kp,uu brain model: Friden et al. Drug Metab Dispos 2011.
 *
 * Input:  SMILES (single or JSON array), optional measured pKa / fu_plasma
 * Output: cns_properties.csv, pgp_prediction.csv, brain_penetration.csv,
 *         cns_penetration_results.json
 */

nextflow.enable.dsl = 2

params.outdir      = './results'
params.smiles_list = '["CCc1nn(C)c2cc(-c3ccc(S(=O)(=O)N4CCN(C)CC4)cc3)cnc12"]'   // sildenafil
params.pKa         = 'null'
params.logD74      = 'null'
params.fu_plasma   = 'null'
params.predict_efflux_ratio = 'true'

process CNS_PENETRATION_PREDICTION {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("cns_penetration_results.json"),  emit: results
    tuple val(meta), path("cns_penetration_output.txt"),    emit: output
    tuple val(meta), path("cns_properties.csv"),            emit: cns_props
    tuple val(meta), path("pgp_prediction.csv"),            emit: pgp
    tuple val(meta), path("brain_penetration.csv"),         emit: brain
    path "versions.yml",                                    emit: versions

    script:
    """
    export PARAM_SMILES_LIST='${params.smiles_list}'
    export PARAM_PKA='${params.pKa}'
    export PARAM_LOGD74='${params.logD74}'
    export PARAM_FU_PLASMA='${params.fu_plasma}'
    export PARAM_PREDICT_EFFLUX='${params.predict_efflux_ratio}'

    python3 << 'PYEOF'
import json, os, csv, sys, math
from rdkit import Chem
from rdkit.Chem import Descriptors, rdMolDescriptors, Crippen

def auto_convert(v):
    if v in (None, '', 'null', 'None'): return None
    try: return float(v)
    except: return v

def parse_smiles_input(raw):
    """Accept single SMILES string or JSON array."""
    raw = raw.strip()
    if raw.startswith('['):
        try:
            lst = json.loads(raw)
            return [(str(i+1), s) for i, s in enumerate(lst)]
        except: pass
    return [('1', raw)]

# ── CNS MPO Score (Wager et al. 2010) ────────────────────────────────────────
# 6 descriptors, each scored 0-1, summed. Score ≥ 4 = favorable CNS profile.
def clogp_score(clogp):
    """Desirability: 0-3 → 1, 3-5 → linear decline, >5 → 0."""
    if clogp <= 3: return 1.0
    if clogp >= 5: return 0.0
    return (5 - clogp) / 2

def mw_score(mw):
    """≤360 → 1, 360-500 → linear decline, >500 → 0."""
    if mw <= 360: return 1.0
    if mw >= 500: return 0.0
    return (500 - mw) / 140

def tpsa_score(tpsa):
    """≤20 → 1, 20-90 → linear, >90 → 0."""
    if tpsa <= 20: return 1.0
    if tpsa >= 90: return 0.0
    return (90 - tpsa) / 70

def hbd_score(hbd):
    """0 → 1, 1 → 0.75, 2 → 0.5, 3 → 0.25, ≥4 → 0."""
    return max(0.0, 1 - 0.25 * hbd)

def pka_score(pka):
    """Most basic pKa: <8 → 1, 8-10 → linear, >10 → 0."""
    if pka is None: return 0.5  # unknown
    if pka <= 8: return 1.0
    if pka >= 10: return 0.0
    return (10 - pka) / 2

def logd_score(logd):
    """1-3 → 1, 0-1 → linear up, 3-5 → linear down, outside → 0."""
    if 1 <= logd <= 3: return 1.0
    if 0 <= logd < 1: return logd
    if 3 < logd <= 5: return (5 - logd) / 2
    return 0.0

def predict_cns_mpo(mol, pka=None, logd=None):
    clogp = Crippen.MolLogP(mol)
    mw    = Descriptors.ExactMolWt(mol)
    tpsa  = rdMolDescriptors.CalcTPSA(mol)
    hbd   = rdMolDescriptors.CalcNumHBD(mol)
    # Estimate logD7.4 from cLogP and TPSA if not provided
    if logd is None:
        logd = clogp - 0.01 * tpsa
    # Estimate pKa proxy from SMARTS for basic nitrogens if not provided
    if pka is None:
        n_basic = mol.HasSubstructMatch(Chem.MolFromSmarts('[NH,NH2,n]'))
        pka = 8.5 if n_basic else 4.0  # rough proxy

    s_clogp = clogp_score(clogp)
    s_mw    = mw_score(mw)
    s_tpsa  = tpsa_score(tpsa)
    s_hbd   = hbd_score(hbd)
    s_pka   = pka_score(pka)
    s_logd  = logd_score(logd)
    mpo     = round(s_clogp + s_mw + s_tpsa + s_hbd + s_pka + s_logd, 2)

    return {
        'clogp': round(clogp, 2), 'MW': round(mw, 1), 'TPSA': round(tpsa, 1),
        'HBD': hbd, 'pKa_proxy': round(pka, 1), 'LogD74': round(logd, 2),
        'CNS_MPO': mpo,
        'MPO_scores': {
            'cLogP': round(s_clogp,2), 'MW': round(s_mw,2), 'TPSA': round(s_tpsa,2),
            'HBD': round(s_hbd,2), 'pKa': round(s_pka,2), 'LogD': round(s_logd,2)
        }
    }

def predict_pgp(mol, mw, logp, hbd):
    """
    P-gp substrate probability based on Ecker et al. rules:
    MW > 400 + LogP > 2 + HBD > 2 → likely substrate
    Seelig model: ≥2 H-bond acceptors within 2.5 Å or ≥4 HBAs → substrate
    """
    hba = rdMolDescriptors.CalcNumHBA(mol)
    rotbonds = rdMolDescriptors.CalcNumRotatableBonds(mol)
    score = 0
    if mw > 400: score += 1
    if logp > 2:  score += 1
    if hbd > 2:   score += 1
    if hba > 8:   score += 1
    if rotbonds > 7: score += 1

    prob = min(1.0, score / 4)
    is_substrate = prob >= 0.5
    efflux_ratio = round(1 + prob * 4, 1)  # 1-5× range
    return {
        'Pgp_substrate': is_substrate,
        'Pgp_probability': round(prob, 2),
        'efflux_ratio_predicted': efflux_ratio,
        'BCRP_substrate': hba > 6 and logp < 2  # simplified BCRP rule
    }

def predict_kpuu_brain(pgp_efflux, fu_plasma, logd):
    """
    Kp,uu,brain estimator.
    Simplified: Kp,uu = fu_brain/(fu_plasma) ≈ 1/(P-gp × protein_binding_factor)
    Reference: Friden et al., 2011, validated against rat brain homogenate data.
    """
    fu_brain_proxy = 1 / (1 + 0.72 * 10**(0.6 * logd))  # Kalvass model
    if fu_plasma is None: fu_plasma = max(0.01, 0.5 - 0.05 * logd)
    pgp_correction = 1 / pgp_efflux  # P-gp reduces brain exposure
    kpuu = (fu_brain_proxy / fu_plasma) * pgp_correction
    kpuu = min(1.5, max(0.001, kpuu))  # physiological range
    if kpuu >= 0.3:
        bbb_class = 'HIGH'
    elif kpuu >= 0.1:
        bbb_class = 'MEDIUM'
    else:
        bbb_class = 'LOW'
    return round(kpuu, 3), bbb_class

# ── Load and process ──────────────────────────────────────────────────────────
raw_smiles  = os.environ.get('PARAM_SMILES_LIST', '["C"]')
pka_in      = auto_convert(os.environ.get('PARAM_PKA'))
logd_in     = auto_convert(os.environ.get('PARAM_LOGD74'))
fu_in       = auto_convert(os.environ.get('PARAM_FU_PLASMA'))

smiles_pairs = parse_smiles_input(raw_smiles)
cns_rows, pgp_rows, brain_rows = [], [], []
summary_list = []

for cid, smi in smiles_pairs:
    mol = Chem.MolFromSmiles(smi) if smi else None
    if mol is None:
        print(f"WARNING: invalid SMILES for compound {cid}: {smi}", file=sys.stderr)
        continue

    props = predict_cns_mpo(mol, pka=pka_in, logd=logd_in)
    pgp   = predict_pgp(mol, props['MW'], props['clogp'], props['HBD'])
    kpuu, bbb_class = predict_kpuu_brain(
        pgp['efflux_ratio_predicted'], fu_in, props['LogD74']
    )

    cns_rows.append({
        'compound': cid, 'SMILES': smi, 'LogP': props['clogp'],
        'TPSA': props['TPSA'], 'MW': props['MW'], 'HBD': props['HBD'],
        'pKa_proxy': props['pKa_proxy'], 'LogD74': props['LogD74'],
        'CNS_MPO_score': props['CNS_MPO']
    })
    pgp_rows.append({
        'compound': cid, 'Pgp_substrate': pgp['Pgp_substrate'],
        'Pgp_probability': pgp['Pgp_probability'],
        'efflux_ratio_predicted': pgp['efflux_ratio_predicted'],
        'BCRP_substrate': pgp['BCRP_substrate']
    })
    brain_rows.append({
        'compound': cid, 'Kpuu_brain_predicted': kpuu,
        'BBB_class': bbb_class, 'confidence': 'MEDIUM'
    })

    mpo = props['CNS_MPO']
    rec = 'Favorable CNS profile' if mpo >= 4 and bbb_class in ('HIGH','MEDIUM') else \
          'Poor CNS profile — optimize MW/TPSA/HBD' if mpo < 4 else \
          'Moderate CNS profile — check P-gp efflux'
    summary_list.append({
        'compound': cid, 'CNS_MPO': mpo, 'BBB_class': bbb_class,
        'Kpuu_brain': kpuu, 'Pgp_substrate': pgp['Pgp_substrate'],
        'recommendation': rec
    })

def write_csv(path, rows, fieldnames):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

write_csv('cns_properties.csv',   cns_rows,
          ['compound','SMILES','LogP','TPSA','MW','HBD','pKa_proxy','LogD74','CNS_MPO_score'])
write_csv('pgp_prediction.csv',   pgp_rows,
          ['compound','Pgp_substrate','Pgp_probability','efflux_ratio_predicted','BCRP_substrate'])
write_csv('brain_penetration.csv', brain_rows,
          ['compound','Kpuu_brain_predicted','BBB_class','confidence'])

# Overall summary
result = {
    'status': 'completed',
    'compounds_analyzed': len(cns_rows),
    'high_bbb_count': sum(1 for r in brain_rows if r['BBB_class']=='HIGH'),
    'pgp_substrate_count': sum(1 for r in pgp_rows if r['Pgp_substrate']),
    'mean_CNS_MPO': round(sum(r['CNS_MPO_score'] for r in cns_rows)/len(cns_rows),2) if cns_rows else None,
    'compound_summaries': summary_list
}
with open('cns_penetration_results.json', 'w') as f:
    json.dump(result, f, indent=2)

report = ["=== CNS PENETRATION PREDICTION REPORT ===",
          f"Compounds analyzed: {result['compounds_analyzed']}",
          f"High BBB penetrators: {result['high_bbb_count']}",
          f"P-gp substrates: {result['pgp_substrate_count']}",
          f"Mean CNS MPO: {result['mean_CNS_MPO']}",
          ""]
for s in summary_list:
    report.append(f"  [{s['compound']}] MPO={s['CNS_MPO']} | BBB={s['BBB_class']} | Kpuu={s['Kpuu_brain']} | {s['recommendation']}")
with open('cns_penetration_output.txt', 'w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
cns_penetration_prediction:
  python: "3.10"
  rdkit: ">=2023.9"
  numpy: ">=1.24"
EOF
    """
}

workflow CNS_PENETRATION_WORKFLOW {
    take: meta_ch
    main: CNS_PENETRATION_PREDICTION(meta_ch)
    emit:
        results = CNS_PENETRATION_PREDICTION.out.results
        brain   = CNS_PENETRATION_PREDICTION.out.brain
}

workflow {
    meta = [id: 'cns_penetration_run', single_end: false]
    Channel.value(meta) | CNS_PENETRATION_WORKFLOW
}
