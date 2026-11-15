#!/usr/bin/env nextflow

/**
 * structural_biology/cyclic_peptide_cofold
 *
 * Boltz-2 cyclic-peptide / receptor co-folding, fanned out ONE PROCESS PER
 * PEPTIDE so AWS Batch runs every peptide fold in PARALLEL (the whole point of
 * putting this on BioMate's executor rather than a single GPU box loop).
 *
 * Per peptide the process writes a Boltz YAML input:
 *     version: 1
 *     sequences:
 *       - protein: { id: <chain>, sequence: <receptor chain 1> }
 *       - protein: { id: <chain>, sequence: <receptor chain 2> }   # optional (2-chain receptor)
 *       - protein: { id: P, sequence: <peptide>, cyclic: true }
 * then runs:
 *     boltz predict in.yaml --out_dir out --use_msa_server --no_kernels --override
 * and emits the predicted complex CIF + Boltz confidence JSON + a per-peptide
 * summary JSON (complex_iptm / iptm / confidence_score).
 *
 * Ground truth recipe: research/guangzhou_all_atom/build_candidates.py
 * (boltz_refold, ~L85-105) and refold_rerank_driver.sh. Session corrections
 * applied here: `--no_kernels` (cuequivariance ops kernel ImportErrors without
 * it) and `--use_msa_server` (single-seq folds error out without an MSA).
 *
 * Inputs (params):
 *   params.peptides         JSON list of {id, seq}, one fold per element → parallel
 *   params.receptor_chains  JSON map chain_id -> sequence (1 OR 2 receptor chains)
 *   params.target           label for the target (metadata only)
 *   params.outdir           output directory (default: 'results')
 *
 * Container: the Boltz-2 GPU image already used by boltz_structure_prediction.
 * It MUST contain boltz + cuequivariance-torch (refold_rerank_driver.sh installs
 * `boltz` + `cuequivariance-torch` into a py3.11 conda env with conda-forge
 * numpy/scipy). The current biomate/ai-tools/boltz image was built for
 * `boltz predict` and is the right base; if `--no_kernels` support or a newer
 * boltz is needed, a refreshed image must be built + pushed to ECR first.
 */

nextflow.enable.dsl = 2


// Demo defaults (overridden by BioMate's executor at launch).
params.peptides        = '[{"id": "pep1", "seq": "GCWGDRGPFDTCG"}]'
params.receptor_chains = '{"R": "MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH"}'
params.target          = 'demo_target'
params.outdir          = 'results'

