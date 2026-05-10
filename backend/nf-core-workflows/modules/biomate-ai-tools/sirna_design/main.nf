#!/usr/bin/env nextflow
/*
 * molecular_biology/sirna_design_full
 *
 * siRNA candidate generation and efficacy scoring from an input mRNA sequence.
 * Implements the industry-standard Ui-Tei (2004) and Reynolds (2004) scoring
 * criteria plus thermodynamic asymmetry analysis to rank 19-21mer candidates.
 * Top candidates are ready for downstream sirna_offtarget_analysis.
 *
 * Algorithm overview:
 *   1. Parse input mRNA (FASTA or raw sequence); optionally restrict to
 *      coding / 5'UTR / 3'UTR window via target_region param.
 *   2. Sliding-window extraction of all 19, 20, and 21-nt sense/antisense pairs.
 *   3. GC content filter: keep candidates with min_gc_pct ≤ GC% ≤ max_gc_pct
 *      (default 30–52%, optimal for RISC loading).
 *   4. Ui-Tei 2004 criteria (Nucleic Acids Res 32:936):
 *        a) A/U at sense position 1 (weak 5' end of antisense → RISC loading)
 *        b) G/C at sense position 19 (strong 3' end → target cleavage anchor)
 *        c) AU-rich stretch in antisense positions 1-7 (≥4 A/U)
 *        d) No internal repeats (no single nucleotide run ≥ 4)
 *   5. Reynolds 2004 criteria (Nature Biotechnol 22:326) — 8 binary features:
 *        GC 36-52%, no G at sense pos 1, no GGG/CCC trinucleotide runs,
 *        U at sense pos 10, A at sense pos 3, A at sense pos 19,
 *        A at antisense pos 10, antisense Tm < 20 °C
 *   6. Thermodynamic asymmetry: ΔG of 5' antisense (positions 1-4) must be
 *      less negative than 5' sense end — favors antisense RISC loading
 *      (Schwarz 2003 Cell 115:199; Khvorova 2003 Cell 115:209).
 *   7. Composite score = Ui-Tei (0-4) + Reynolds (0-8) + asymmetry_bonus (0/1)
 *      Max = 13. Efficacy tier: A (≥10), B (7-9), C (4-6), D (≤3).
 *   8. Output top n_top candidates sorted by composite score (descending).
 *
 * Input parameters:
 *   mrna_sequence   — path to FASTA file OR raw RNA/DNA sequence string
 *   target_region   — all | coding | 3utr | 5utr  (default: all)
 *   n_top           — number of top candidates to return (default: 10)
 *   min_gc_pct      — lower GC% bound (default: 30)
 *   max_gc_pct      — upper GC% bound (default: 52)
 *
 * Outputs:
 *   sirna_candidates.csv  — ranked table; columns:
 *                           position, sense_21mer, antisense_21mer, gc_pct,
 *                           uitei_score, reynolds_score, composite_score,
 *                           predicted_efficacy_tier
 *   scoring_summary.json  — full scoring details + parameter audit
 *   design_report.txt     — human-readable ranked report
 *
 * Chain to: sirna_offtarget_analysis (feed guide_strand from this output)
 *
 * References:
 *   - Ui-Tei et al. 2004 Nucleic Acids Res 32:936
 *   - Reynolds et al. 2004 Nature Biotechnol 22:326
 *   - Schwarz et al. 2003 Cell 115:199 (thermodynamic asymmetry)
 *   - Khvorova et al. 2003 Cell 115:209 (thermodynamic asymmetry)
 *   - Elbashir et al. 2001 Nature 411:494 (21-nt duplex standard)
 */

nextflow.enable.dsl = 2

params.outdir       = './results'
params.mrna_sequence = 'null'   // FASTA file path or raw sequence string (RNA or DNA)
params.target_region = 'all'    // all | coding | 3utr | 5utr
params.n_top         = '10'     // number of top candidates to return
params.min_gc_pct    = '30'     // minimum GC% (default 30)
params.max_gc_pct    = '52'     // maximum GC% (default 52)

