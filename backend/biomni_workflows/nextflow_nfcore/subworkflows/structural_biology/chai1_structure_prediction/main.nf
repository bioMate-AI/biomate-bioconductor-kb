#!/usr/bin/env nextflow

/**
 * chai1_structure_prediction
 *
 * Multi-modal biomolecular structure prediction using Chai-1.
 * Handles proteins, small molecules, DNA, RNA, glycosylations, and multi-chain
 * complexes in a single forward pass. Apache 2.0 licensed.
 *
 * Inputs (provide one):
 *   params.input_fasta   -- path to a FASTA file (use Chai-1 headers for multi-chain:
 *                           >protein|name=A, >ligand|name=LIG|smiles=CCO, >rna|name=R)
 *   params.sequence      -- raw amino-acid sequence string; the workflow writes a
 *                           FASTA file automatically (single-chain protein assumed)
 *
 * Other params:
 *   params.num_trunk_recycles        -- trunk recycling steps (default: 3)
 *   params.num_diffusion_timesteps   -- diffusion steps (default: 200)
 *   params.seed                      -- random seed (default: 42)
 *   params.outdir                    -- output directory
 */

nextflow.enable.dsl = 2

params.input_fasta               = ''
params.sequence                  = ''  // raw AA/NT sequence — alternative to input_fasta
params.num_trunk_recycles        = 3
params.num_diffusion_timesteps   = 200
params.seed                      = 42
params.outdir                    = 'results'
params.publish_dir_mode          = 'copy'

def ECR = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest'

// -- Chai-1 structure prediction -----------------------------------------------
// Handles both input modes inside the process script so no intermediate channel
// or local temp file is needed (collectFile breaks with S3 work directories).

process CHAI1_PREDICT {
    tag "chai1"
    label 'process_gpu'
    publishDir "${params.outdir}/structures", mode: params.publish_dir_mode

    container ECR

    output:
    path("chai_output/"), emit: results_dir
    path("chai_output/*.cif"), emit: structures, optional: true
    path("chai_output/scores.json"), emit: scores, optional: true

    script:
    // Guard against Groovy coercing missing/boolean params to the string "true"/"false"
    def raw_fasta  = params.input_fasta?.toString()?.trim() ?: ''
    def fasta_path = (raw_fasta && raw_fasta != 'true' && raw_fasta != 'false' && !raw_fasta.startsWith('null')) ? raw_fasta : ''
    def seq        = params.sequence?.toString()?.trim()    ?: ''
    def clean_seq  = (seq && seq != 'true' && seq != 'false') ? seq : ''
    if (!fasta_path && !clean_seq) error "Provide params.input_fasta (FASTA file path) or params.sequence (raw AA/NT sequence)"
    def use_fasta  = fasta_path ? 'True' : 'False'
    """
    python3 - <<'PYEOF'
import json, sys
from pathlib import Path

try:
    from chai_lab.chai1 import run_inference
except ImportError as e:
    print(f"[chai1] Import error: {e}", file=sys.stderr)
    sys.exit(1)

# Resolve FASTA input (values below are substituted by Groovy before bash runs this)
use_provided_fasta = ${use_fasta}
fasta_path_str = "${fasta_path}"

if use_provided_fasta and fasta_path_str and Path(fasta_path_str).exists():
    fasta_file = Path(fasta_path_str)
else:
    fasta_file = Path("input_sequence.fasta")
    seq_str = "${clean_seq}"
    if not seq_str:
        print("[chai1] ERROR: no valid fasta_path or sequence provided", file=sys.stderr)
        sys.exit(1)
    fasta_file.write_text(">protein|name=query\\n" + seq_str + "\\n")

output_dir = Path("chai_output")
output_dir.mkdir(parents=True, exist_ok=True)

candidates = run_inference(
    fasta_file=fasta_file,
    output_dir=output_dir,
    num_trunk_recycles=${params.num_trunk_recycles},
    num_diffn_timesteps=${params.num_diffusion_timesteps},
    seed=${params.seed},
    device="cuda",
    use_esm_embeddings=True,
)

print(f"[chai1] Predicted {len(candidates)} candidate(s)")

def to_float(v):
    return float(v.item() if hasattr(v, 'item') else v)

scores = [{"aggregate_score": to_float(c.aggregate_score)} for c in candidates]
with open(output_dir / "scores.json", "w") as fh:
    json.dump(scores, fh, indent=2)
if candidates:
    print(f"[chai1] Best aggregate_score: {to_float(candidates[0].aggregate_score):.4f}")
PYEOF
    """
}

// -- Summarise -----------------------------------------------------------------

process SUMMARISE_RESULTS {
    tag "summary"
    label 'process_low'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    container ECR

    input:
    path(results_dir)

    output:
    path("chai1_summary.json"), emit: summary

    script:
    """
    python3 - <<'EOF'
import json, glob, os

structures = glob.glob("${results_dir}/*.cif")
scores = {}
score_file = "${results_dir}/scores.json"
if os.path.exists(score_file):
    with open(score_file) as f:
        scores = json.load(f)

summary = {
    "tool": "Chai-1",
    "structures_predicted": len(structures),
    "structure_files": [os.path.basename(s) for s in structures],
    "scores": scores,
}
with open("chai1_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
EOF
    """
}

workflow {
    CHAI1_PREDICT()
    SUMMARISE_RESULTS(CHAI1_PREDICT.out.results_dir)
}
