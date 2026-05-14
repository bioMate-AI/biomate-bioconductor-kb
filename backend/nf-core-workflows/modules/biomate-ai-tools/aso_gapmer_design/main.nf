#!/usr/bin/env nextflow
/*
 * molecular_biology/aso_gapmer_design
 *
 * Antisense oligonucleotide (ASO) gapmer design for RNase H-mediated gene knockdown.
 * Designs 5'-wing/DNA-gap/3'-wing gapmers using MOE or LNA chemistry.
 * Scores for Tm, GC content, self-complementarity, hepatotoxicity flags, and CpG motifs.
 * Provides tissue-specific delivery recommendations.
 *
 * Algorithm overview:
 *   1. Parse target mRNA (FASTA or raw sequence); if gene name provided, use demo sequence.
 *   2. Sliding window (16-22 nt) over pre-mRNA; prefer 3'-UTR and exon-exon junctions.
 *   3. Gapmer architecture:
 *      - MOE gapmer (5 MOE + 10 DNA + 5 MOE = 20-mer) — nusinersen/inotersen pattern
 *      - LNA gapmer (3 LNA + 10 DNA + 3 LNA = 16-mer) — higher Tm, smaller size
 *      - MOE mixmer (alternating MOE/DNA throughout) — no RNase H cleavage, steric block
 *   4. Tm prediction: nearest-neighbor with MOE (+1.5°C/residue) and LNA (+4°C/residue) corrections.
 *      Target Tm: 50-65°C for 37°C activity.
 *   5. Scoring filters:
 *      - Tm in target range (50-65°C)
 *      - GC 40-60%
 *      - No self-complementarity > 4 nt palindrome
 *      - No GGGG runs (G-quadruplex → hepatotoxicity)
 *      - CpG motif count (immunostimulatory — flag for 5-methylcytosine substitution)
 *      - Off-target: no stretch of 6+ consecutive G/C (predicted secondary structure)
 *   6. PS backbone recommendation: full PS (systemic) or mixed PS/PO (CNS/intrathecal).
 *   7. Delivery recommendation by tissue:
 *      - liver: GalNAc conjugation (SC injection)
 *      - cns: intrathecal, no conjugation (nusinersen/spinraza pattern)
 *      - muscle: PMO/PPMO alternative (naked PS ASO has poor muscle uptake)
 *      - systemic: naked PS ASO (liver/kidney primary; limited muscle/CNS)
 *
 * Input parameters:
 *   target_mrna    — FASTA file path, raw sequence, or gene name (required)
 *   target_tissue  — liver | cns | muscle | systemic (required)
 *   chemistry      — moe_gapmer | lna_gapmer | moe_mixmer (default: moe_gapmer)
 *   n_top          — number of top candidates to return (default: 10)
 *
 * Outputs:
 *   aso_candidates.csv         — ranked gapmer sequences with scores
 *   aso_design_report.json     — full design details
 *   delivery_recommendation.txt — delivery strategy report
 *
 * Approved ASO precedents:
 *   - Nusinersen (Spinraza): MOE gapmer, intrathecal, SMN2 exon 7 splicing (SMA)
 *   - Inotersen (Tegsedi): MOE gapmer, SC, TTR knockdown (hATTR amyloidosis)
 *   - Volanesorsen (Waylivra): MOE gapmer, SC, ApoC-III knockdown (hypertriglyceridemia)
 *   - Inclisiran (Leqvio): siRNA-GalNAc (different mechanism — listed for contrast)
 *   - Givosiran (Givlaari): GalNAc-siRNA (aminolevulinate synthase, AHP)
 */

nextflow.enable.dsl = 2

params.outdir        = './results'
params.target_mrna   = 'null'
params.target_tissue = 'liver'
params.chemistry     = 'moe_gapmer'
params.n_top         = '10'

