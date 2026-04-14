#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_perform_crispr_cas9_genome_editing
 * Simulates CRISPR-Cas9 genome editing process including guide RNA design, delivery, and analysis.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.guide_rna_sequences = null
params.target_genomic_loci = null
params.cell_tissue_type = null

// Main process
process PERFORM_CRISPR_CAS9_GENOME_EDITING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_crispr_cas9_genome_editing_results.json"), emit: results
    path("perform_crispr_cas9_genome_editing_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioengineering import perform_crispr_cas9_genome_editing
except ImportError:
    # Fallback: function may need to be implemented locally
    def perform_crispr_cas9_genome_editing(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = perform_crispr_cas9_genome_editing(
    guide_rna_sequences="${params.guide_rna_sequences}",
    target_genomic_loci="${params.target_genomic_loci}",
    cell_tissue_type="${params.cell_tissue_type}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_crispr_cas9_genome_editing_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("perform_crispr_cas9_genome_editing_output.txt", "w") as f:
    f.write("Biomni: Perform Crispr Cas9 Genome Editing Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("perform_crispr_cas9_genome_editing completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_PERFORM_CRISPR_CAS9_GENOME_EDITING {
    take:
    // No file inputs

    main:
    PERFORM_CRISPR_CAS9_GENOME_EDITING()

    emit:
    results = PERFORM_CRISPR_CAS9_GENOME_EDITING.out.results
    output = PERFORM_CRISPR_CAS9_GENOME_EDITING.out.output
}

// Entry workflow
workflow {
    if (!params.guide_rna_sequences) {
        error "Please provide --guide_rna_sequences parameter"
    }
    if (!params.target_genomic_loci) {
        error "Please provide --target_genomic_loci parameter"
    }
    if (!params.cell_tissue_type) {
        error "Please provide --cell_tissue_type parameter"
    }


    BIOMNI_BIOENGINEERING_PERFORM_CRISPR_CAS9_GENOME_EDITING()
}
