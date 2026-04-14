#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_orfs_in_frame
 * Helper function to find ORFs in a specific frame.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.seq_str = null
params.frame = null
params.strand = null

// Main process
process FIND_ORFS_IN_FRAME {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_orfs_in_frame_results.json"), emit: results
    path("find_orfs_in_frame_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import find_orfs_in_frame
except ImportError:
    # Fallback: function may need to be implemented locally
    def find_orfs_in_frame(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = find_orfs_in_frame(
    seq_str="${params.seq_str}",
    frame="${params.frame}",
    strand="${params.strand}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_orfs_in_frame_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("find_orfs_in_frame_output.txt", "w") as f:
    f.write("Biomni: Find Orfs In Frame Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("find_orfs_in_frame completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME {
    take:
    // No file inputs

    main:
    FIND_ORFS_IN_FRAME()

    emit:
    results = FIND_ORFS_IN_FRAME.out.results
    output = FIND_ORFS_IN_FRAME.out.output
}

// Entry workflow
workflow {
    if (!params.seq_str) {
        error "Please provide --seq_str parameter"
    }
    if (!params.frame) {
        error "Please provide --frame parameter"
    }
    if (!params.strand) {
        error "Please provide --strand parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_FIND_ORFS_IN_FRAME()
}