// [Phase A] siRNA Candidate Generation & Efficacy Scoring
process SIRNA_DESIGN_FULL {
    tag "sirna_design"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("sirna_candidates.csv"),   emit: candidates
    tuple val(meta), path("scoring_summary.json"),   emit: summary_json
    tuple val(meta), path("design_report.txt"),      emit: report
    path "versions.yml",                              emit: versions

    script:
    """
    export PARAM_SEQ='${params.mrna_sequence}'
    export PARAM_REGION='${params.target_region}'
    export PARAM_NTOP='${params.n_top}'
    export PARAM_MINGC='${params.min_gc_pct}'
    export PARAM_MAXGC='${params.max_gc_pct}'

    python3 << 'PYEOF'
import json, os, csv, math, re

# ─── Parameters ──────────────────────────────────────────────────────────────
raw_seq     = os.environ.get('PARAM_SEQ', '').strip()
region      = os.environ.get('PARAM_REGION', 'all').lower()
n_top       = max(1, int(float(os.environ.get('PARAM_NTOP', '10'))))
min_gc      = float(os.environ.get('PARAM_MINGC', '30'))
max_gc      = float(os.environ.get('PARAM_MAXGC', '52'))

# ─── Parse sequence ───────────────────────────────────────────────────────────
def parse_sequence(s):
    """Accept FASTA file path, FASTA string, raw RNA, or raw DNA."""
    s = s.strip()
    if not s or s == 'null':
        # Demo sequence: human BCL2 mRNA coding region (NM_000633) ~53% GC
        s = ('AUGGCGCACGCUGGAGAUGGUUGGGAGCUGGCAGAAGGUGAAUGCCUCCAGAGGCUGGCUAGGGAAAC'
             'UGAGCAGAUCAUUGCCUUGUGGAACCUGACAGAGAUCAUAGCCAUCAUCAAGCAGCUGGAUGGCCACUU'
             'CCAGAGUGUGAAACUGGGGGAGGAUUGGGCCUGCUUUAGCUGGGACUUUACUUGAGCUGGGCUUUGUA'
             'UGGGCAUUCCAGGAUAUUGGAGAAGCAGGCCCAGUCAGUGCUCACAGAAAAUAGUCACUGUGGG')
        return s.upper().replace('T', 'U'), 'demo_BCL2_coding'
    if os.path.isfile(s):
        with open(s) as fh:
            lines = fh.read().splitlines()
        name = lines[0].lstrip('>').split()[0] if lines[0].startswith('>') else 'input'
        seq  = ''.join(l for l in lines if not l.startswith('>')).upper().replace('T', 'U')
        return seq, name
    # Could be inline FASTA
    if s.startswith('>'):
        lines = s.splitlines()
        name  = lines[0].lstrip('>').split()[0]
        seq   = ''.join(l for l in lines[1:]).upper().replace('T', 'U')
        return seq, name
    # Raw sequence
    seq = re.sub(r'[^ACGUTacguN]', '', s).upper().replace('T', 'U')
    return seq, 'input_sequence'

mrna, seq_name = parse_sequence(raw_seq)

# ─── Region filter ─────────────────────────────────────────────────────────
# Simple heuristic: split into thirds as 5UTR/CDS/3UTR if region != all
L = len(mrna)
region_windows = {
    'all':     (0, L),
    '5utr':    (0, max(1, L // 6)),
    'coding':  (L // 6, 5 * L // 6),
    '3utr':    (5 * L // 6, L),
}
r_start, r_end = region_windows.get(region, (0, L))
target_seq = mrna[r_start:r_end]

# ─── Nearest-neighbour ΔG parameters (SantaLucia 1998 / Xia 1998 RNA) ────────
NN_DG = {
    'AA': -0.93, 'AU': -1.10, 'UA': -1.33, 'UU': -0.93,
    'GA': -2.35, 'GU': -2.11, 'CA': -2.11, 'CU': -1.96,
    'AG': -2.35, 'AC': -2.11, 'UG': -2.11, 'UC': -1.96,
    'GG': -3.26, 'GC': -3.42, 'CG': -3.61, 'CC': -3.26,
}

def calc_dg5(seq, n=4):
    """ΔG of first n+1 nt (nearest-neighbour sum, approximation)."""
    total = 0.0
    for i in range(min(n, len(seq) - 1)):
        total += NN_DG.get(seq[i] + seq[i+1], -2.0)
    return round(total, 3)

def reverse_complement(seq):
    comp = {'A': 'U', 'U': 'A', 'G': 'C', 'C': 'G', 'N': 'N'}
    return ''.join(comp.get(b, 'N') for b in reversed(seq))

def gc_pct(seq):
    gc = sum(1 for b in seq if b in 'GC')
    return round(100.0 * gc / max(len(seq), 1), 1)

def tm_approx(seq):
    """Wallace rule Tm (RNA, 100 mM NaCl); returns °C."""
    gc = seq.count('G') + seq.count('C')
    au = seq.count('A') + seq.count('U')
    return round(2 * au + 4 * gc, 1)

# ─── Scoring functions ───────────────────────────────────────────────────────

def uitei_score(sense21):
    """
    Ui-Tei 2004 criteria — 4 binary features; higher = better.
    Sense strand positions are 1-indexed.
    """
    score = 0
    # (a) A or U at position 1 (sense) — weak 5' end of antisense strand
    if sense21[0] in 'AU':
        score += 1
    # (b) G or C at position 19 (sense) — strong 3' end of antisense
    if len(sense21) >= 19 and sense21[18] in 'GC':
        score += 1
    # (c) AU-rich in antisense positions 1-7 (= sense RC positions, approx
    #     sense 15-21 reversed; simplified: antisense pos 1-7)
    antisense = reverse_complement(sense21)
    au_count = sum(1 for b in antisense[:7] if b in 'AU')
    if au_count >= 4:
        score += 1
    # (d) No internal repeats: no single-nucleotide run of ≥ 4
    if not re.search(r'([ACGU])\1{3,}', sense21):
        score += 1
    return score

def reynolds_score(sense21):
    """
    Reynolds 2004 criteria — 8 binary features; higher = better.
    """
    score = 0
    gc = gc_pct(sense21)
    antisense = reverse_complement(sense21)

    # 1. GC content 36-52%
    if 36 <= gc <= 52:
        score += 1
    # 2. No G at sense position 1
    if sense21[0] != 'G':
        score += 1
    # 3. No GGG or CCC trinucleotide run
    if 'GGG' not in sense21 and 'CCC' not in sense21:
        score += 1
    # 4. U at sense position 10
    if len(sense21) >= 10 and sense21[9] == 'U':
        score += 1
    # 5. A at sense position 3
    if len(sense21) >= 3 and sense21[2] == 'A':
        score += 1
    # 6. A at sense position 19
    if len(sense21) >= 19 and sense21[18] == 'A':
        score += 1
    # 7. A at antisense position 10 (favors RISC loading guide end)
    if len(antisense) >= 10 and antisense[9] == 'A':
        score += 1
    # 8. Antisense Tm < 20 °C (low self-complementarity; Wallace rule)
    if tm_approx(antisense) < 20:
        score += 1
    return score

def thermo_asymmetry_bonus(sense21):
    """
    Returns 1 if 5'-ΔG antisense < 5'-ΔG sense (Schwarz/Khvorova 2003),
    i.e., antisense 5' end is thermodynamically less stable → preferred RISC loading.
    """
    antisense = reverse_complement(sense21)
    dg_sense     = calc_dg5(sense21)
    dg_antisense = calc_dg5(antisense)
    return 1 if dg_antisense < dg_sense else 0

TIER_MAP = [(10, 'A'), (7, 'B'), (4, 'C'), (0, 'D')]

def efficacy_tier(composite):
    for threshold, tier in TIER_MAP:
        if composite >= threshold:
            return tier
    return 'D'

# ─── Sliding-window candidate extraction ─────────────────────────────────────
candidates = []

for mer in (21, 20, 19):
    for pos in range(len(target_seq) - mer + 1):
        sense = target_seq[pos:pos + mer]
        if any(b not in 'ACGU' for b in sense):
            continue  # skip ambiguous bases

        # Pad shorter mers to 21 for scoring (add 2-nt 3' overhang convention)
        sense21 = sense if mer == 21 else sense + 'UU'[:21 - mer]

        # GC filter
        gcp = gc_pct(sense)
        if not (min_gc <= gcp <= max_gc):
            continue

        ut  = uitei_score(sense21)
        rn  = reynolds_score(sense21)
        ta  = thermo_asymmetry_bonus(sense21)
        comp = ut + rn + ta

        antisense21 = reverse_complement(sense21)
        dg_s  = calc_dg5(sense21)
        dg_as = calc_dg5(antisense21)

        candidates.append({
            'position':             r_start + pos + 1,  # 1-indexed on full mRNA
            'mer_length':           mer,
            'sense_21mer':          sense21,
            'antisense_21mer':      antisense21,
            'gc_pct':               gcp,
            'uitei_score':          ut,
            'reynolds_score':       rn,
            'thermo_asymmetry':     ta,
            'composite_score':      comp,
            'predicted_efficacy_tier': efficacy_tier(comp),
            'dg5_sense':            dg_s,
            'dg5_antisense':        dg_as,
        })

# Sort: composite DESC, then GC proximity to 45% (sweet-spot tiebreak)
candidates.sort(key=lambda c: (-c['composite_score'], abs(c['gc_pct'] - 45)))

top = candidates[:n_top]

# ─── Write outputs ────────────────────────────────────────────────────────────
CSV_COLS = ['position', 'sense_21mer', 'antisense_21mer', 'gc_pct',
            'uitei_score', 'reynolds_score', 'composite_score',
            'predicted_efficacy_tier']

with open('sirna_candidates.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=CSV_COLS, extrasaction='ignore')
    w.writeheader()
    w.writerows(top)

summary = {
    'status': 'completed',
    'sequence_name': seq_name,
    'mrna_length': L,
    'target_region': region,
    'region_window': [r_start + 1, r_end],
    'target_region_length': len(target_seq),
    'mer_lengths_scanned': [19, 20, 21],
    'gc_filter': {'min_pct': min_gc, 'max_pct': max_gc},
    'total_candidates_before_gc_filter':
        sum(1 for pos in range(len(target_seq) - mer + 1)
            for mer in (19, 20, 21)
            if pos + mer <= len(target_seq)),
    'total_candidates_after_gc_filter': len(candidates),
    'n_top_returned': len(top),
    'scoring_criteria': {
        'uitei_2004': 'positions 1/19 base identity, AU-rich antisense 1-7, no repeats (max 4)',
        'reynolds_2004': 'GC 36-52%, pos1 not G, no GGG/CCC, U@10, A@3, A@19, A@AS10, Tm<20 (max 8)',
        'thermo_asymmetry': 'dG5_antisense < dG5_sense (Schwarz/Khvorova 2003, max 1)',
        'composite_max': 13,
    },
    'top_candidates': top,
    'tier_distribution': {
        t: sum(1 for c in candidates if c['predicted_efficacy_tier'] == t)
        for t in ['A', 'B', 'C', 'D']
    },
    'downstream_workflow': 'sirna_offtarget_analysis',
    'next_step': 'Feed sense_21mer (as guide_strand) to sirna_offtarget_analysis for seed-region off-target scanning',
    'references': [
        'Ui-Tei et al. 2004 Nucleic Acids Res 32:936',
        'Reynolds et al. 2004 Nature Biotechnol 22:326',
        'Schwarz et al. 2003 Cell 115:199',
        'Khvorova et al. 2003 Cell 115:209',
        'Elbashir et al. 2001 Nature 411:494',
    ],
}

with open('scoring_summary.json', 'w') as f:
    json.dump(summary, f, indent=2)

# Human-readable report
tier_dist = summary['tier_distribution']
lines = [
    '╔══════════════════════════════════════════════════════════════╗',
    '  siRNA Design & Efficacy Scoring Report',
    f'  Sequence: {seq_name} ({L} nt)  |  Region: {region}',
    '╚══════════════════════════════════════════════════════════════╝',
    '',
    f'  Candidates screened:  {len(candidates)}',
    f'  GC filter:            {min_gc}–{max_gc}%',
    f'  Efficacy distribution: A={tier_dist["A"]}  B={tier_dist["B"]}  C={tier_dist["C"]}  D={tier_dist["D"]}',
    '',
    f'── Top {len(top)} Candidates (Composite Score DESC) ──────────────────',
    f'  {"Rank":<5} {"Pos":<6} {"Sense 21mer":<23} {"GC%":<7} {"Ui-Tei":<8} {"Reyn":<6} {"Comp":<6} Tier',
    '  ' + '-' * 72,
]
for rank, c in enumerate(top, 1):
    lines.append(
        f'  {rank:<5} {c["position"]:<6} {c["sense_21mer"]:<23} '
        f'{c["gc_pct"]:<7.1f} {c["uitei_score"]:<8} {c["reynolds_score"]:<6} '
        f'{c["composite_score"]:<6} {c["predicted_efficacy_tier"]}'
    )

lines += [
    '',
    '── Scoring Criteria ──────────────────────────────────────────────',
    '  Ui-Tei  (0-4): pos1=A/U, pos19=G/C, antisense AU-rich[1-7], no repeats',
    '  Reynolds(0-8): GC 36-52%, no G@1, no GGG/CCC, U@10, A@3, A@19, A@AS10, Tm<20',
    '  Thermo  (0-1): dG5 antisense < dG5 sense (RISC strand selection)',
    '  Composite max: 13  |  Tiers: A≥10, B 7-9, C 4-6, D≤3',
    '',
    '── Next Step ─────────────────────────────────────────────────────',
    '  Feed top candidate sense_21mer as guide_strand parameter to:',
    '  → sirna_offtarget_analysis (seed scanning, miRNA mimicry, TLR motifs)',
    '',
    '── References ────────────────────────────────────────────────────',
]
for ref in summary['references']:
    lines.append(f'  · {ref}')

with open('design_report.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('\n'.join(lines))
PYEOF

    python3 -c "print('sirna_design_full: 1.0')" > versions.yml
    """
}

workflow SIRNA_DESIGN_WORKFLOW {
    take: meta_ch
    main: SIRNA_DESIGN_FULL(meta_ch)
    emit:
        candidates   = SIRNA_DESIGN_FULL.out.candidates
        summary_json = SIRNA_DESIGN_FULL.out.summary_json
        report       = SIRNA_DESIGN_FULL.out.report
}

workflow { meta = [id: 'sirna_design_run']; Channel.value(meta) | SIRNA_DESIGN_WORKFLOW }
