#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidysbml
// Starting from one SBML file, it extracts information from each listOfCompartments, listOfSpecies and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidysbml/inst/doc/tidysbml-introduction.R
// Upstream  : biomaRt, dplyr
// Downstream: none
//
// Install: BiocManager::install("tidysbml")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYSBML {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidysbml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidysbml:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidysbml:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidysbml_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidysbml_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidysbml_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidysbml)
    library(jsonlite)

    # --- sbml_as_list [] ---
    # Key functions: sbml_as_list, as_dfs, as_df
    if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
    BiocManager::install("tidysbml")
    # --- Query BioMart annotation [] ---
    # Key functions: useEnsembl, getBM
    library(biomaRt)
    mart <- useEnsembl(biomart = "ensembl", dataset = "hsapiens_gene_ensembl")
    df_mart_uniprot <- getBM( attributes = c("uniprot_gn_id", "uniprot_gn_symbol",   "description"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidysbml_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidysbml_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidysbml_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYSBML:", paste0("    tidysbml: ", packageVersion("tidysbml"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidysbml_results.csv
    touch ${prefix}_tidysbml_output.rds
    echo "BIOC_TIDYSBML:" > versions.yml
    echo "    tidysbml: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYSBML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYSBML(ch_input)

    emit:
    results  = BIOC_TIDYSBML.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYSBML.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYSBML.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYSBML.out.versions  // channel: path(versions.yml)
}