process COFOLD {
    tag "${pep_id}"
    label 'process_gpu'
    publishDir { "${params.outdir}/cofold/${pep_id}" }, mode: 'copy'

    // Reuse the Boltz-2 GPU image from boltz_structure_prediction (must carry
    // boltz + cuequivariance-torch). ECR on AWS Batch; same repo/tag locally.
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest' : 'biomate/ai-tools/boltz:latest'

    input:
    tuple val(pep_id), val(pep_seq)

    output:
    tuple val(pep_id), path("out/**/*.cif"),                emit: structures, optional: true
    tuple val(pep_id), path("out/**/confidence_*.json"),    emit: confidence, optional: true
    tuple val(pep_id), path("${pep_id}_cofold.json"),       emit: summary
    path "versions.yml",                                    emit: versions

    script:
    """
    export PARAM_RECEPTOR_CHAINS='${params.receptor_chains}'
    export PEP_ID='${pep_id}'
    export PEP_SEQ='${pep_seq}'
    export TARGET='${params.target}'

    # 1) Build the Boltz YAML: one `- protein` per receptor chain (1 or 2) plus
    #    the cyclic peptide chain. ncAAs / D-residues / N-methylation cannot be
    #    expressed in Boltz's `sequence:` field → L-backbone approximation.
    python3 << 'PYEOF'
import os, json

rc = json.loads(os.environ.get("PARAM_RECEPTOR_CHAINS") or "{}")
pep_seq = os.environ["PEP_SEQ"].strip()
if not pep_seq:
    raise SystemExit("FATAL: empty peptide sequence")
if not rc:
    raise SystemExit("FATAL: no receptor_chains supplied (need 1 or 2 chains)")
if len(rc) > 2:
    raise SystemExit("FATAL: %d receptor chains supplied; only 1 or 2 supported" % len(rc))

lines = ["version: 1", "sequences:"]
used = set()
for cid, seq in rc.items():
    cid = str(cid).strip()
    seq = str(seq).strip()
    used.add(cid)
    lines.append("  - protein:")
    lines.append("      id: %s" % cid)
    lines.append("      sequence: %s" % seq)

# Peptide chain id: prefer 'P'; fall back to first free letter if a receptor
# chain already claimed 'P'.
pep_chain = "P"
if pep_chain in used:
    for c in "QRSTUVWXYZABCDEFGHIJKLMNO":
        if c not in used:
            pep_chain = c
            break
lines.append("  - protein:")
lines.append("      id: %s" % pep_chain)
lines.append("      sequence: %s" % pep_seq)
lines.append("      cyclic: true")

with open("in.yaml", "w") as f:
    f.write("\\n".join(lines) + "\\n")
print("=== Boltz YAML ===")
print(open("in.yaml").read())
PYEOF

    # 2) Fold. --no_kernels avoids the cuequivariance ops kernel ImportError;
    #    --use_msa_server because single-seq folds error without an MSA;
    #    --override to overwrite a stale out/ on retry.
    boltz predict in.yaml --out_dir out --use_msa_server --no_kernels --override

    # 3) Summarise: collect the complex CIF + Boltz confidence (complex_iptm /
    #    iptm / confidence_score). Never fabricate a score — null if absent.
    python3 << 'PYEOF'
import os, json, glob

pep_id = os.environ["PEP_ID"]
cifs = sorted(glob.glob("out/**/*.cif", recursive=True))
conf_files = sorted(glob.glob("out/**/confidence_*.json", recursive=True))

confidence = None
conf_source = None
for cj in conf_files:
    try:
        cd = json.load(open(cj))
    except Exception:
        continue
    for k in ("complex_iptm", "iptm", "confidence_score"):
        if cd.get(k) is not None:
            confidence = float(cd[k])
            conf_source = "%s:%s" % (os.path.basename(cj), k)
            break
    if confidence is not None:
        break

summary = {
    "peptide_id": pep_id,
    "target": os.environ.get("TARGET"),
    "tool": "Boltz-2",
    "cyclic": True,
    "n_structures": len(cifs),
    "structure_files": [os.path.basename(c) for c in cifs],
    "confidence": confidence,
    "confidence_source": conf_source,
    "status": "ok" if cifs else "no_structure",
    "note": "cyclic via Boltz `cyclic: true`; ncAA/D-Pro/N-methyl folded as "
            "L-backbone approximation (not expressible in Boltz sequence:)",
}
with open("%s_cofold.json" % pep_id, "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltz: \$(python3 -c "import boltz; print(getattr(boltz,'__version__','unknown'))" 2>/dev/null || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
END_VERSIONS
    """
}

workflow CYCLIC_PEPTIDE_COFOLD {
    take:
    ch_peptides   // channel: tuple(pep_id, pep_seq) — ONE element per peptide → parallel folds

    main:
    COFOLD(ch_peptides)

    emit:
    structures = COFOLD.out.structures
    confidence = COFOLD.out.confidence
    summary    = COFOLD.out.summary
    versions   = COFOLD.out.versions
}

// Entry workflow for standalone execution.
workflow {
    // Parse params.peptides (JSON list of {id, seq}) and FAN OUT: Channel.fromList
    // makes each peptide its own channel emission → its own COFOLD task → AWS
    // Batch schedules them in parallel. This is the parallelism the module exists for.
    def peptides = params.peptides instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.peptides)
        : params.peptides

    ch_peptides = Channel
        .fromList(peptides)
        .map { p -> tuple(p.id as String, p.seq as String) }

    CYCLIC_PEPTIDE_COFOLD(ch_peptides)

    CYCLIC_PEPTIDE_COFOLD.out.summary.view { pid, f -> "cofold done: ${pid}" }
}
