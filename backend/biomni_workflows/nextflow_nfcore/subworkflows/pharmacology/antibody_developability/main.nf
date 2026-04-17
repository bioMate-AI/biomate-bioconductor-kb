#!/usr/bin/env nextflow
/*
 * pharmacology/antibody_developability
 *
 * In silico developability assessment for antibody and biologic drug candidates.
 * Predicts aggregation propensity, deamidation/oxidation liabilities, FcRn
 * binding (pH-dependent half-life), and isoelectric point from amino acid
 * sequence or CDR loop sequences.
 *
 * Models:
 *   Aggregation: CamSol-inspired hydrophobicity patch scoring (Sormanni 2015)
 *   Deamidation: NG/NS/DG motifs in CDRs (Vlasak 2009; Yan 2009)
 *   Oxidation: Met/Trp/Tyr in exposed positions (Houde 2011)
 *   pI: Henderson-Hasselbalch from pKa residues
 *   FcRn: pI-based half-life model (Deng 2012; Roopenian 2007)
 *
 * Input:  full_sequence or CDR sequences (HCDR1/2/3, LCDR1/2/3),
 *         antibody_format (IgG1/IgG4/scFv/bispecific), target_indication
 * Output: developability_scores.json, liability_scan.csv, developability_report.txt
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
params.full_sequence     = ''
params.hcdr1             = 'GFTFSSY'
params.hcdr2             = 'ISYDGSN'
params.hcdr3             = 'ARGIYGHY'
params.lcdr1             = 'QSIVHSNGNTYLE'
params.lcdr2             = 'KVSNRFS'
params.lcdr3             = 'FQGSHVPLT'
params.antibody_format   = 'IgG1'
params.target_indication = 'oncology'
params.dose_mg_kg        = '10'

process ANTIBODY_DEVELOPABILITY {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("ab_dev_results.json"),          emit: results
    tuple val(meta), path("ab_dev_output.txt"),            emit: output
    tuple val(meta), path("developability_scores.json"),   emit: scores
    tuple val(meta), path("liability_scan.csv"),           emit: liability
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_SEQ='${params.full_sequence}'
    export PARAM_HCDR1='${params.hcdr1}'
    export PARAM_HCDR2='${params.hcdr2}'
    export PARAM_HCDR3='${params.hcdr3}'
    export PARAM_LCDR1='${params.lcdr1}'
    export PARAM_LCDR2='${params.lcdr2}'
    export PARAM_LCDR3='${params.lcdr3}'
    export PARAM_FORMAT='${params.antibody_format}'
    export PARAM_INDICATION='${params.target_indication}'
    export PARAM_DOSE='${params.dose_mg_kg}'

    python3 << 'PYEOF'
import json, os, csv, sys, math, re

def ac(v, default=None):
    if v in (None,'','null','None'): return default
    try: return float(v)
    except: return default

# ── Residue physicochemical properties ────────────────────────────────────────
# Hydrophobicity (Kyte-Doolittle scale, normalised 0–1)
HYDROPHOBICITY = {
    'A': 0.62, 'R': -2.53, 'N': -0.78, 'D': -0.90, 'C': 0.29,
    'Q': -0.85, 'E': -0.74, 'G': 0.48, 'H': -0.40, 'I': 1.38,
    'L': 1.06, 'K': -1.50, 'M': 0.64, 'F': 1.19, 'P': 0.12,
    'S': -0.18, 'T': -0.05, 'W': 0.81, 'Y': 0.26, 'V': 1.08,
}

# pKa values for charged residues (Henderson-Hasselbalch for pI)
PKA_RESIDUES = {
    'D': 3.9, 'E': 4.1, 'C': 8.3, 'Y': 10.1,
    'H': 6.0, 'K': 10.5, 'R': 12.5,
    'N_term': 8.0, 'C_term': 3.1,
}

# ── pI calculation ─────────────────────────────────────────────────────────────
def compute_pI(sequence):
    """Isoelectric point via charge pH titration."""
    seq = sequence.upper()
    counts = {aa: seq.count(aa) for aa in PKA_RESIDUES if aa in seq}
    n_asp = seq.count('D')
    n_glu = seq.count('E')
    n_cys = seq.count('C')
    n_tyr = seq.count('Y')
    n_his = seq.count('H')
    n_lys = seq.count('K')
    n_arg = seq.count('R')

    def charge_at_ph(ph):
        # Positive charges
        pos = (1 / (1 + 10**(ph - PKA_RESIDUES['N_term'])) +
               n_his * (1 / (1 + 10**(ph - PKA_RESIDUES['H']))) +
               n_lys * (1 / (1 + 10**(ph - PKA_RESIDUES['K']))) +
               n_arg * (1 / (1 + 10**(ph - PKA_RESIDUES['R']))))
        # Negative charges
        neg = (1 / (1 + 10**(PKA_RESIDUES['C_term'] - ph)) +
               n_asp * (1 / (1 + 10**(PKA_RESIDUES['D'] - ph))) +
               n_glu * (1 / (1 + 10**(PKA_RESIDUES['E'] - ph))) +
               n_cys * (1 / (1 + 10**(PKA_RESIDUES['C'] - ph))) +
               n_tyr * (1 / (1 + 10**(PKA_RESIDUES['Y'] - ph))))
        return pos - neg

    # Binary search for pI
    lo, hi = 0.0, 14.0
    for _ in range(100):
        mid = (lo + hi) / 2
        if charge_at_ph(mid) > 0:
            lo = mid
        else:
            hi = mid
    return round((lo + hi) / 2, 2)

# ── Aggregation propensity (CamSol proxy) ─────────────────────────────────────
def aggregation_score(cdrs_combined):
    """
    Simplified CamSol-like score: hydrophobic patches in CDR sequences.
    Score > 1.0 = aggregation-prone; < -1.0 = well-behaved.
    Based on mean hydrophobicity of sliding window over CDRs.
    """
    if not cdrs_combined:
        return 0.0, 'UNKNOWN'
    seq = cdrs_combined.upper()
    window = 7
    scores = []
    for i in range(len(seq) - window + 1):
        w = seq[i:i+window]
        mean_h = sum(HYDROPHOBICITY.get(aa, 0) for aa in w) / window
        scores.append(mean_h)
    if not scores:
        return 0.0, 'UNKNOWN'
    max_score = max(scores)
    mean_score = sum(scores) / len(scores)
    # Overall score: combination of peak and mean
    agg_score = round(max_score * 0.6 + mean_score * 0.4, 3)
    if agg_score > 0.6:
        risk = 'HIGH — likely aggregation-prone; consider sequence engineering'
    elif agg_score > 0.3:
        risk = 'MEDIUM — moderate hydrophobicity; monitor HIC/SEC at high concentration'
    else:
        risk = 'LOW — acceptable hydrophobicity profile'
    return agg_score, risk

# ── Deamidation liability (Vlasak 2009; Yan 2009) ─────────────────────────────
DEAMID_MOTIFS = [
    ('NG', 2, 'HIGH',   'NG dipeptide — primary deamidation hotspot in CDRs (t½ ~1 day at pH 7.4)'),
    ('NS', 1, 'MEDIUM', 'NS motif — moderate deamidation risk (t½ ~3 days)'),
    ('DG', 1, 'MEDIUM', 'DG motif — isomerisation (aspartate → isoaspartate)'),
    ('DD', 1, 'LOW',    'DD motif — minor deamidation in acidic conditions'),
    ('QN', 1, 'LOW',    'QN motif — glutamine deamidation (slower than N)'),
]

def scan_deamidation(cdr_seqs):
    hits = []
    for cdr_name, seq in cdr_seqs.items():
        seq_u = seq.upper()
        for motif, score, severity, desc in DEAMID_MOTIFS:
            pos = [i for i in range(len(seq_u)-1) if seq_u[i:i+len(motif)] == motif]
            for p in pos:
                hits.append({'cdr': cdr_name, 'motif': motif, 'position': p+1,
                             'severity': severity, 'description': desc})
    return hits

# ── Oxidation liability (Houde 2011) ──────────────────────────────────────────
OXID_RESIDUES = [
    ('M', 'MEDIUM', 'Methionine — oxidation to Met-sulfoxide; critical in Fc (M252, M428)'),
    ('W', 'HIGH',   'Tryptophan — photodegradation; W32/W52 in CDRs are hotspots'),
    ('Y', 'LOW',    'Tyrosine — minor oxidation at high stress'),
    ('H', 'LOW',    'Histidine — copper-catalysed oxidation in acidic conditions'),
]

def scan_oxidation(combined_seq):
    hits = []
    for aa, severity, desc in OXID_RESIDUES:
        positions = [i+1 for i, c in enumerate(combined_seq.upper()) if c == aa]
        if positions:
            hits.append({'residue': aa, 'positions': positions,
                         'count': len(positions), 'severity': severity, 'description': desc})
    return hits

# ── FcRn binding model (Deng 2012) ────────────────────────────────────────────
def fcRn_halflife(pI, antibody_format):
    """
    Approximate serum half-life (days) from pI.
    IgG1/IgG4 optimal pI: 6-8 (FcRn binding at pH 6, release at 7.4)
    Very high pI (>9) → non-specific binding, faster clearance
    Very low pI (<5) → poor FcRn binding
    scFv/bispecific: shorter baseline t½
    """
    if antibody_format in ('IgG1', 'IgG4', 'IgG2'):
        baseline = 21  # days
    elif antibody_format in ('scFv',):
        baseline = 0.2  # days (renal clearance dominant)
    elif antibody_format in ('bispecific', 'IgG1-bispecific'):
        baseline = 14
    else:
        baseline = 14

    # pI penalty
    if pI < 5.5:
        pI_factor = 0.5
    elif pI < 6.5:
        pI_factor = 0.85
    elif pI <= 8.5:
        pI_factor = 1.0
    elif pI <= 9.5:
        pI_factor = 0.85
    else:
        pI_factor = 0.60  # highly cationic → non-specific clearance

    return round(baseline * pI_factor, 1)

# ── Viscosity risk ─────────────────────────────────────────────────────────────
def viscosity_risk(agg_score, pI):
    if agg_score > 0.6 and (pI < 6 or pI > 9):
        return 'HIGH — aggregation-prone + pI near extremes; SC delivery may be challenging'
    if agg_score > 0.3 or pI > 8.5:
        return 'MEDIUM — monitor viscosity at ≥100 mg/mL for SC formulation'
    return 'LOW — acceptable for SC/IV formulation development'

# ── Process ───────────────────────────────────────────────────────────────────
full_seq   = os.environ.get('PARAM_SEQ', '').strip()
hcdr1      = os.environ.get('PARAM_HCDR1', '')
hcdr2      = os.environ.get('PARAM_HCDR2', '')
hcdr3      = os.environ.get('PARAM_HCDR3', '')
lcdr1      = os.environ.get('PARAM_LCDR1', '')
lcdr2      = os.environ.get('PARAM_LCDR2', '')
lcdr3      = os.environ.get('PARAM_LCDR3', '')
ab_format  = os.environ.get('PARAM_FORMAT', 'IgG1')
indication = os.environ.get('PARAM_INDICATION', 'oncology')
dose       = ac(os.environ.get('PARAM_DOSE'), 10)

cdr_seqs = {}
for name, seq in [('HCDR1', hcdr1), ('HCDR2', hcdr2), ('HCDR3', hcdr3),
                   ('LCDR1', lcdr1), ('LCDR2', lcdr2), ('LCDR3', lcdr3)]:
    if seq:
        cdr_seqs[name] = seq

cdrs_combined = ''.join(cdr_seqs.values())
if full_seq:
    analysis_seq = full_seq
    seq_source = 'full_sequence'
elif cdrs_combined:
    analysis_seq = cdrs_combined
    seq_source = 'CDR_sequences'
else:
    analysis_seq = 'EVQLVESGGGLVQPGGSLRLSCAASGFTFSSY'  # placeholder
    seq_source = 'placeholder'
    print("WARNING: no sequence provided, using placeholder", file=sys.stderr)

# pI from full sequence if available, else from CDRs + typical Fc pI ~8.0
if full_seq:
    pI = compute_pI(full_seq)
    pI_source = 'full sequence'
elif cdrs_combined:
    pI_cdrs = compute_pI(cdrs_combined)
    pI = round(0.5 * pI_cdrs + 0.5 * 8.0, 2)  # blend with typical Fc
    pI_source = 'CDRs + typical Fc blend'
else:
    pI = 8.0
    pI_source = 'default IgG typical'

# Aggregation
agg_score, agg_risk = aggregation_score(cdrs_combined or analysis_seq[:60])

# Liabilities
deamid_hits  = scan_deamidation(cdr_seqs if cdr_seqs else {'CDRs': analysis_seq[:60]})
oxid_hits    = scan_oxidation(cdrs_combined or analysis_seq[:60])
fcRn_t_half  = fcRn_halflife(pI, ab_format)
visc_risk    = viscosity_risk(agg_score, pI)

# Risk summary
n_high_deamid = sum(1 for h in deamid_hits if h['severity'] == 'HIGH')
n_high_oxid   = sum(1 for h in oxid_hits   if h['severity'] == 'HIGH')

if n_high_deamid > 1 or n_high_oxid > 1 or agg_score > 0.6:
    overall_risk = 'HIGH — immediate engineering required before IND'
elif n_high_deamid > 0 or n_high_oxid > 0 or agg_score > 0.3:
    overall_risk = 'MEDIUM — address before Phase I; monitor stability'
else:
    overall_risk = 'LOW — acceptable developability profile; standard stability studies'

scores = {
    'antibody_format': ab_format,
    'target_indication': indication,
    'sequence_source': seq_source,
    'pI': pI,
    'pI_source': pI_source,
    'aggregation_score_CamSol_proxy': agg_score,
    'aggregation_risk': agg_risk,
    'FcRn_predicted_halflife_days': fcRn_t_half,
    'viscosity_risk': visc_risk,
    'deamidation_liabilities': deamid_hits,
    'oxidation_liabilities': oxid_hits,
    'overall_developability_risk': overall_risk,
    'recommended_actions': [
        f'Confirm pI ({pI:.1f}) by IEF; target range 6.5–8.5 for optimal FcRn',
        f'HIC-HPLC aggregation screen at 10 mg/mL (predicted score {agg_score:.2f})',
    ] + (
        [f'Engineer {sum(1 for h in deamid_hits if h["severity"]=="HIGH")} NG/NS deamidation site(s) in CDRs'] if n_high_deamid else []
    ) + (
        ['Protect Met residues in Fc CH2 domain (antioxidant in formulation buffer)'] if n_high_oxid else []
    )
}

# CSV liability scan
csv_rows = [['region', 'liability_type', 'motif_or_residue', 'position', 'severity', 'description']]
for h in deamid_hits:
    csv_rows.append([h['cdr'], 'deamidation', h['motif'], h['position'], h['severity'], h['description']])
for h in oxid_hits:
    csv_rows.append(['combined_CDRs', 'oxidation', h['residue'], str(h['positions']), h['severity'], h['description']])

with open('developability_scores.json', 'w') as f:
    json.dump(scores, f, indent=2)
with open('liability_scan.csv', 'w', newline='') as f:
    csv.writer(f).writerows(csv_rows)
with open('ab_dev_results.json', 'w') as f:
    json.dump({'status': 'completed', **scores}, f, indent=2)

report = [
    f'=== ANTIBODY DEVELOPABILITY ASSESSMENT ({ab_format}) ===', '',
    f'Format: {ab_format} | Indication: {indication} | pI: {pI:.2f} ({pI_source})',
    f'FcRn-predicted t½: {fcRn_t_half} days',
    f'Aggregation score: {agg_score:.3f} — {agg_risk}',
    f'Viscosity risk: {visc_risk}', '',
    f'Deamidation: {len(deamid_hits)} liabilities ({n_high_deamid} HIGH)',
    f'Oxidation:   {len(oxid_hits)} liabilities ({n_high_oxid} HIGH)',
    '', f'OVERALL: {overall_risk}', '',
    'Recommended actions:',
]
for action in scores['recommended_actions']:
    report.append(f'  • {action}')
with open('ab_dev_output.txt', 'w') as f:
    f.write('\n'.join(report))
print('\n'.join(report))
PYEOF

    cat << 'EOF' > versions.yml
antibody_developability:
  python: "3.10"
  models: "CamSol proxy, Vlasak 2009 deamidation, Deng 2012 FcRn"
EOF
    """
}

workflow ANTIBODY_DEVELOPABILITY_WORKFLOW {
    take: meta_ch
    main: ANTIBODY_DEVELOPABILITY(meta_ch)
    emit:
        results  = ANTIBODY_DEVELOPABILITY.out.results
        scores   = ANTIBODY_DEVELOPABILITY.out.scores
        liability = ANTIBODY_DEVELOPABILITY.out.liability
}

workflow {
    meta = [id: 'ab_dev_run', single_end: false]
    Channel.value(meta) | ANTIBODY_DEVELOPABILITY_WORKFLOW
}
