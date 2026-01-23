#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_design_golden_gate_oligos
 * Design oligos for Golden Gate assembly by identifying backbone overhangs
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.backbone_sequence = null
params.insert_sequence = null
params.enzyme_name = null
params.is_circular = false

// Main process
process DESIGN_GOLDEN_GATE_OLIGOS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("design_golden_gate_oligos_results.json"), emit: results
    path("design_golden_gate_oligos_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import design_golden_gate_oligos

# Run the tool
try:
    result = design_golden_gate_oligos(
    backbone_sequence="${params.backbone_sequence}",
    insert_sequence="${params.insert_sequence}",
    enzyme_name="${params.enzyme_name}",
    is_circular=${params.is_circular ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("design_golden_gate_oligos_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("design_golden_gate_oligos_output.txt", "w") as f:
    f.write("Biomni: Design Golden Gate Oligos Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("design_golden_gate_oligos completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_DESIGN_GOLDEN_GATE_OLIGOS {
    take:
    // No file inputs

    main:
    DESIGN_GOLDEN_GATE_OLIGOS()

    emit:
    results = DESIGN_GOLDEN_GATE_OLIGOS.out.results
    output = DESIGN_GOLDEN_GATE_OLIGOS.out.output
}

// Entry workflow
workflow {
    if (!params.backbone_sequence) {
        error "Please provide --backbone_sequence parameter"
    }
    if (!params.insert_sequence) {
        error "Please provide --insert_sequence parameter"
    }
    if (!params.enzyme_name) {
        error "Please provide --enzyme_name parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_DESIGN_GOLDEN_GATE_OLIGOS()
}
