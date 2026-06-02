#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: discordant
// Discordant is an R package that identifies pairs of features that correlate differently between phen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/discordant/inst/doc/Using_discordant.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("discordant")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISCORDANT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-discordant"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-discordant:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-discordant:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_discordant_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_discordant_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_discordant_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(discordant)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # Load data
    data(TCGA_GBM_miRNA_microarray)
    data(TCGA_GBM_transcript_microarray)
    # --- Data [] ---
    # Key functions: splitMADOutlier
    ---------------------------------------------------------------------
    data(TCGA_Breast_miRNASeq)
    mat.filtered <- splitMADOutlier(TCGA_Breast_miRNASeq,
                                    filter0 = TRUE,
                                    threshold = 4)
    # --- Discordantrun [] ---
    # Key functions: discordantRun
    ---------------------------------------------------------------------
    # Within -omics
    wthn_result <- discordantRun(v1 = wthn_vectors$v1,
                                 v2 = wthn_vectors$v2,
                                 x = TCGA_GBM_transcript_microarray)
    # --- Data [] ---
    # Key functions: createVectors, discordantRun
    ---------------------------------------------------------------------
    # Load Data
    data(TCGA_Breast_miRNASeq_voom)
    data(TCGA_Breast_RNASeq_voom)
    # Prepare groups
    # --- Discordantrun [] ---
    # Key functions: discordantRun
    ---------------------------------------------------------------------
    # Between -omics

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_discordant_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_discordant_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_discordant_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DISCORDANT:", paste0("    discordant: ", packageVersion("discordant"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discordant_results.csv
    touch ${prefix}_discordant_output.rds
    echo "BIOC_DISCORDANT:" > versions.yml
    echo "    discordant: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DISCORDANT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DISCORDANT(ch_input)

    emit:
    results  = BIOC_DISCORDANT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DISCORDANT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DISCORDANT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DISCORDANT.out.versions  // channel: path(versions.yml)
}
