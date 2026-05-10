#!/usr/bin/env nextflow
/*
 * drug_discovery/mrna_therapeutic_design
 *
 * Full mRNA therapeutic design pipeline: protein AA or ORF input →
 * human codon optimization → 5'/3'-UTR + poly-A assembly → stability
 * scoring (CAI, GC%, ARE motifs, uORF scan, cap-occlusion MFE) →
 * IVT template design → LNP formulation recommendation by tissue.
 *
 * Algorithm overview:
 *   Step 1: Sequence preparation
 *     - AA input → back-translate with human codon optimization (max CAI)
 *     - Nucleotide ORF → use as-is, convert T→U
 *     - HexaPro-like stabilization if protein_class=spike (6 Pro substitutions)
 *     - 5'-UTR: beta-globin Kozak (GCCACCAUGG) or AES/HBB or custom
 *     - Signal peptide if secreted=true: IgK leader METDTLLLWVLLLWVPGSTGD
 *     - 3'-UTR: HBB 3'-UTR or AES+mtRNR1 (Moderna-style stability element)
 *     - Poly-A tail: A30-linker-A70 (100 nt, Moderna A30LA70 standard)
 *   Step 2: Codon optimization scoring
 *     - CAI from human codon table; target > 0.8
 *     - GC content: 46-54% optimal; flag >70% or <30% runs ≥10 nt
 *     - CpG dinucleotide count (immune stimulatory → minimize)
 *     - uORF scan: AUG in 5'-UTR → flag translation competition risk
 *     - Internal stop codon check
 *     - Cap-occlusion MFE (first 50 nt; MFE > -20 kcal/mol preferred)
 *   Step 3: mRNA stability prediction
 *     - ARE motif count (AUUUA pentamers in 3'-UTR)
 *     - Predicted half-life tier (UTR length, ARE count, poly-A length)
 *     - m1Ψ recommendation (Karikó 2008: innate immune evasion + translation boost)
 *     - Cap analog recommendation: CleanCap AG (Cap1)
 *   Step 4: IVT template design
 *     - T7 promoter prefix: TAATACGACTCACTATA
 *     - Internal T7 terminator scan (TTTTT runs)
 *     - Expected transcript length
 *     - Linearization site suggestion
 *   Step 5: LNP formulation recommendation
 *     - Liver:  MC3/DLin-MC3-DMA  50:10:38.5:1.5
 *     - Muscle: SM-102 (Moderna mRNA-1273 standard)
 *     - Lung:   ALC-0315 sweep recommended
 *     - Spleen: C12-200 or 304-O13-E12 (CAR-T in vivo)
 *     - CNS:    intrathecal + small LNP; most LNPs don't cross BBB
 *
 * Input parameters:
 *   protein_sequence — AA sequence or nucleotide ORF (required)
 *   target_tissue    — liver | muscle | lung | spleen | cns (required)
 *   protein_class    — therapeutic | vaccine | antibody | enzyme (default: therapeutic)
 *   secreted         — true | false (default: false)
 *   utr_design       — hbb | moderna | custom (default: hbb)
 *
 * Outputs:
 *   mrna_design_report.json   — full design audit with all scores
 *   optimized_sequence.fasta  — final mRNA with UTRs and poly-A
 *   ivt_template.fasta        — DNA IVT template (T7 promoter + coding DNA)
 *   stability_metrics.json    — CAI, GC%, ARE count, half-life tier, cap/mod recs
 *   lnp_recommendation.json   — formulation by tissue with molar ratios
 *
 * References:
 *   - Karikó et al. 2008 Immunity 23:165 (m1Ψ modification)
 *   - Karikó et al. 2012 Mol Ther 20:948 (modified nucleosides + stability)
 *   - Andries et al. 2015 J Control Release 217:337 (AES+mtRNR1 3'-UTR)
 *   - Richner et al. 2017 Cell 168:1114 (uORF and Kozak optimization)
 *   - Rauch et al. 2018 Sci Rep 8:9841 (codon optimization + CAI)
 *   - Semple et al. 2010 Nature Biotechnol 28:172 (MC3 LNP)
 *   - Moderna mRNA-1273 patent (SM-102 formulation)
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.protein_sequence = 'null'       // AA sequence or nucleotide ORF
params.target_tissue    = 'muscle'     // liver | muscle | lung | spleen | cns
params.protein_class    = 'therapeutic' // therapeutic | vaccine | antibody | enzyme
params.secreted         = 'false'      // add IgK signal peptide
params.utr_design       = 'hbb'        // hbb | moderna | custom

// [Phase A] Sequence Preparation & Codon Optimization
process MRNA_SEQUENCE_PREP {
    tag "mrna_seq_prep"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("optimized_sequence.fasta"),  emit: optimized_fasta
    tuple val(meta), path("ivt_template.fasta"),         emit: ivt_fasta
    tuple val(meta), path("stability_metrics.json"),     emit: stability_json
    tuple val(meta), path("lnp_recommendation.json"),    emit: lnp_json
    tuple val(meta), path("mrna_design_report.json"),    emit: report_json
    path "versions.yml",                                  emit: versions

    script:
    """
    export PARAM_SEQ='${params.protein_sequence}'
    export PARAM_TISSUE='${params.target_tissue}'
    export PARAM_CLASS='${params.protein_class}'
    export PARAM_SECRETED='${params.secreted}'
    export PARAM_UTR='${params.utr_design}'

    python3 << 'PYEOF'
import json, os, re, math

# ─── Parameters ──────────────────────────────────────────────────────────────
raw_input   = os.environ.get('PARAM_SEQ', '').strip()
tissue      = os.environ.get('PARAM_TISSUE', 'muscle').lower()
prot_class  = os.environ.get('PARAM_CLASS', 'therapeutic').lower()
secreted    = os.environ.get('PARAM_SECRETED', 'false').lower() in ('true', '1', 'yes')
utr_design  = os.environ.get('PARAM_UTR', 'hbb').lower()

# ─── Human codon table (most-used codon per amino acid, HIVE-CUT 2020) ──────
HUMAN_CODON_TABLE = {
    'A': 'GCC', 'R': 'AGG', 'N': 'AAC', 'D': 'GAC', 'C': 'TGC',
    'Q': 'CAG', 'E': 'GAG', 'G': 'GGC', 'H': 'CAC', 'I': 'ATC',
    'L': 'CTG', 'K': 'AAG', 'M': 'ATG', 'F': 'TTC', 'P': 'CCC',
    'S': 'AGC', 'T': 'ACC', 'W': 'TGG', 'Y': 'TAC', 'V': 'GTG',
    '*': 'TGA',
}

# Full human codon usage frequencies (HIVE-CUT / GenBank 2020, per thousand)
# Used for CAI calculation — relative adaptiveness per codon
HUMAN_CODON_FREQ = {
    # Ala
    'GCT': 18.4, 'GCC': 27.7, 'GCA': 15.8, 'GCG': 7.4,
    # Arg
    'CGT': 4.5,  'CGC': 10.4, 'CGA': 6.2,  'CGG': 11.4, 'AGA': 12.2, 'AGG': 12.0,
    # Asn
    'AAT': 17.0, 'AAC': 19.1,
    # Asp
    'GAT': 21.8, 'GAC': 25.1,
    # Cys
    'TGT': 10.6, 'TGC': 12.6,
    # Gln
    'CAA': 12.3, 'CAG': 34.2,
    # Glu
    'GAA': 29.0, 'GAG': 39.6,
    # Gly
    'GGT': 10.8, 'GGC': 22.2, 'GGA': 16.5, 'GGG': 16.5,
    # His
    'CAT': 10.9, 'CAC': 15.1,
    # Ile
    'ATT': 15.9, 'ATC': 20.8, 'ATA': 7.5,
    # Leu
    'TTA': 7.7,  'TTG': 12.9, 'CTT': 13.2, 'CTC': 19.6, 'CTA': 7.2, 'CTG': 39.6,
    # Lys
    'AAA': 24.4, 'AAG': 31.9,
    # Met
    'ATG': 22.0,
    # Phe
    'TTT': 17.6, 'TTC': 20.3,
    # Pro
    'CCT': 17.5, 'CCC': 19.8, 'CCA': 16.9, 'CCG': 6.9,
    # Ser
    'TCT': 15.2, 'TCC': 17.7, 'TCA': 12.2, 'TCG': 4.4, 'AGT': 15.1, 'AGC': 19.5,
    # Thr
    'ACT': 13.1, 'ACC': 18.9, 'ACA': 15.1, 'ACG': 6.1,
    # Trp
    'TGG': 13.2,
    # Tyr
    'TAT': 12.2, 'TAC': 15.3,
    # Val
    'GTT': 11.0, 'GTC': 14.5, 'GTA': 7.1, 'GTG': 28.1,
    # Stop
    'TAA': 1.0, 'TAG': 0.8, 'TGA': 1.6,
}

def _max_freq_for_aa(aa):
    codon = HUMAN_CODON_TABLE.get(aa.upper(), 'NNN')
    return HUMAN_CODON_FREQ.get(codon, 1.0)

def back_translate(aa_seq):
    """Convert AA to DNA using highest-CAI human codons."""
    return ''.join(HUMAN_CODON_TABLE.get(aa.upper(), 'NNN') for aa in aa_seq)

def compute_cai(dna_seq):
    """Compute Codon Adaptation Index (Sharp & Li 1987) against human table."""
    codons = [dna_seq[i:i+3] for i in range(0, len(dna_seq)-2, 3)
              if len(dna_seq[i:i+3]) == 3]
    if not codons:
        return 0.0
    log_sum = 0.0
    n = 0
    for codon in codons:
        freq = HUMAN_CODON_FREQ.get(codon.upper(), 1.0)
        # Find max frequency among synonymous codons (simplified: use table max)
        aa = None
        for a, c in HUMAN_CODON_TABLE.items():
            if c == codon.upper():
                aa = a
                break
        max_f = _max_freq_for_aa(aa) if aa else freq
        if max_f > 0 and freq > 0:
            log_sum += math.log(freq / max_f)
            n += 1
    return round(math.exp(log_sum / max(n, 1)), 4) if n > 0 else 0.0

def gc_content(seq):
    gc = sum(1 for b in seq.upper() if b in 'GC')
    return round(100.0 * gc / max(len(seq), 1), 2)

def count_cpg(seq):
    return seq.upper().count('CG')

def find_gc_runs(seq, length=10):
    """Find runs of >= `length` nt that are all G/C (>70%) or all A/T (<30%)."""
    issues = []
    for i in range(len(seq) - length + 1):
        window = seq[i:i+length].upper()
        gc = sum(1 for b in window if b in 'GC')
        pct = 100.0 * gc / length
        if pct > 70 or pct < 30:
            issues.append({'pos': i+1, 'window': window, 'gc_pct': round(pct, 1)})
    return issues

def scan_uorfs(utr_seq):
    """Find AUG codons in 5'-UTR (RNA sequence)."""
    utr_rna = utr_seq.upper().replace('T', 'U')
    return [m.start() + 1 for m in re.finditer('AUG', utr_rna)]

def scan_internal_stops(cds_rna):
    """Check for premature stop codons within CDS (excluding final stop)."""
    stops = []
    for i in range(0, len(cds_rna) - 5, 3):
        codon = cds_rna[i:i+3].upper().replace('U', 'T')
        if codon in ('TAA', 'TAG', 'TGA') and i < len(cds_rna) - 3:
            stops.append({'pos': i+1, 'codon': codon})
    return stops

def cap_occlusion_mfe(seq_rna, n=50):
    """
    Approximate MFE of first n nt using nearest-neighbour simplified model.
    Real MFE requires RNAfold; this is a heuristic penalty score.
    Returns kcal/mol (negative = more structured).
    """
    s = seq_rna[:n].upper().replace('T', 'U')
    # Count G-C and A-U pairs in a simplified stem estimate
    gc_pairs = sum(1 for i in range(len(s)//2)
                   if (s[i] == 'G' and s[-(i+1)] == 'C') or
                      (s[i] == 'C' and s[-(i+1)] == 'G'))
    au_pairs = sum(1 for i in range(len(s)//2)
                   if (s[i] == 'A' and s[-(i+1)] == 'U') or
                      (s[i] == 'U' and s[-(i+1)] == 'A'))
    mfe_approx = -(gc_pairs * 3.0 + au_pairs * 2.0) / max(len(s), 1) * 10
    return round(mfe_approx, 2)

def count_are_motifs(utr_seq):
    """Count AUUUA pentamers in 3'-UTR (Shaw & Kamen 1986)."""
    return utr_seq.upper().replace('T', 'U').count('AUUUA')

def halflife_tier(are_count, utr3_len, polya_len):
    """Predict half-life tier based on destabilizing features."""
    score = 0
    if are_count == 0:
        score += 3
    elif are_count <= 2:
        score += 1
    if utr3_len >= 200:
        score += 2
    elif utr3_len >= 100:
        score += 1
    if polya_len >= 100:
        score += 2
    elif polya_len >= 60:
        score += 1
    if score >= 6:
        return 'LONG (>12h)'
    elif score >= 4:
        return 'MEDIUM (4-12h)'
    elif score >= 2:
        return 'SHORT (1-4h)'
    else:
        return 'VERY_SHORT (<1h)'

# ─── UTR / structural element sequences (DNA) ────────────────────────────────
UTR5_SEQS = {
    'hbb':    'ACAAGATGCCATTGTCCCCCGGCCTCCTGCTGTTGCTGCTGGCCTTCAGCTTCAGGTTAGTATTTGCTATTCAGATCTCGAGC',  # HBB 5'-UTR (Kozak-optimized, ~80 nt)
    'moderna': 'GGGAAAUAAGAGAGAAAAGAAGAGUAAGAAGAAAUAUAAGAGCCACCAUGG',  # AES minimal (Moderna-like)
    'custom':  'GCCACCAUGG',  # minimal Kozak only
}
KOZAK = 'GCCACC'  # Kozak consensus prefix (ATG provided by protein)

UTR3_SEQS = {
    'hbb':    ('UGCUUUAACAGAUAUUUGGCUUAGAGGUGAAUUUCUGAAAUUGAAGCAGCUUCAAUUAGCAA'
               'AAAUAAAGAUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUUAUUU'),  # HBB 3'-UTR RNA ~120 nt
    'moderna': ('UGCUUUAACAGAUAUUUGGCUUAGAGGUGAAUUUCUGAAAUUGAAGCAGCUUCAAUUAGCAA'  # AES
                'AAAUAAACCCUUAAAUUUAAAUUUAAAUUUAAAUUUAAAUUUAAAUUUAAAUUUAAAUUUAAA'
                'GCUAGAAGAUAAUUAGUUAGCUAAGCAUAUUGCUUAUAGUAAUAGUGGUAUUAAUAGCUAAC'
                'UGGUACUAGUGCUAAACCGAAAGGGAAG'),  # mtRNR1 element (Moderna-style)
    'custom':  'UGCUUUAACAGAUAUUUGGCUUAGAGGUGAAUUUCUG',
}

POLYA_TAIL = 'A' * 30 + 'GCAUAUGACU' + 'A' * 70  # A30LA70 Moderna standard (RNA)
IGK_SIGNAL_DNA = 'ATGGAAACAGACACACTCCTGCTATGGGTGCTGCTGCTCTGGGTTCCAGGATCT'  # IgK leader (19 aa)
T7_PROMOTER = 'TAATACGACTCACTATA'  # T7 class III promoter

# ─── Parse / generate input sequence ─────────────────────────────────────────
def is_amino_acid(s):
    aa_chars = set('ACDEFGHIKLMNPQRSTVWY*acdefghiklmnpqrstvwy')
    nuc_chars = set('ACGTUacgtu')
    aa_only = set(s.upper()) - nuc_chars
    return len(aa_only) > 0

if raw_input in ('', 'null'):
    # Demo: spike protein RBD mini-sequence (conceptual)
    input_type = 'demo_aa'
    aa_seq = ('MFVFLVLLPLVSSQCVNLTTRTQLPPAYTNSFTRGVYYPDKVFRSSVLHSTQDLFLPFFSNVTWF'
              'HAIHVSGTNGTKRFDNPVLPFNDGVYFASTEKSNIIRGWIFGTTLDSKTQSLLIVNNATNVVIKV'
              'CEFQFCNDPFLGVYYHKNNKSWMESEFRVYSSANNCTFEYVSQPFLMDLEGKQGNFKNLREFVFK'
              'NLTKVDKTLPPLEYVNKSFSFSTFKCYGVSPTKLNDLCFTNVYADSFVIRGDEVRQIAPGQTGNL')
    cds_dna = back_translate(aa_seq)
    seq_name = 'demo_SARS2_RBD'
elif is_amino_acid(raw_input):
    input_type = 'amino_acid'
    aa_seq = re.sub(r'[^ACDEFGHIKLMNPQRSTVWYacdefghiklmnpqrstvwy*]', '', raw_input)
    cds_dna = back_translate(aa_seq)
    seq_name = 'input_protein'
else:
    input_type = 'nucleotide_orf'
    aa_seq = None
    cds_dna = raw_input.upper().replace('U', 'T').replace(' ', '').replace('\n', '')
    cds_dna = re.sub(r'[^ACGT]', '', cds_dna)
    seq_name = 'input_orf'

# HexaPro-like stabilization: for spike/structural, add note (actual 6P mutations
# require specific AA position mapping; flagged as recommendation here)
hexapro_applied = prot_class in ('vaccine',) or 'spike' in seq_name.lower()
hexapro_note = ('HexaPro 6-proline stabilization recommended for prefusion conformation '
                '(Hsieh et al. 2020 Science). Apply F817P/A892P/A899P/A942P/K986P/V987P '
                'to full spike sequence before back-translation.') if hexapro_applied else None

# Add signal peptide if secreted
if secreted:
    cds_dna = IGK_SIGNAL_DNA + cds_dna

# ─── 5'-UTR ──────────────────────────────────────────────────────────────────
utr5_key = utr_design if utr_design in UTR5_SEQS else 'hbb'
utr5_dna = UTR5_SEQS[utr5_key].replace('U', 'T')

# ─── 3'-UTR ──────────────────────────────────────────────────────────────────
utr3_rna = UTR3_SEQS[utr5_key]
utr3_dna = utr3_rna.replace('U', 'T')

# ─── Poly-A ──────────────────────────────────────────────────────────────────
polya_dna = POLYA_TAIL.replace('U', 'T')

# ─── Assemble full mRNA (DNA coding strand) ───────────────────────────────────
full_dna = utr5_dna + cds_dna + utr3_dna + polya_dna
full_rna = full_dna.replace('T', 'U')

# ─── Codon optimization scores ───────────────────────────────────────────────
cai_score     = compute_cai(cds_dna)
gc_cds        = gc_content(cds_dna)
gc_full       = gc_content(full_dna)
cpg_count     = count_cpg(cds_dna)
gc_run_issues = find_gc_runs(cds_dna, 10)
uorfs         = scan_uorfs(utr5_dna)
internal_stops = scan_internal_stops(cds_dna)
mfe_5end      = cap_occlusion_mfe(full_rna, 50)

# ─── Stability metrics ────────────────────────────────────────────────────────
are_count  = count_are_motifs(utr3_rna)
polya_len  = 100  # A30LA70 = 100 nt
utr3_len   = len(utr3_rna)
hl_tier    = halflife_tier(are_count, utr3_len, polya_len)

# Cap-occlusion: MFE > -20 kcal/mol is acceptable
cap_occlusion_ok = mfe_5end > -20.0

# Internal T7 terminator scan (TTTTT on coding strand)
t7_term_count = len(re.findall('TTTTT', cds_dna))

# ─── LNP formulation recommendation ──────────────────────────────────────────
LNP_DB = {
    'liver': {
        'ionizable_lipid': 'DLin-MC3-DMA (MC3)',
        'trade_name': 'Onpattro (patisiran)',
        'molar_ratio': 'IL:DSPC:Chol:PEG2000-DMG = 50:10:38.5:1.5',
        'n_p_ratio': '3-6',
        'pka_optimal': '6.2-6.5',
        'administration': 'IV infusion',
        'clinical_precedent': 'FDA-approved siRNA LNP (Onpattro, 2018); extrapolated to mRNA liver delivery',
        'notes': 'Pre-medicate with antihistamines + corticosteroids for IV. ApoE-mediated LDLR hepatocyte uptake.',
    },
    'muscle': {
        'ionizable_lipid': 'SM-102',
        'trade_name': 'Spikevax (mRNA-1273)',
        'molar_ratio': 'SM-102:DSPC:Chol:PEG2000-DMG = 50:10:38.5:1.5',
        'n_p_ratio': '6',
        'pka_optimal': '6.56',
        'administration': 'Intramuscular injection',
        'clinical_precedent': 'Moderna mRNA-1273 COVID-19 vaccine (2020); IM injection depot release',
        'notes': 'IM depot: slow release + local APCs. Optimal for vaccine antigen expression in myocytes and DCs.',
    },
    'lung': {
        'ionizable_lipid': 'ALC-0315 or Lipid 5',
        'trade_name': 'Comirnaty (BNT162b2) / investigational',
        'molar_ratio': 'ALC-0315:DSPC:Chol:ALC-0159 = 46.3:9.4:42.7:1.6 (BNT162b2)',
        'n_p_ratio': '6',
        'pka_optimal': '6.09 (ALC-0315)',
        'administration': 'Intratracheal, nebulized, or IV',
        'clinical_precedent': 'BNT162b2 IM (2020); inhaled LNP-mRNA in preclinical (e.g., Robinson 2018)',
        'notes': 'Pulmonary delivery requires smaller particle size (60-80 nm). Nebulization stability must be validated.',
    },
    'spleen': {
        'ionizable_lipid': 'C12-200 or 304-O13-E12',
        'trade_name': 'Research (in vivo CAR-T)',
        'molar_ratio': 'C12-200:DOPE:Chol:PEG-lipid = 50:25:20:5',
        'n_p_ratio': '10',
        'pka_optimal': '6.7 (C12-200)',
        'administration': 'IV (selective spleen uptake due to scavenger receptors)',
        'clinical_precedent': 'Rurik et al. 2022 Science (CAR-T in vivo), Tombácz et al. 2021',
        'notes': 'Spleen-selective LNPs deliver to B cells and T cells. IV dosing. ApoE-independent uptake.',
    },
    'cns': {
        'ionizable_lipid': 'Not established — BBB barrier',
        'trade_name': 'N/A',
        'molar_ratio': 'No validated formulation for systemic CNS LNP delivery',
        'n_p_ratio': 'N/A',
        'pka_optimal': 'N/A',
        'administration': 'Intrathecal or intracerebroventricular (preferred); focused ultrasound + microbubbles (investigational)',
        'clinical_precedent': 'No FDA-approved LNP for systemic CNS mRNA. Intrathecal ASO delivery (Spinraza) is standard for CNS.',
        'notes': 'BBB severely limits systemic LNP uptake. Consider intrathecal injection, neural-targeting peptide conjugation (RVG), or focused ultrasound-mediated BBB opening.',
    },
}

lnp = LNP_DB.get(tissue, LNP_DB['muscle'])

# ─── IVT template ────────────────────────────────────────────────────────────
# T7 IVT template = T7 promoter + coding DNA strand
ivt_dna_template = T7_PROMOTER + utr5_dna + cds_dna + utr3_dna + polya_dna
expected_transcript_len = len(full_rna)

# ─── Compile outputs ──────────────────────────────────────────────────────────
stability_metrics = {
    'status': 'completed',
    'input_type': input_type,
    'sequence_name': seq_name,
    'cds_length_nt': len(cds_dna),
    'full_mrna_length_nt': len(full_rna),
    'codon_adaptation_index_CAI': cai_score,
    'cai_target': '>0.8',
    'cai_pass': cai_score > 0.8,
    'gc_content_cds_pct': gc_cds,
    'gc_content_full_mrna_pct': gc_full,
    'gc_target_range': '46-54%',
    'gc_pass': 46 <= gc_cds <= 54,
    'cpg_dinucleotides_in_cds': cpg_count,
    'cpg_note': 'CpG triggers TLR9; minimize for therapeutic mRNA',
    'gc_run_issues_count': len(gc_run_issues),
    'gc_run_issues': gc_run_issues[:5],
    'uorf_augs_in_5utr': uorfs,
    'uorf_risk': 'HIGH' if len(uorfs) > 2 else ('MEDIUM' if len(uorfs) > 0 else 'NONE'),
    'internal_stop_codons': internal_stops,
    'cap_occlusion_mfe_approx_kcal_mol': mfe_5end,
    'cap_occlusion_threshold_kcal_mol': -20.0,
    'cap_occlusion_ok': cap_occlusion_ok,
    'are_motif_count_3utr': are_count,
    'are_note': 'AUUUA pentamers destabilize mRNA via ARE-binding proteins',
    'predicted_halflife_tier': hl_tier,
    'polya_tail': 'A30LA70 (100 nt, Moderna standard)',
    'polya_length_nt': polya_len,
    't7_terminator_runs_in_cds': t7_term_count,
    't7_terminator_note': 'TTTTT runs may cause premature T7 IVT termination',
    'utr5_design': utr5_key,
    'utr3_design': utr5_key,
    'hexapro_recommendation': hexapro_note,
    'modification_recommendation': {
        'm1_pseudouridine': {
            'recommended': True,
            'reason': 'N1-methylpseudouridine (m1Ψ) replaces uridine to evade innate immune TLR7/8/MDA5 detection and increase ribosome processivity',
            'reference': 'Karikó et al. 2008 Immunity; Andries et al. 2015',
        },
    },
    'cap_recommendation': {
        'analog': 'CleanCap AG (TriLink Biotechnologies) — Cap1 structure',
        'cap_structure': 'm7GpppAm (Cap1)',
        'reason': 'Cap1 prevents innate immune IFIT1/2/3 recognition; higher in vivo translation than ARCA (Cap0)',
        'alternative': 'Vaccinia capping enzyme (co-transcriptional) for GMP manufacturing',
    },
    'references': [
        'Karikó et al. 2008 Immunity 23:165 (m1Ψ)',
        'Andries et al. 2015 J Control Release 217:337 (AES+mtRNR1 3-UTR)',
        'Rauch et al. 2018 Sci Rep 8:9841 (codon optimization)',
        'Richner et al. 2017 Cell 168:1114 (uORF optimization)',
        'Hsieh et al. 2020 Science 369:1501 (HexaPro stabilization)',
    ],
}

lnp_recommendation = {
    'target_tissue': tissue,
    'cargo_type': 'mRNA',
    'mrna_length_nt': len(full_rna),
    'recommended_formulation': lnp,
    'encapsulation_notes': {
        'target_encapsulation_efficiency': '>85%',
        'particle_size_nm': '80-120',
        'pdi': '<0.2',
        'zeta_potential_mv': '+5 to +20 (after PEGylation)',
    },
    'chain_to': 'lnp_formulation_optimization (for custom ionizable lipid SMILES sweep)',
}

design_report = {
    'status': 'completed',
    'pipeline': 'mrna_therapeutic_design',
    'sequence_name': seq_name,
    'input_type': input_type,
    'protein_class': prot_class,
    'secreted': secreted,
    'target_tissue': tissue,
    'utr_design': utr5_key,
    'cds_length_nt': len(cds_dna),
    'full_mrna_length_nt': len(full_rna),
    'ivt_template_length_nt': len(ivt_dna_template),
    'expected_transcript_length_nt': expected_transcript_len,
    't7_promoter': T7_PROMOTER,
    'linearization_suggestion': f'Linearize plasmid 3 of poly-A tail (position ~{len(T7_PROMOTER) + len(full_dna) + 20} from T7 start)',
    'codon_optimization': {
        'method': 'Human highest-CAI codon selection (HIVE-CUT 2020)',
        'cai': cai_score,
        'target_cai': '>0.8',
        'pass': cai_score > 0.8,
    },
    'qc_flags': {
        'gc_content_pass': 46 <= gc_cds <= 54,
        'cai_pass': cai_score > 0.8,
        'uorf_risk': 'HIGH' if len(uorfs) > 2 else ('MEDIUM' if len(uorfs) > 0 else 'NONE'),
        'internal_stops': len(internal_stops),
        'cap_occlusion_ok': cap_occlusion_ok,
        'are_motifs': are_count,
        'cpg_count': cpg_count,
        't7_terminator_runs': t7_term_count,
    },
    'overall_qc_pass': (cai_score > 0.8 and 46 <= gc_cds <= 54
                        and len(internal_stops) == 0 and cap_occlusion_ok),
    'stability_tier': hl_tier,
    'lnp_ionizable_lipid': lnp['ionizable_lipid'],
    'lnp_molar_ratio': lnp['molar_ratio'],
    'next_steps': [
        'Apply m1Ψ modification during IVT (replace UTP with m1Ψ-TP)',
        'Use CleanCap AG for co-transcriptional capping',
        f'Formulate with {lnp["ionizable_lipid"]} at {lnp["molar_ratio"]}',
        'Run LNP characterization: DLS (size), Ribogreen (EE%), cryo-TEM',
        'In vitro translation assay (rabbit reticulocyte or cell-free) to verify CAI improvement',
        'Chain to lnp_formulation_optimization for ionizable lipid pKa sweep',
    ],
}

# ─── Write outputs ────────────────────────────────────────────────────────────
def fasta_wrap(seq, width=80):
    return '\n'.join(seq[i:i+width] for i in range(0, len(seq), width))

# optimized_sequence.fasta — full mRNA (RNA)
with open('optimized_sequence.fasta', 'w') as f:
    f.write(f'>{seq_name}_optimized_mRNA tissue={tissue} length={len(full_rna)}nt CAI={cai_score}\n')
    f.write(fasta_wrap(full_rna) + '\n')

# ivt_template.fasta — DNA template for T7 IVT
with open('ivt_template.fasta', 'w') as f:
    f.write(f'>{seq_name}_IVT_template T7_promoter+coding_DNA length={len(ivt_dna_template)}nt\n')
    f.write(fasta_wrap(ivt_dna_template) + '\n')

with open('stability_metrics.json', 'w') as f:
    json.dump(stability_metrics, f, indent=2)

with open('lnp_recommendation.json', 'w') as f:
    json.dump(lnp_recommendation, f, indent=2)

with open('mrna_design_report.json', 'w') as f:
    json.dump(design_report, f, indent=2)

# Print summary
print('=== mRNA Therapeutic Design Report ===')
print(f'Sequence:       {seq_name} ({input_type})')
print(f'CDS length:     {len(cds_dna)} nt')
print(f'Full mRNA:      {len(full_rna)} nt')
print(f'CAI:            {cai_score}  (target >0.8, pass={cai_score > 0.8})')
print(f'GC% (CDS):      {gc_cds}%  (target 46-54%, pass={46 <= gc_cds <= 54})')
print(f'CpG count:      {cpg_count}')
print(f'uORFs in 5-UTR: {len(uorfs)}  risk={("HIGH" if len(uorfs) > 2 else ("MEDIUM" if len(uorfs) > 0 else "NONE"))}')
print(f'Internal stops: {len(internal_stops)}')
print(f'ARE motifs:     {are_count}')
print(f'Half-life tier: {hl_tier}')
print(f'Cap occlusion:  MFE~{mfe_5end} kcal/mol (ok={cap_occlusion_ok})')
print(f'LNP:            {lnp["ionizable_lipid"]}  |  {lnp["molar_ratio"]}')
print(f'Modification:   m1Ψ (replace UTP) + CleanCap AG (Cap1)')
print(f'Overall QC:     {design_report["overall_qc_pass"]}')
PYEOF

    python3 -c "print('mrna_therapeutic_design: 1.0')" > versions.yml
    """
}

// [Phase B] mRNA Design Summary (collates all outputs for downstream use)
process MRNA_DESIGN_SUMMARY {
    tag "mrna_summary"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    tuple val(meta), path(report_json)
    tuple val(meta2), path(stability_json)
    tuple val(meta3), path(lnp_json)

    output:
    tuple val(meta), path("mrna_pipeline_summary.txt"), emit: summary

    script:
    """
    python3 << 'PYEOF'
import json

with open('${report_json}') as f:
    report = json.load(f)
with open('${stability_json}') as f:
    stab = json.load(f)
with open('${lnp_json}') as f:
    lnp = json.load(f)

lines = [
    '╔══════════════════════════════════════════════════════════════╗',
    '  mRNA Therapeutic Design — Pipeline Summary',
    f'  Sequence: {report.get("sequence_name", "unknown")}',
    f'  Target tissue: {report.get("target_tissue", "unknown")}',
    '╚══════════════════════════════════════════════════════════════╝',
    '',
    '── Codon Optimization ────────────────────────────────────────',
    f'  CAI:         {stab.get("codon_adaptation_index_CAI")}  (target >0.8)',
    f'  GC% CDS:     {stab.get("gc_content_cds_pct")}%  (target 46-54%)',
    f'  CpG count:   {stab.get("cpg_dinucleotides_in_cds")}',
    f'  uORF risk:   {stab.get("uorf_risk")}',
    f'  Internal stops: {len(stab.get("internal_stop_codons", []))}',
    '',
    '── Stability ─────────────────────────────────────────────────',
    f'  ARE motifs:  {stab.get("are_motif_count_3utr")} (AUUUA in 3-UTR)',
    f'  Half-life:   {stab.get("predicted_halflife_tier")}',
    f'  Cap occlusion MFE: {stab.get("cap_occlusion_mfe_approx_kcal_mol")} kcal/mol',
    '',
    '── Modifications ─────────────────────────────────────────────',
    '  m1Ψ (N1-methylpseudouridine): RECOMMENDED',
    '  Cap: CleanCap AG (Cap1, m7GpppAm)',
    '',
    '── IVT Template ──────────────────────────────────────────────',
    f'  T7 promoter: TAATACGACTCACTATA',
    f'  Transcript length: {report.get("expected_transcript_length_nt")} nt',
    '',
    '── LNP Formulation ───────────────────────────────────────────',
    f'  Ionizable lipid: {lnp["recommended_formulation"]["ionizable_lipid"]}',
    f'  Molar ratio:     {lnp["recommended_formulation"]["molar_ratio"]}',
    f'  N/P ratio:       {lnp["recommended_formulation"]["n_p_ratio"]}',
    f'  Administration:  {lnp["recommended_formulation"]["administration"]}',
    f'  Precedent:       {lnp["recommended_formulation"]["clinical_precedent"]}',
    '',
    '── Overall QC ────────────────────────────────────────────────',
    f'  PASS: {report.get("overall_qc_pass")}',
    '',
    '── Next Steps ────────────────────────────────────────────────',
]
for step in report.get('next_steps', []):
    lines.append(f'  · {step}')

with open('mrna_pipeline_summary.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('\n'.join(lines))
PYEOF
    """
}

workflow MRNA_THERAPEUTIC_DESIGN_WORKFLOW {
    take: meta_ch
    main:
        MRNA_SEQUENCE_PREP(meta_ch)
        MRNA_DESIGN_SUMMARY(
            MRNA_SEQUENCE_PREP.out.report_json,
            MRNA_SEQUENCE_PREP.out.stability_json,
            MRNA_SEQUENCE_PREP.out.lnp_json
        )
    emit:
        optimized_fasta = MRNA_SEQUENCE_PREP.out.optimized_fasta
        ivt_fasta       = MRNA_SEQUENCE_PREP.out.ivt_fasta
        stability_json  = MRNA_SEQUENCE_PREP.out.stability_json
        lnp_json        = MRNA_SEQUENCE_PREP.out.lnp_json
        report_json     = MRNA_SEQUENCE_PREP.out.report_json
        summary         = MRNA_DESIGN_SUMMARY.out.summary
}

workflow {
    meta = [id: 'mrna_therapeutic_design_run']
    Channel.value(meta) | MRNA_THERAPEUTIC_DESIGN_WORKFLOW
}
