#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_analyze_barcode_sequencing_data
 * Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file = null
params.barcode_pattern = null
params.flanking_seq_5prime = null
params.flanking_seq_3prime = null
params.min_count = '5'
params.output_dir = './results'

// Main process
process ANALYZE_BARCODE_SEQUENCING_DATA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_barcode_sequencing_data_results.json"), emit: results
    path("analyze_barcode_sequencing_data_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.synthetic_biology import analyze_barcode_sequencing_data

# Run the tool
try:
    result = analyze_barcode_sequencing_data(
    input_file="${params.input_file}",
    barcode_pattern="${params.barcode_pattern}",
    flanking_seq_5prime="${params.flanking_seq_5prime}",
    flanking_seq_3prime="${params.flanking_seq_3prime}",
    min_count="${params.min_count}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_barcode_sequencing_data_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_barcode_sequencing_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Barcode Sequencing Data Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_barcode_sequencing_data completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA {
    take:
    // No file inputs

    main:
    ANALYZE_BARCODE_SEQUENCING_DATA()

    emit:
    results = ANALYZE_BARCODE_SEQUENCING_DATA.out.results
    output = ANALYZE_BARCODE_SEQUENCING_DATA.out.output
}

// Entry workflow
workflow {
    if (!params.input_file) {
        error "Please provide --input_file parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BARCODE_SEQUENCING_DATA()
}
