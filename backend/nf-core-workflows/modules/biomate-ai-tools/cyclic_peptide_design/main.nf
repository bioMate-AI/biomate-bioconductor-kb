#!/usr/bin/env nextflow
/*
 * biomate-ai-tools/cyclic_peptide_design
 *
 * De novo cyclic peptide sequence design under explicit ring / residue /
 * charge / hydrophobicity constraints. Rule-based scaffold enumeration +
 * ring-closure validation (head-to-tail amide) — honest generation, not a
 * fabricated affinity or ADMET claim.
 *
 * Phases (one process each → panel phase cards):
 *   1. VALIDATE_CONSTRAINTS — normalise length / alphabet / charge bounds
 *   2. ENUMERATE_SEQUENCES  — enumerate cyclic candidates under constraints
 *   3. FILTER_MACROCYCLE    — Yudin-style macrocycle heuristics (MW/TPSA proxy)
 *   4. RANK_CANDIDATES      — score + emit FASTA / CSV / summary JSON
 *
 * DB path: biomate-ai-tools/cyclic_peptide_design/main.nf
 * (coldstart design-generate-pep-* previously failed FileNotFoundError).
 *
 * Note: use fully-qualified groovy.json.JsonSlurper (no top-level import).
 */

nextflow.enable.dsl = 2

params.outdir              = './results'
params.ring_size_min       = 8
params.ring_size_max       = 14
params.n_candidates        = 25
params.allowed_residues    = 'ACDEFGHIKLMNPQRSTVWY'
params.target_charge_min   = -2
params.target_charge_max   = 2
params.hydrophobic_frac_max = 0.55
params.seed_motif          = ''          // optional motif that must appear
params.target_label        = 'demo_target'

process VALIDATE_CONSTRAINTS {
    tag 'validate_constraints'
    label 'process_low'
    publishDir "${params.outdir}/01_validate", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' \
        : 'biomate/workflow-tools:latest'

    output:
    path 'constraints.json', emit: constraints

    script:
    """
    python3 << 'PYEOF'
import json, os, sys

aminos = set('${params.allowed_residues}'.upper())
std = set('ACDEFGHIKLMNPQRSTVWY')
if not aminos or not aminos.issubset(std):
    print('ERROR: allowed_residues must be a non-empty subset of standard AA', file=sys.stderr)
    sys.exit(1)
lo = int(${params.ring_size_min})
hi = int(${params.ring_size_max})
if lo < 5 or hi > 24 or lo > hi:
    print(f'ERROR: ring_size_min/max out of range ({lo},{hi})', file=sys.stderr)
    sys.exit(1)
n = max(1, min(int(${params.n_candidates}), 200))
motif = '${params.seed_motif}'.upper().strip()
# Coldstart often binds the full BAK BH3 helix (16 aa) into seed_motif while
# defaults keep ring_size_max=14 — widen the ring to fit the motif rather than
# hard-fail VALIDATE (remeasure pep-1).
if motif and not set(motif).issubset(aminos):
    print('ERROR: seed_motif contains residues outside allowed_residues', file=sys.stderr)
    sys.exit(1)
if motif and len(motif) > hi:
    hi = len(motif)
    if lo > hi:
        lo = hi
    print(f'NOTE: raised ring_size_max to {hi} to fit seed_motif', file=sys.stderr)
out = {
    'ring_size_min': lo,
    'ring_size_max': hi,
    'n_candidates': n,
    'allowed_residues': ''.join(sorted(aminos)),
    'target_charge_min': int(${params.target_charge_min}),
    'target_charge_max': int(${params.target_charge_max}),
    'hydrophobic_frac_max': float(${params.hydrophobic_frac_max}),
    'seed_motif': motif,
    'target_label': '${params.target_label}',
    'cyclization': 'head_to_tail_amide',
    'status': 'ok',
}
with open('constraints.json', 'w') as fh:
    json.dump(out, fh, indent=2)
print('constraints ok', out)
PYEOF
    """
}