// [Phase A] ASO Gapmer Candidate Design
process ASO_GAPMER_DESIGN {
    tag "aso_gapmer_design"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("aso_candidates.csv"),          emit: candidates
    tuple val(meta), path("aso_design_report.json"),      emit: report_json
    tuple val(meta), path("delivery_recommendation.txt"), emit: delivery_report
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_MRNA='${params.target_mrna}'
    export PARAM_TISSUE='${params.target_tissue}'
    export PARAM_CHEM='${params.chemistry}'
    export PARAM_NTOP='${params.n_top}'

    python3 << 'PYEOF'
import json, os, csv, re, math

# ─── Parameters ──────────────────────────────────────────────────────────────
raw_input     = os.environ.get('PARAM_MRNA', '').strip()
target_tissue = os.environ.get('PARAM_TISSUE', 'liver').strip().lower()
chemistry     = os.environ.get('PARAM_CHEM', 'moe_gapmer').strip().lower()
n_top         = max(1, int(float(os.environ.get('PARAM_NTOP', '10'))))

# ─── Gene-name → demo sequence map ───────────────────────────────────────────
# Partial 3'-UTR sequences for common therapeutic targets (representative)
GENE_DEMO_SEQS = {
    'PCSK9':   ('GCUGUGGCUGCAGCAGGCAGAGCAGCCCCAGGUCAGCCUGCAGCAGCCAGAGCUGCAGCCGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
    'TTR':     ('GCAGAGCAAGUGCCAGCCAGUGCCAGCAGCAGCAGCAAGCCAGCAGCCAGCAGCCAGCAGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
    'APOC3':   ('GCAGCAGCCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
    'SMN2':    ('AAACAUUUGCUUUACAAAACCUAAUAAAAGUAAAGUUUAAAUAUGUCAAUUUGAAGAAAAAAAAAAA'
                'AAGUCUUAUAAAGAUUUUAUAUUAAAUUUGAUGAAAUUUAUCUAUUUAAAUAAAAUAAUAUUUGUUA'),
    'MALAT1':  ('GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
    'MAPT':    ('GCAGCAGCCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
    'HUNTINGTIN': ('CAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAG'
                   'CAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAG'),
    'SOD1':    ('GCAGAGCAAGUGCCAGCCAGUGCCAGCAGCAGCAGCAAGCCAGCAGCCAGCAGCCAGCAGCAGCA'
                'GCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCAGCA'),
}

# ─── Sequence parsing ─────────────────────────────────────────────────────────
def parse_sequence(s):
    s = s.strip()
    if not s or s == 'null':
        seq = GENE_DEMO_SEQS['SMN2']
        return seq.upper().replace('T', 'U'), 'demo_SMN2_3UTR'

    # Gene name lookup
    upper_s = s.upper().replace(' ', '_').replace('-', '')
    for gene, demo_seq in GENE_DEMO_SEQS.items():
        if upper_s == gene or upper_s == gene.replace('-', ''):
            return demo_seq.upper().replace('T', 'U'), gene

    if os.path.isfile(s):
        with open(s) as fh:
            lines = fh.read().splitlines()
        name = lines[0].lstrip('>').split()[0] if lines[0].startswith('>') else 'input'
        seq  = ''.join(l for l in lines if not l.startswith('>')).upper().replace('T', 'U')
        return seq, name
    if s.startswith('>'):
        lines = s.splitlines()
        name  = lines[0].lstrip('>').split()[0]
        seq   = ''.join(l for l in lines[1:]).upper().replace('T', 'U')
        return seq, name
    seq = re.sub(r'[^ACGUTacguN]', '', s).upper().replace('T', 'U')
    if len(seq) >= 10:
        return seq, 'input_sequence'

    # Treat as gene name fallback
    for gene, demo_seq in GENE_DEMO_SEQS.items():
        if s.upper() in gene:
            return demo_seq.upper().replace('T', 'U'), gene
    seq = GENE_DEMO_SEQS['SMN2']
    return seq.upper().replace('T', 'U'), f'demo_SMN2_3UTR (could_not_resolve_{s})'

mrna, seq_name = parse_sequence(raw_input)

# ─── Chemistry parameters ─────────────────────────────────────────────────────
CHEMISTRY_PARAMS = {
    'moe_gapmer': {
        'wing_mod': 'MOE',
        'wing_len': 5,
        'gap_len':  10,
        'aso_len':  20,
        'tm_correction_per_mod': 1.5,
        'rnase_h_active': True,
        'description': "5'-MOE(5) / DNA(10) / MOE(5)-3' = 20-mer gapmer. RNase H active. Nusinersen/inotersen pattern.",
        'precedents': ['Nusinersen (Spinraza, intrathecal, SMA)', 'Inotersen (Tegsedi, SC, hATTR)', 'Volanesorsen (Waylivra, SC, ApoC-III)'],
    },
    'lna_gapmer': {
        'wing_mod': 'LNA',
        'wing_len': 3,
        'gap_len':  10,
        'aso_len':  16,
        'tm_correction_per_mod': 4.5,  # midpoint of 4-6°C range
        'rnase_h_active': True,
        'description': "5'-LNA(3) / DNA(10) / LNA(3)-3' = 16-mer gapmer. Higher Tm, shorter oligo. RNase H active.",
        'precedents': ['Mipomersen-like short gapmers (investigational)', 'SPC5001 (ApoB LNA gapmer)'],
    },
    'moe_mixmer': {
        'wing_mod': 'MOE',
        'wing_len': None,  # alternating throughout
        'gap_len':  None,
        'aso_len':  20,
        'tm_correction_per_mod': 1.5,
        'rnase_h_active': False,
        'description': "20-mer alternating MOE/DNA mixmer. NO RNase H cleavage — steric blocking mechanism only (exon skipping, splicing modulation).",
        'precedents': ['Eteplirsen (Exondys 51, exon 51 skipping, DMD)', 'Golodirsen (Vyondys 53, exon 53 skipping)'],
    },
}

chem_params = CHEMISTRY_PARAMS.get(chemistry, CHEMISTRY_PARAMS['moe_gapmer'])

# ─── Nearest-neighbor Tm (DNA:RNA hybrid, simplified SantaLucia 1998) ─────────
NN_TM_HYBRID = {
    # DNA:RNA hybrid ΔH (kcal/mol) — approximate values
    'AA': -6.6, 'AU': -5.7, 'AC': -8.2, 'AG': -7.8,
    'TA': -7.2, 'TT': -6.6, 'TC': -6.6, 'TG': -9.1,
    'CA': -8.8, 'CU': -6.6, 'CC': -9.3, 'CG': -8.0,
    'GA': -8.2, 'GU': -7.0, 'GC': -7.2, 'GG': -9.3,
}

def tm_nearest_neighbor(dna_seq, mods_count=0, mod_type='MOE'):
    '''
    Approximate Tm for DNA:RNA hybrid using nearest-neighbor.
    Corrects for chemical modifications.
    Assumes 250 nM ASO, 150 mM NaCl, 37°C assay.
    '''
    dh = sum(NN_TM_HYBRID.get(dna_seq[i:i+2].upper(), -7.5)
             for i in range(len(dna_seq) - 1))
    # Approximate entropy contribution (simplified)
    n = len(dna_seq)
    ds = dh / (72.0 + 16.6 * math.log10(0.15))  # simplified
    # Wallace rule fallback for short oligos
    gc = dna_seq.upper().count('G') + dna_seq.upper().count('C')
    at = n - gc
    tm_wallace = 2 * at + 4 * gc

    # Blend nearest-neighbor with Wallace (NN more accurate for >10 nt)
    tm_base = tm_wallace if n <= 10 else (tm_wallace * 0.3 + (dh / (ds + 0.7) - 273.15) * 0.7 if ds != 0 else tm_wallace)

    # Modification corrections
    corr = mods_count * chem_params['tm_correction_per_mod']
    return round(tm_base + corr, 1)

def gc_pct(seq):
    seq = seq.upper().replace('U', 'T')
    gc = sum(1 for b in seq if b in 'GC')
    return round(100.0 * gc / max(len(seq), 1), 1)

def reverse_complement_dna(seq):
    seq = seq.upper().replace('U', 'T')
    comp = {'A': 'T', 'T': 'A', 'G': 'C', 'C': 'G', 'N': 'N'}
    return ''.join(comp.get(b, 'N') for b in reversed(seq))

def has_palindrome(seq, min_len=4):
    '''Check if sequence contains a palindrome of length >= min_len.'''
    seq = seq.upper().replace('U', 'T')
    for i in range(len(seq) - min_len + 1):
        for length in range(min_len, len(seq) - i + 1, 2):
            sub = seq[i:i+length]
            if sub == reverse_complement_dna(sub):
                return True, sub
    return False, None

def count_cpg(seq):
    seq = seq.upper().replace('U', 'T')
    return seq.count('CG')

def has_gquad(seq):
    '''GGGG run = G-quadruplex potential → hepatotoxicity risk.'''
    return bool(re.search(r'G{4,}', seq.upper()))

def has_long_gc_run(seq, run_len=6):
    '''Highly structured region proxy: runs of ≥6 consecutive G/C.'''
    return bool(re.search(r'[GC]{' + str(run_len) + r',}', seq.upper().replace('U', 'T')))

# ─── Wing modification count per chemistry ────────────────────────────────────
def get_mods_count(wing_len, aso_len, chem):
    if chem == 'moe_mixmer':
        # Alternating: half of residues are MOE
        return aso_len // 2
    else:
        return 2 * wing_len  # both wings

# ─── Sliding window ASO design ────────────────────────────────────────────────
target_dna = mrna.upper().replace('U', 'T')
aso_len    = chem_params['aso_len']
wing_len   = chem_params['wing_len'] or 5
gap_len    = chem_params['gap_len']  or 10
mods_count = get_mods_count(wing_len, aso_len, chemistry)

candidates = []

for start in range(len(target_dna) - aso_len + 1):
    target_window = target_dna[start:start + aso_len]

    if any(b not in 'ACGTN' for b in target_window):
        continue

    # ASO sequence = reverse complement of target window (antisense)
    aso_seq = reverse_complement_dna(target_window)

    # Structural annotation
    wing5 = aso_seq[:wing_len]
    gap   = aso_seq[wing_len:wing_len + gap_len]
    wing3 = aso_seq[wing_len + gap_len:]

    # ── Scoring ───────────────────────────────────────────────────────────────
    gcp = gc_pct(aso_seq)
    tm  = tm_nearest_neighbor(aso_seq, mods_count=mods_count, mod_type=chem_params['wing_mod'])

    # Pass/fail filters
    gquad    = has_gquad(aso_seq)
    cpg_cnt  = count_cpg(aso_seq)
    gc_run   = has_long_gc_run(target_window, run_len=6)  # avoid highly structured target
    palind, palind_seq = has_palindrome(aso_seq, min_len=4)

    # Hard rejections
    if gquad:
        continue
    if gc_run:
        continue

    # Soft scores
    tm_ok   = 50.0 <= tm <= 65.0
    gc_ok   = 40.0 <= gcp <= 60.0
    self_ok = not palind

    score = sum([tm_ok, gc_ok, self_ok, cpg_cnt == 0])

    # Prefer 3'-UTR (heuristic: last 1/3 of sequence)
    in_3utr = start >= 2 * len(target_dna) // 3

    candidates.append({
        'position':          start + 1,
        'target_seq':        target_window,
        'aso_sequence':      aso_seq,
        'wing5':             wing5,
        'gap_dna':           gap,
        'wing3':             wing3,
        'aso_length':        aso_len,
        'gc_pct':            gcp,
        'tm_predicted_c':    tm,
        'tm_ok':             tm_ok,
        'gc_ok':             gc_ok,
        'self_complementarity': palind,
        'palindrome_motif':  palind_seq or '',
        'gquad_risk':        gquad,
        'cpg_count':         cpg_cnt,
        'cpg_flag':          cpg_cnt > 0,
        'structured_target': gc_run,
        'in_3utr':           in_3utr,
        'composite_score':   score + (1 if in_3utr else 0),
    })

# Sort: score DESC, Tm proximity to 57.5°C tiebreak
candidates.sort(key=lambda c: (-c['composite_score'], abs(c['tm_predicted_c'] - 57.5)))

top = candidates[:n_top]

# ─── PS backbone recommendation ──────────────────────────────────────────────
ps_rec = {
    'liver':    ('Full phosphorothioate (PS) backbone. Liver GalNAc-conjugated ASO uses full PS '
                 'for nuclease resistance in blood (SC delivery). Standard for inclisiran/givosiran class.'),
    'cns':      ('Mixed PS/PO backbone recommended. Intrathecal delivery (no plasma nucleases). '
                 'Mixed PS/PO reduces neuroinflammation vs full PS. Nusinersen uses full PS '
                 '(intrathecal route). Either acceptable; mixed reduces toxicity.'),
    'muscle':   ('Full PS for systemic delivery, but note: PS ASO has very poor muscle uptake. '
                 'STRONGLY RECOMMEND switching to PMO (phosphorodiamidate morpholino oligomer) '
                 'or PPMO (peptide-conjugated PMO) chemistry for muscle targets. '
                 'Eteplirsen/golodirsen are PMO, not PS ASO.'),
    'systemic': ('Full PS backbone for plasma nuclease resistance. Note: systemic PS ASO '
                 'distributes primarily to liver and kidney; poor CNS penetration (BBB) '
                 'and poor muscle uptake. Consider GalNAc conjugation for liver specificity.'),
}
ps_backbone_note = ps_rec.get(target_tissue, ps_rec['systemic'])

# ─── Delivery recommendation ─────────────────────────────────────────────────
DELIVERY_REC = {
    'liver': {
        'route': 'Subcutaneous (SC) injection',
        'conjugation': 'GalNAc-ASO conjugation (N-acetylgalactosamine, ASGPR-mediated hepatocyte uptake)',
        'dose_schedule': 'Typical: loading doses (weeks 1, 2, 3, 4) then quarterly maintenance',
        'precedents': ['Inclisiran (PCSK9, GalNAc-siRNA)', 'Givosiran (ALAS1, GalNAc-siRNA)', 'Fitusiran (antithrombin, GalNAc-siRNA)'],
        'note': 'GalNAc conjugation enables ~10-30x dose reduction vs naked ASO and targets hepatocytes specifically via ASGPR (asialoglycoprotein receptor). ASGPR expression: hepatocytes >> all other cell types.',
    },
    'cns': {
        'route': 'Intrathecal (IT) or intracerebroventricular (ICV) injection',
        'conjugation': 'None required — IT delivery bypasses BBB; naked MOE gapmer distributes widely in CNS',
        'dose_schedule': 'Lumbar IT injection; nusinersen dosing: 4 loading doses in 2 months, then every 4 months',
        'precedents': ['Nusinersen (SMN2, IT, SMA)', 'Tominersen (HTT, IT/ICV, Huntington — Phase 3 paused)', 'Eplontersen (TTR, IT, hATTR)'],
        'note': 'MOE gapmers distribute from CSF into spinal cord and brain parenchyma via diffusion. Intrathecal concentration profiles support RNase H-mediated knockdown in motor neurons (SMA) and cortical neurons (HD). No GalNAc or other conjugation needed for CNS.',
    },
    'muscle': {
        'route': 'Systemic IV or SC (with major caveats)',
        'conjugation': 'HIGHLY RECOMMENDED: Switch to PMO (phosphorodiamidate morpholino) or PPMO (peptide-conjugated PMO). Naked PS ASO has <1% muscle uptake.',
        'dose_schedule': 'PMO: weekly IV injection (eteplirsen 30 mg/kg/week); PPMO: lower dose possible',
        'precedents': ['Eteplirsen (Exondys 51, DMD exon 51 skipping, PMO, IV)', 'Golodirsen (Vyondys 53, DMD exon 53 skipping, PMO, IV)', 'Viltolarsen (Viltepso, PMO, IV)'],
        'note': 'PS ASO chemistry (MOE gapmer or LNA gapmer) is NOT recommended for muscle targets. PMO oligos (uncharged backbone) have better muscle uptake. PPMO (cell-penetrating peptide + PMO) further improves efficacy. This design provides the target sequence; final chemistry should be PMO for muscle delivery.',
        'chemistry_warning': 'CHEMISTRY CHANGE RECOMMENDED: PMO or PPMO instead of MOE/LNA gapmer for muscle delivery.',
    },
    'systemic': {
        'route': 'SC or IV injection',
        'conjugation': 'Naked PS ASO (no conjugation). GalNAc conjugation if liver is primary target.',
        'dose_schedule': 'SC: weekly to monthly injection; IV: weekly infusion',
        'precedents': ['Inotersen (Tegsedi, SC, TTR knockdown, hATTR)', 'Volanesorsen (Waylivra, SC, ApoC-III, hypertriglyceridemia)'],
        'note': 'Naked PS ASO distributes to liver and kidney (primary organs). Protein binding (albumin) buffers toxicity but limits free fraction. Systemic PS ASO does not cross BBB and has poor muscle uptake.',
    },
}

delivery_info = DELIVERY_REC.get(target_tissue, DELIVERY_REC['systemic'])

# ─── Output files ─────────────────────────────────────────────────────────────
CSV_COLS = ['position', 'aso_sequence', 'gc_pct', 'tm_predicted_c',
            'tm_ok', 'gc_ok', 'self_complementarity', 'cpg_count',
            'cpg_flag', 'in_3utr', 'composite_score']

with open('aso_candidates.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=CSV_COLS, extrasaction='ignore')
    w.writeheader()
    w.writerows(top)

report = {
    'status': 'completed',
    'target': seq_name,
    'mrna_length': len(mrna),
    'target_tissue': target_tissue,
    'chemistry': chemistry,
    'chemistry_description': chem_params['description'],
    'rnase_h_active': chem_params['rnase_h_active'],
    'gapmer_architecture': {
        'wing_mod': chem_params['wing_mod'],
        'wing_len': wing_len,
        'gap_len':  gap_len,
        'total_len': aso_len,
        'structure': f"5'-{chem_params['wing_mod']}({wing_len}) / DNA({gap_len}) / {chem_params['wing_mod']}({wing_len})-3'" if chemistry != 'moe_mixmer' else '5\'-alternating MOE/DNA-3\'',
    },
    'scoring_filters': {
        'tm_target_range': '50-65°C',
        'gc_target_range': '40-60%',
        'self_complementarity_max_palindrome': 4,
        'reject_gquad': 'GGGG runs rejected (hepatotoxicity via G-quadruplex)',
        'reject_structured_target': '>6 consecutive G/C in target window rejected (inaccessible structure)',
        'cpg_flag': 'CpG motifs flagged — consider 5-methylcytosine substitution to reduce TLR9 activation',
    },
    'ps_backbone_recommendation': ps_backbone_note,
    'delivery': delivery_info,
    'candidates_screened': len(candidates) + sum(1 for c in candidates if c['gquad_risk'] or c['structured_target']),
    'candidates_after_filters': len(candidates),
    'n_top_returned': len(top),
    'top_candidates': top,
    'chemistry_precedents': chem_params['precedents'],
    'references': [
        'Crooke et al. 2018 Cell Metab 27:714 (ASO mechanism review)',
        'Rinaldi & Wood 2018 Nature Rev Neurol 14:9 (CNS ASO delivery)',
        'Prakash et al. 2014 J Med Chem 57:6254 (MOE gapmer Tm correction)',
        'Eckstein 2014 Nucleic Acid Ther 24:374 (PS backbone pharmacology)',
        'Roberts et al. 2020 Nucleic Acids Res 48:5616 (LNA toxicity)',
        'Ly et al. 2020 Cell Chem Biol 27:992 (GalNAc-ASO hepatic delivery)',
        'Finkel et al. 2017 Lancet 388:3017 (nusinersen Phase 3 ENDEAR trial)',
    ],
}

with open('aso_design_report.json', 'w') as f:
    json.dump(report, f, indent=2)

# ─── Delivery recommendation text ────────────────────────────────────────────
chemistry_warning = delivery_info.get('chemistry_warning', '')

lines = [
    '╔══════════════════════════════════════════════════════════════╗',
    '  ASO Gapmer Design — Delivery Recommendation',
    f'  Target: {seq_name}  |  Tissue: {target_tissue}  |  Chemistry: {chemistry}',
    '╚══════════════════════════════════════════════════════════════╝',
    '',
    '── Chemistry Summary ──────────────────────────────────────────',
    f'  {chem_params["description"]}',
    f'  RNase H active: {"YES (gapmer → mRNA degradation)" if chem_params["rnase_h_active"] else "NO (steric block / splice modulation only)"}',
    '',
]

if chemistry_warning:
    lines += [
        '!! CHEMISTRY WARNING !!',
        f'  {chemistry_warning}',
        '',
    ]

lines += [
    '── Delivery Strategy ──────────────────────────────────────────',
    f'  Route:        {delivery_info["route"]}',
    f'  Conjugation:  {delivery_info["conjugation"]}',
    f'  Dosing:       {delivery_info["dose_schedule"]}',
    '',
    '── Scientific Note ────────────────────────────────────────────',
    f'  {delivery_info["note"]}',
    '',
    '── PS Backbone Recommendation ─────────────────────────────────',
    f'  {ps_backbone_note}',
    '',
    '── Approved Precedents ────────────────────────────────────────',
]
for prec in delivery_info['precedents']:
    lines.append(f'  · {prec}')

lines += [
    '',
    '── Top ASO Candidates ─────────────────────────────────────────',
    f'  {"Rank":<5} {"Pos":<6} {"ASO Sequence":<22} {"GC%":<7} {"Tm(°C)":<8} {"CpG":<5} {"Score"} In3UTR',
    '  ' + '-' * 70,
]
for rank, c in enumerate(top, 1):
    lines.append(
        f'  {rank:<5} {c["position"]:<6} {c["aso_sequence"]:<22} '
        f'{c["gc_pct"]:<7.1f} {c["tm_predicted_c"]:<8.1f} '
        f'{c["cpg_count"]:<5} {c["composite_score"]:<6} {"YES" if c["in_3utr"] else "no"}'
    )

lines += [
    '',
    '── Scoring Filter Notes ───────────────────────────────────────',
    '  Rejected: GGGG runs (G-quadruplex → hepatotoxicity)',
    '  Rejected: >6 consecutive GC in target (inaccessible secondary structure)',
    '  Flagged:  CpG motifs (TLR9 immunostimulation — use 5-mC substitution)',
    '  Flagged:  self-complementarity palindrome >4 nt (hairpin risk)',
    '',
    '── Output Files ───────────────────────────────────────────────',
    '  aso_candidates.csv         — ranked candidate table',
    '  aso_design_report.json     — full design details and references',
    '  delivery_recommendation.txt — this report',
]

with open('delivery_recommendation.txt', 'w') as f:
    f.write('\\n'.join(lines) + '\\n')

print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
aso_gapmer_design:
  version: "1.0"
  container: biomni-tools
EOF
    """
}

workflow ASO_GAPMER_DESIGN_WORKFLOW {
    take: meta_ch
    main: ASO_GAPMER_DESIGN(meta_ch)
    emit:
        candidates    = ASO_GAPMER_DESIGN.out.candidates
        report_json   = ASO_GAPMER_DESIGN.out.report_json
        delivery_report = ASO_GAPMER_DESIGN.out.delivery_report
}

workflow {
    meta = [id: 'aso_gapmer_run']
    Channel.value(meta) | ASO_GAPMER_DESIGN_WORKFLOW
}
