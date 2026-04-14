#!/usr/bin/env nextflow
/*
 * biomni_database_region_to_ccre_screen
 * Given starting and ending coordinates, this function retrieves information of intersecting cCREs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.coord_chrom = null
params.coord_start = 0
params.coord_end = 0
params.assembly = 'GRCh38'

// Main process
process REGION_TO_CCRE_SCREEN {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("region_to_ccre_screen_results.json"), emit: results
    path("region_to_ccre_screen_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.database import region_to_ccre_screen

# Run the tool
try:
    result = region_to_ccre_screen(
    coord_chrom="${params.coord_chrom}",
    coord_start=${params.coord_start},
    coord_end=${params.coord_end},
    assembly="${params.assembly}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("region_to_ccre_screen_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("region_to_ccre_screen_output.txt", "w") as f:
    f.write("Biomni: Region To Ccre Screen Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("region_to_ccre_screen completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_DATABASE_REGION_TO_CCRE_SCREEN {
    take:
    // No file inputs

    main:
    REGION_TO_CCRE_SCREEN()

    emit:
    results = REGION_TO_CCRE_SCREEN.out.results
    output = REGION_TO_CCRE_SCREEN.out.output
}

// Entry workflow
workflow {
    if (!params.coord_chrom) {
        error "Please provide --coord_chrom parameter"
    }


    BIOMNI_DATABASE_REGION_TO_CCRE_SCREEN()
}
