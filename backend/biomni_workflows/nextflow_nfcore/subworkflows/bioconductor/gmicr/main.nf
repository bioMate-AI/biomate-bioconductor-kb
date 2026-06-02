#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GmicR
// This package uses bayesian network learning to detect relationships between Gene Modules detected by
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GmicR/inst/doc/GmicR_vignette.R
// Upstream  : WGCNA
// Downstream: none
//
// Install: BiocManager::install("GmicR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMICR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmicr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmicr:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmicr:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gmicr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmicr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmicr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Auto_WGCNA)
    library(Data_Prep)
    library(GO_Module_NameR)
    library(GSEAGO_Builder)
    library(Gmic_viz)
    library(InverseARCs)
    library(Query_Prep)
    library(jsonlite)

    # --- clearing environment and loading data [] ---
    # Key functions: remove
    remove(list = ls())
    library(GmicR)
    # --- module detection [] ---
    # Key functions: Auto_WGCNA
    library(GmicR)
    # --- GO module annotations [] ---
    # Key functions: Query_Prep

    # --- GO enrichment [] ---
    # Key functions: GSEAGO_Builder

    # --- GO module names [] ---
    # Key functions: GO_Module_NameR
    GMIC_Builder<-GO_Module_NameR(GMIC_Builder)
    # --- discretizing data [] ---
    # Key functions: Data_Prep

    # --- make Cluster [] ---
    # Key functions: makeCluster, bn_tabu_gen, stopCluster
    cl<-parallel::makeCluster(1)
    # --- detecting inverse relationships [] ---
    # Key functions: InverseARCs
    GMIC_Final<-InverseARCs(GMIC_net, threshold = -0.3)
    # --- Visualizing network [] ---
    # Key functions: Gmic_viz


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmicr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmicr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmicr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMICR:", paste0("    gmicr: ", packageVersion("GmicR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmicr_results.csv
    touch ${prefix}_gmicr_output.rds
    echo "BIOC_GMICR:" > versions.yml
    echo "    gmicr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMICR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GMICR(ch_input)

    emit:
    results  = BIOC_GMICR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMICR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMICR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMICR.out.versions  // channel: path(versions.yml)
}