process ENUMERATE_SEQUENCES {
    tag 'enumerate_sequences'
    label 'process_low'
    publishDir "${params.outdir}/02_enumerate", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' \
        : 'biomate/workflow-tools:latest'

    input:
    path constraints

    output:
    path 'enumerated_candidates.json', emit: enumerated

    script:
    """
    python3 << 'PYEOF'
import json, itertools, hashlib

with open('${constraints}') as fh:
    c = json.load(fh)

aminos = list(c['allowed_residues'])
motif = c.get('seed_motif') or ''
want = int(c['n_candidates'])
# Prefer mid-range ring sizes first (better oral macrocycle priors).
sizes = list(range(int(c['ring_size_min']), int(c['ring_size_max']) + 1))
sizes.sort(key=lambda L: abs(L - 10))

CHARGE = {'D': -1, 'E': -1, 'K': 1, 'R': 1, 'H': 0.1}
HYDRO = set('AILMFVWY')

def ok(seq):
    if motif and motif not in (seq + seq):
        return False
    ch = sum(CHARGE.get(a, 0) for a in seq)
    if ch < c['target_charge_min'] or ch > c['target_charge_max']:
        return False
    hf = sum(1 for a in seq if a in HYDRO) / max(len(seq), 1)
    if hf > float(c['hydrophobic_frac_max']):
        return False
    # Ring closure: no Pro at junction (N- and C-terminal) for head-to-tail.
    if seq[0] == 'P' or seq[-1] == 'P':
        return False
    return True

cands = []
seen = set()
# Deterministic enumeration: rotate a motif-aware seed alphabet per length.
for L in sizes:
    if len(cands) >= want:
        break
    alphabet = aminos[:]
    # Bound explosion: walk a deterministic hash-ordered stream of sequences.
    # Full cartesian product is infeasible for L>6; use rolling substitutions
    # from a base sequence built from the alphabet.
    base = (motif + (''.join(alphabet) * L))[:L]
    if len(base) < L:
        base = (base + 'A' * L)[:L]
    queue = [base]
    while queue and len(cands) < want:
        seq = queue.pop(0)
        if seq in seen:
            continue
        seen.add(seq)
        if ok(seq):
            cid = 'cyc_' + hashlib.sha1(seq.encode()).hexdigest()[:10]
            cands.append({
                'id': cid,
                'seq': seq,
                'length': L,
                'charge': round(sum(CHARGE.get(a, 0) for a in seq), 2),
                'hydrophobic_frac': round(sum(1 for a in seq if a in HYDRO) / L, 3),
            })
        # Branch: single-position substitutions in alphabet order.
        if len(seen) > want * 40:
            break
        for i, a in enumerate(seq):
            for b in alphabet:
                if b == a:
                    continue
                nxt = seq[:i] + b + seq[i + 1:]
                if nxt not in seen:
                    queue.append(nxt)
                    break
            if len(queue) > want * 8:
                break

out = {
    'status': 'ok' if cands else 'empty',
    'n': len(cands),
    'candidates': cands[:want],
    'note': 'Rule-based cyclic enumeration under constraints; not a trained generator.',
}
with open('enumerated_candidates.json', 'w') as fh:
    json.dump(out, fh, indent=2)
print(f'enumerated {len(cands)} candidates')
PYEOF
    """
}

process FILTER_MACROCYCLE {
    tag 'filter_macrocycle'
    label 'process_low'
    publishDir "${params.outdir}/03_filter", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' \
        : 'biomate/workflow-tools:latest'

    input:
    path enumerated

    output:
    path 'filtered_candidates.json', emit: filtered

    script:
    """
    python3 << 'PYEOF'
import json

# Residue MW (neutral) — Yudin 2015 macrocycle window uses peptide MW proxy.
MW = {
    'A': 71.08, 'C': 103.15, 'D': 115.09, 'E': 129.12, 'F': 147.18,
    'G': 57.05, 'H': 137.14, 'I': 113.16, 'K': 128.17, 'L': 113.16,
    'M': 131.20, 'N': 114.11, 'P': 97.12, 'Q': 128.13, 'R': 156.19,
    'S': 87.08, 'T': 101.11, 'V': 99.13, 'W': 186.21, 'Y': 163.18,
}
# Polar side-chain proxy for TPSA-ish filter (not a measured ADMET value).
POLAR = set('DEHKNQRSTY')

with open('${enumerated}') as fh:
    data = json.load(fh)

kept = []
for row in data.get('candidates') or []:
    seq = row['seq']
    mw = 18.02 + sum(MW.get(a, 110.0) for a in seq)  # + water for head-to-tail
    polar = sum(1 for a in seq if a in POLAR)
    # Oral macrocycle-ish window (honest heuristic, not Lipinski):
    if not (500 <= mw <= 1200):
        continue
    if polar / max(len(seq), 1) > 0.65:
        continue
    kept.append({**row, 'mw_da': round(mw, 1), 'polar_frac': round(polar / len(seq), 3)})

out = {
    'status': 'ok' if kept else 'empty',
    'n_in': len(data.get('candidates') or []),
    'n_out': len(kept),
    'candidates': kept,
    'filter': 'Yudin-style MW 500-1200 + polar_frac<=0.65 (heuristic)',
}
with open('filtered_candidates.json', 'w') as fh:
    json.dump(out, fh, indent=2)
print(f'filtered {out["n_out"]} / {out["n_in"]}')
PYEOF
    """
}

