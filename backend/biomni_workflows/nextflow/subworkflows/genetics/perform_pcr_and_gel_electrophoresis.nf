#!/usr/bin/env nextflow
/*
 * biomni_genetics_perform_pcr_and_gel_electrophoresis
 * Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.genomic_dna = null
params.forward_primer = null
params.reverse_primer = null
params.target_region = null
params.annealing_temp = '58'
params.extension_time = '30'
params.cycles = '35'
params.gel_percentage = '2.0'
params.output_prefix = 'pcr_result'

// Main process
process PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_pcr_and_gel_electrophoresis_results.json"), emit: results
    path("perform_pcr_and_gel_electrophoresis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import perform_pcr_and_gel_electrophoresis

# Run the tool
try:
    result = perform_pcr_and_gel_electrophoresis(
    genomic_dna="${params.genomic_dna}",
    forward_primer="${params.forward_primer}",
    reverse_primer="${params.reverse_primer}",
    target_region="${params.target_region}",
    annealing_temp="${params.annealing_temp}",
    extension_time="${params.extension_time}",
    cycles="${params.cycles}",
    gel_percentage="${params.gel_percentage}",
    output_prefix="${params.output_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_pcr_and_gel_electrophoresis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("perform_pcr_and_gel_electrophoresis_output.txt", "w") as f:
    f.write("Biomni: Perform Pcr And Gel Electrophoresis Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("perform_pcr_and_gel_electrophoresis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    take:
    // No file inputs

    main:
    PERFORM_PCR_AND_GEL_ELECTROPHORESIS()

    emit:
    results = PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.results
    output = PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.output
}

// Entry workflow
workflow {
    if (!params.genomic_dna) {
        error "Please provide --genomic_dna parameter"
    }


    BIOMNI_GENETICS_PERFORM_PCR_AND_GEL_ELECTROPHORESIS()
}
