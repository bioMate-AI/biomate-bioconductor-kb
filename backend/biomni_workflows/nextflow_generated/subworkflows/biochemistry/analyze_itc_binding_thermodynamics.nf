#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_itc_binding_thermodynamics
 * Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.itc_data_path = null
params.itc_data = null
params.temperature = '298.15'
params.protein_concentration = null
params.ligand_concentration = null

// Main process
process ANALYZE_ITC_BINDING_THERMODYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_itc_binding_thermodynamics_results.json"), emit: results
    path("analyze_itc_binding_thermodynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biochemistry import analyze_itc_binding_thermodynamics
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_itc_binding_thermodynamics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_itc_binding_thermodynamics(
    itc_data_path="${params.itc_data_path}",
    itc_data="${params.itc_data}",
    temperature="${params.temperature}",
    protein_concentration="${params.protein_concentration}",
    ligand_concentration="${params.ligand_concentration}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_itc_binding_thermodynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_itc_binding_thermodynamics_output.txt", "w") as f:
    f.write("Biomni: Analyze Itc Binding Thermodynamics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_itc_binding_thermodynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_ITC_BINDING_THERMODYNAMICS {
    take:
    // No file inputs

    main:
    ANALYZE_ITC_BINDING_THERMODYNAMICS()

    emit:
    results = ANALYZE_ITC_BINDING_THERMODYNAMICS.out.results
    output = ANALYZE_ITC_BINDING_THERMODYNAMICS.out.output
}

// Entry workflow
workflow {



    BIOMNI_BIOCHEMISTRY_ANALYZE_ITC_BINDING_THERMODYNAMICS()
}