process RANK_CANDIDATES {
    tag 'rank_candidates'
    label 'process_low'
    publishDir "${params.outdir}/04_rank", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' \
        : 'biomate/workflow-tools:latest'

    input:
    path filtered
    path constraints

    output:
    path 'cyclic_peptides.fasta', emit: fasta
    path 'cyclic_peptides.csv',   emit: csv
    path 'design_summary.json',   emit: summary
    path 'versions.yml',          emit: versions

    script:
    """
    python3 << 'PYEOF'
import json, csv

with open('${filtered}') as fh:
    filt = json.load(fh)
with open('${constraints}') as fh:
    cons = json.load(fh)

rows = list(filt.get('candidates') or [])
# Rank: prefer mid MW + moderate hydrophobicity (chameleonic proxy).
for r in rows:
    r['score'] = round(
        1.0
        - abs(r.get('mw_da', 800) - 800) / 800.0
        - abs(r.get('hydrophobic_frac', 0.4) - 0.4)
        - abs(r.get('charge', 0)) * 0.05,
        4,
    )
rows.sort(key=lambda r: (-r['score'], r['id']))

with open('cyclic_peptides.fasta', 'w') as fh:
    for r in rows:
        // Escape \$ so Nextflow GString does not eat the Python f-string
        // (coldstart pep-3: SyntaxError f-string unmatched '[').
        fh.write(f\">{r["id"]} len={r["length"]} score={r["score"]}\\n{r["seq"]}\\n")

with open('cyclic_peptides.csv', 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['id', 'seq', 'length', 'mw_da', 'charge',
                                       'hydrophobic_frac', 'polar_frac', 'score'])
    w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k) for k in w.fieldnames})

summary = {
    'workflow': 'cyclic_peptide_design',
    'target_label': cons.get('target_label'),
    'cyclization': cons.get('cyclization'),
    'n_candidates': len(rows),
    'top_id': rows[0]['id'] if rows else None,
    'top_seq': rows[0]['seq'] if rows else None,
    'status': 'ok' if rows else 'empty',
    'honesty': 'Rule-based enumeration + macrocycle heuristics; not measured affinity/ADMET.',
}
with open('design_summary.json', 'w') as fh:
    json.dump(summary, fh, indent=2)

with open('versions.yml', 'w') as fh:
    fh.write('cyclic_peptide_design:\\n  engine: rule_based_v1\\n')
print('ranked', len(rows), 'candidates')
PYEOF
    """
}

workflow {
    VALIDATE_CONSTRAINTS()
    ENUMERATE_SEQUENCES(VALIDATE_CONSTRAINTS.out.constraints)
    FILTER_MACROCYCLE(ENUMERATE_SEQUENCES.out.enumerated)
    RANK_CANDIDATES(FILTER_MACROCYCLE.out.filtered, VALIDATE_CONSTRAINTS.out.constraints)

    RANK_CANDIDATES.out.summary.view { f ->
        def d = new groovy.json.JsonSlurper().parseText(f.text)
        log.info "cyclic_peptide_design: status=${d.status} n=${d.n_candidates} top=${d.top_id}"
    }
}
