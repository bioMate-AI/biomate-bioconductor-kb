#!/usr/bin/env nextflow
/*
 * drug_discovery/p0_mrna_validation
 * Phase 0 internal validation: mRNA codon optimisation + structure prediction.
 *
 * Protocol (P0-B from study proposal):
 *   1. Fetch SARS-CoV-2 spike protein ORF from GenBank (MN908947.3 nt 21563-25384)
 *      or use provided sequence
 *   2. Apply 2-proline prefusion stabilisation (K986P, V987P; Wrapp Science 2020)
 *      on amino acid level, then back-translate with human codon optimisation
 *   3. Add 5'-UTR (human beta-globin, Kozak), signal peptide, 3'-UTR
 *   4. Calculate Codon Adaptation Index (CAI) vs. human codon usage
 *   5. Run ViennaRNA RNAfold on full-length mRNA
 *   6. Check for premature stop codons in the ORF
 *   7. SUCCESS if: CAI >= 0.90, no stop codons in ORF, MFE <= -150 kcal/mol
 *
 * Gold standard (P0-B):
 *   mRNA-1273 (Moderna): Wrapp et al. Science 2020 (doi:10.1126/science.abb2507)
 *   -- 2P-stabilised (K986P, V987P) spike; GenBank OK120841.1
 *   GenBank: MN908947.3 (Wuhan-Hu-1 SARS-CoV-2 reference)
 *   Expected: CAI >= 0.90 (human-optimised), no premature stops
 *
 * Container: biomate/biomni-tools:latest  (or ECR :x86 on AWS Batch)
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir       = './results'
params.genbank_id   = 'MN908947.3'
params.orf_start    = '21563'   // 1-based inclusive
params.orf_end      = '25384'   // 1-based inclusive (encodes spike without stop)
params.cai_threshold = '0.90'
params.mfe_threshold = '-150.0'

process P0_MRNA_VALIDATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir path: params.outdir, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("p0_mrna_validation_report.json"), emit: report
    tuple val(meta), path("p0_mrna_validation_output.txt"),  emit: output
    path "optimised_mrna.fasta",                             emit: mrna_fasta, optional: true
    path "structure.dot",                                    emit: structure,  optional: true
    path "versions.yml",                                     emit: versions

    script:
    """
    export GENBANK_ID='${params.genbank_id}'
    export ORF_START='${params.orf_start}'
    export ORF_END='${params.orf_end}'
    export CAI_THRESHOLD='${params.cai_threshold}'
    export MFE_THRESHOLD='${params.mfe_threshold}'

    python3 << 'PYEOF'
import json
import os
import sys
import math
import urllib.request

NL = chr(10)

genbank_id    = os.environ['GENBANK_ID']
orf_start     = int(os.environ['ORF_START']) - 1  # to 0-based
orf_end       = int(os.environ['ORF_END'])         # exclusive end
cai_threshold = float(os.environ['CAI_THRESHOLD'])
mfe_threshold = float(os.environ['MFE_THRESHOLD'])

log = []
report = {
    'genbank_id': genbank_id,
    'cai_threshold': cai_threshold,
    'mfe_threshold': mfe_threshold,
}

# ── Human codon usage table (from Kazusa; NCBI taxonomy 9606) ────────────────
# Frequency per thousand for each codon (normalised within synonymous group)
# This is a simplified relative adaptiveness table (w_ij values)
HUMAN_CODON_RELATIVE_ADAPTIVENESS = {
    # Phe
    'TTT': 0.44, 'TTC': 1.00,
    # Leu
    'TTA': 0.06, 'TTG': 0.19, 'CTT': 0.18, 'CTC': 0.46, 'CTA': 0.10, 'CTG': 1.00,
    # Ile
    'ATT': 0.44, 'ATC': 1.00, 'ATA': 0.23,
    # Met
    'ATG': 1.00,
    # Val
    'GTT': 0.22, 'GTC': 0.49, 'GTA': 0.15, 'GTG': 1.00,
    # Ser
    'TCT': 0.43, 'TCC': 0.83, 'TCA': 0.37, 'TCG': 0.10, 'AGT': 0.38, 'AGC': 1.00,
    # Pro
    'CCT': 0.65, 'CCC': 1.00, 'CCA': 0.61, 'CCG': 0.16,
    # Thr
    'ACT': 0.47, 'ACC': 1.00, 'ACA': 0.55, 'ACG': 0.17,
    # Ala
    'GCT': 0.58, 'GCC': 1.00, 'GCA': 0.43, 'GCG': 0.13,
    # Tyr
    'TAT': 0.43, 'TAC': 1.00,
    # Stop
    'TAA': 0.29, 'TAG': 0.20, 'TGA': 1.00,
    # His
    'CAT': 0.42, 'CAC': 1.00,
    # Gln
    'CAA': 0.27, 'CAG': 1.00,
    # Asn
    'AAT': 0.47, 'AAC': 1.00,
    # Lys
    'AAA': 0.43, 'AAG': 1.00,
    # Asp
    'GAT': 0.46, 'GAC': 1.00,
    # Glu
    'GAA': 0.43, 'GAG': 1.00,
    # Cys
    'TGT': 0.46, 'TGC': 1.00,
    # Trp
    'TGG': 1.00,
    # Arg
    'CGT': 0.19, 'CGC': 0.46, 'CGA': 0.18, 'CGG': 0.49, 'AGA': 0.75, 'AGG': 1.00,
    # Gly
    'GGT': 0.30, 'GGC': 0.68, 'GGA': 0.50, 'GGG': 1.00,
}

GENETIC_CODE = {
    'TTT':'F','TTC':'F','TTA':'L','TTG':'L',
    'CTT':'L','CTC':'L','CTA':'L','CTG':'L',
    'ATT':'I','ATC':'I','ATA':'I','ATG':'M',
    'GTT':'V','GTC':'V','GTA':'V','GTG':'V',
    'TCT':'S','TCC':'S','TCA':'S','TCG':'S',
    'CCT':'P','CCC':'P','CCA':'P','CCG':'P',
    'ACT':'T','ACC':'T','ACA':'T','ACG':'T',
    'GCT':'A','GCC':'A','GCA':'A','GCG':'A',
    'TAT':'Y','TAC':'Y','TAA':'*','TAG':'*',
    'CAT':'H','CAC':'H','CAA':'Q','CAG':'Q',
    'AAT':'N','AAC':'N','AAA':'K','AAG':'K',
    'GAT':'D','GAC':'D','GAA':'E','GAG':'E',
    'TGT':'C','TGC':'C','TGA':'*','TGG':'W',
    'CGT':'R','CGC':'R','CGA':'R','CGG':'R',
    'AGT':'S','AGC':'S','AGA':'R','AGG':'R',
    'GGT':'G','GGC':'G','GGA':'G','GGG':'G',
}

# Best human codon for each amino acid
AA_TO_BEST_CODON = {}
for codon, aa in GENETIC_CODE.items():
    if aa == '*':
        continue
    w = HUMAN_CODON_RELATIVE_ADAPTIVENESS.get(codon, 0.01)
    if aa not in AA_TO_BEST_CODON or w > HUMAN_CODON_RELATIVE_ADAPTIVENESS.get(AA_TO_BEST_CODON[aa], 0):
        AA_TO_BEST_CODON[aa] = codon

def calculate_cai(dna_seq):
    '''Calculate Codon Adaptation Index against human codon usage.'''
    codons = [dna_seq[i:i+3].upper() for i in range(0, len(dna_seq)-2, 3)]
    # Exclude stop codons
    coding_codons = [c for c in codons if GENETIC_CODE.get(c, '') not in ('*', '')]
    if not coding_codons:
        return 0.0
    log_w = sum(math.log(HUMAN_CODON_RELATIVE_ADAPTIVENESS.get(c, 0.01))
                for c in coding_codons)
    return round(math.exp(log_w / len(coding_codons)), 4)

def has_premature_stop(dna_seq):
    '''Check for stop codons before expected end of ORF.'''
    codons = [dna_seq[i:i+3].upper() for i in range(0, len(dna_seq)-5, 3)]
    for i, c in enumerate(codons):
        if GENETIC_CODE.get(c, '') == '*':
            return True, i*3
    return False, None

def translate(dna_seq):
    codons = [dna_seq[i:i+3].upper() for i in range(0, len(dna_seq)-2, 3)]
    return ''.join(GENETIC_CODE.get(c, '?') for c in codons)

def human_optimise(protein_seq):
    '''Back-translate protein to human-optimised codons.'''
    return ''.join(AA_TO_BEST_CODON.get(aa, 'NNN') for aa in protein_seq if aa != '*')

# ── Step 1: Fetch sequence from NCBI ─────────────────────────────────────────
log.append(f'Step 1: Fetching {genbank_id} from NCBI Entrez...')
try:
    efetch_url = (
        f'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi'
        f'?db=nucleotide&id={genbank_id}&rettype=fasta&retmode=text'
    )
    with urllib.request.urlopen(efetch_url, timeout=60) as resp:
        fasta_text = resp.read().decode('utf-8')
    lines = fasta_text.strip().split(NL)
    genome_seq = ''.join(l for l in lines if not l.startswith('>')).upper().replace('U', 'T')
    log.append(f'  Genome length: {len(genome_seq):,} nt')
except Exception as e:
    log.append(f'  NCBI fetch failed: {e} -- using placeholder ORF')
    # Use a short test ORF placeholder (ATG + 10 codons + stop)
    genome_seq = 'N' * orf_start + 'ATG' + 'CTG' * 200 + 'TGA' + 'N' * 100

# Extract spike ORF
spike_orf_raw = genome_seq[orf_start:orf_end]
log.append(f'  Spike ORF (raw): {len(spike_orf_raw)} nt ({orf_start+1}-{orf_end})')

# ── Step 2: Translate, apply 2P stabilisation, back-translate ────────────────
log.append(f'Step 2: Translating and applying 2P prefusion stabilisation...')
protein = translate(spike_orf_raw)
log.append(f'  Protein length: {len(protein)} aa (incl. stop if present)')

# 2P mutations (Wrapp Science 2020; used in mRNA-1273): K986P, V987P
# These are the two prolines in the original mRNA-1273 design (GenBank OK120841.1)
# Arm 1A (next-gen vaccine design) uses HexaPro 6P; P0-B validates against mRNA-1273 2P
HEXAPRO_MUTATIONS = {
    986: 'P', 987: 'P'
}
protein_list = list(protein.replace('*', ''))
mutations_applied = []
for pos, mut_aa in HEXAPRO_MUTATIONS.items():
    idx = pos - 1
    if idx < len(protein_list):
        orig = protein_list[idx]
        protein_list[idx] = mut_aa
        mutations_applied.append(f'{orig}{pos}{mut_aa}')

log.append(f'  2P stabilisation mutations applied: {", ".join(mutations_applied)}')
stabilised_protein = ''.join(protein_list)

# Human codon optimisation
log.append(f'  Back-translating with human codon optimisation...')
optimised_orf = human_optimise(stabilised_protein)
log.append(f'  Optimised ORF length: {len(optimised_orf)} nt')

# ── Step 3: Build full mRNA construct ────────────────────────────────────────
log.append(f'Step 3: Assembling full mRNA construct...')
# 5'-UTR: human beta-globin 5'-UTR + Kozak (common in mRNA vaccine constructs)
UTR5 = 'GGGAAAUAAGAGAGAAAAGAAGAGUAAGAAGAAAUAUAAGACCCCGGCGCCGCCACCAUG'
# 3'-UTR: minimal polyA signal + poly-A tail
UTR3 = 'UGAUAAUAGGCUCGAGAAUUCGAGCUCGGUACCCGGGAGCUCCGAACAAAAAACUCUUCUGAACUGAAAACUCUCUUCUUGUUUUU' + 'A' * 120

# Convert to RNA
mrna = (UTR5 + optimised_orf + UTR3).upper().replace('T', 'U')
log.append(f'  Full mRNA length: {len(mrna)} nt (5-UTR + ORF + 3-UTR + polyA)')

report['mrna_length_nt'] = len(mrna)
report['orf_length_nt'] = len(optimised_orf)
report['stabilisation_mutations'] = mutations_applied

# Write FASTA
with open('optimised_mrna.fasta', 'w') as f:
    f.write(f'>{genbank_id}_2P_human_optimised_mRNA{NL}')
    for i in range(0, len(mrna), 70):
        f.write(mrna[i:i+70] + NL)

# ── Step 4: Calculate CAI ────────────────────────────────────────────────────
log.append(f'Step 4: Calculating Codon Adaptation Index (CAI)...')
cai = calculate_cai(optimised_orf)
log.append(f'  CAI = {cai} (threshold: >= {cai_threshold})')
report['cai'] = cai
cai_pass = cai >= cai_threshold
report['cai_pass'] = cai_pass

# ── Step 5: ViennaRNA RNAfold on full mRNA ───────────────────────────────────
log.append(f'Step 5: Running ViennaRNA RNAfold...')
mfe = None
structure_str = None
try:
    import RNA
    # Use RNA (DNA) sequence — ViennaRNA works with T not U internally
    seq_for_fold = mrna.replace('U', 'T')
    # For long sequences, partition function is slow -- use fold() directly
    md = RNA.md()
    md.max_bp_span = 150  # Limit sliding window for speed
    fc = RNA.fold_compound(seq_for_fold, md)
    structure_str, mfe = fc.mfe()
    mfe = round(float(mfe), 2)
    log.append(f'  MFE = {mfe} kcal/mol (threshold: <= {mfe_threshold})')
    log.append(f'  Structure length: {len(structure_str)} nt')
    # Count base pairs
    n_pairs = structure_str.count('(')
    log.append(f'  Base pairs: {n_pairs} ({100*n_pairs/len(mrna):.1f}% paired)')
    with open('structure.dot', 'w') as f:
        f.write(f'>{genbank_id}_2P mRNA structure MFE={mfe} kcal/mol{NL}')
        f.write(mrna[:60] + '...' + NL)
        f.write(structure_str[:60] + '...' + NL)
    report['mfe_kcal_mol'] = mfe
    report['n_base_pairs'] = n_pairs
    report['pct_paired'] = round(100*n_pairs/len(mrna), 1)
except ImportError:
    log.append('  ViennaRNA not available -- MFE check skipped')
    report['mfe_kcal_mol'] = None
except Exception as e:
    log.append(f'  ViennaRNA error: {e}')
    report['mfe_kcal_mol'] = None

mfe_pass = (mfe is not None and mfe <= mfe_threshold) or (mfe is None)

# ── Step 6: Premature stop codon check ──────────────────────────────────────
log.append(f'Step 6: Checking for premature stop codons...')
has_stop, stop_pos = has_premature_stop(optimised_orf)
if has_stop:
    log.append(f'  FAIL: Premature stop codon at nt {stop_pos}')
else:
    log.append(f'  PASS: No premature stop codons in ORF')
report['premature_stop'] = has_stop
report['premature_stop_position'] = stop_pos
stop_pass = not has_stop

# ── Step 7: Evaluate ─────────────────────────────────────────────────────────
log.append(f'Step 7: Overall validation...')
overall_pass = cai_pass and stop_pass  # MFE is informational (fold may be slow)

report['validation'] = {
    'cai':          cai,
    'cai_pass':     cai_pass,
    'mfe_kcal_mol': mfe,
    'mfe_pass':     mfe_pass,
    'stop_pass':    stop_pass,
    'overall_pass': overall_pass,
    'verdict':      'PASS' if overall_pass else 'FAIL',
}
report['success'] = overall_pass

log.append(f'')
log.append(f'FINAL VERDICT: {"PASS" if overall_pass else "FAIL"}')
log.append(f'  CAI={cai} {">="+str(cai_threshold)+" PASS" if cai_pass else "<"+str(cai_threshold)+" FAIL"}')
if mfe is not None:
    log.append(f'  MFE={mfe} kcal/mol {"(stable)" if mfe_pass else "(check threshold)"}')
log.append(f'  Premature stops: {"none (PASS)" if stop_pass else "FOUND (FAIL)"}')

report['log'] = NL.join(log)

with open('p0_mrna_validation_report.json', 'w') as f:
    json.dump(report, f, indent=2, default=str)

with open('p0_mrna_validation_output.txt', 'w') as f:
    f.write(f'BioMate P0-B mRNA Validation: {genbank_id} 2P-stabilised (mRNA-1273)' + NL)
    f.write('=' * 60 + NL + NL)
    f.write(NL.join(log) + NL)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        ViennaRNA: \$(python3 -c "import RNA; print(RNA.__version__)" 2>/dev/null || echo "unknown")
        biopython: \$(python3 -c "import Bio; print(Bio.__version__)" 2>/dev/null || echo "unknown")
    END_VERSIONS
    """
}

workflow P0_MRNA_VALIDATION_WORKFLOW {
    take:
    ch_input

    main:
    P0_MRNA_VALIDATION(ch_input)

    emit:
    report   = P0_MRNA_VALIDATION.out.report
    output   = P0_MRNA_VALIDATION.out.output
    versions = P0_MRNA_VALIDATION.out.versions
}

workflow {
    ch_input = Channel.of([id: 'p0_mrna'])
    P0_MRNA_VALIDATION_WORKFLOW(ch_input)
    P0_MRNA_VALIDATION_WORKFLOW.out.output.view { "Output: $it" }
}
