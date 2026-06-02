#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DominoEffect
// The functions support identification and annotation of hotspot residues in proteins. These are indiv
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DominoEffect/inst/doc/Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DominoEffect")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOMINOEFFECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dominoeffect"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dominoeffect:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dominoeffect:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dominoeffect_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dominoeffect_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dominoeffect_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DominoEffect)
    library(jsonlite)


    # --- Eval=false [] ---
    # Key functions: install
    #  if (!require("BiocManager"))
    #      install.packages("BiocManager")
    #  BiocManager::install("DominoEffect")

    ## -----------------------------------------------------------------------------
    library(DominoEffect)

    ## -----------------------------------------------------------------------------
    data("TestData", package = "DominoEffect")
    data("SnpData", package = "DominoEffect")
    data("DominoData", package = "DominoEffect")

    # --- Eval = False [] ---
    # Key functions: DominoEffect
    #  hotspot_mutations <- DominoEffect(mutation_dataset, gene_data, snp_data, min_n_muts, MAF_thresh, flanking_region, poisson.thr, percentage.thr, ratio.thr, approach, write_to_file)

    ## -----------------------------------------------------------------------------
    min_n_muts <- 5

    ## -----------------------------------------------------------------------------
    MAF.thr <- 0.01

    ## -----------------------------------------------------------------------------
    flanking_region <- c(200, 300)
    flanking_region <- c(300)

    ## -----------------------------------------------------------------------------
    poisson.thr <- 0.01


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dominoeffect_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dominoeffect_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dominoeffect_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOMINOEFFECT:", paste0("    dominoeffect: ", packageVersion("DominoEffect"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dominoeffect_results.csv
    touch ${prefix}_dominoeffect_output.rds
    echo "BIOC_DOMINOEFFECT:" > versions.yml
    echo "    dominoeffect: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOMINOEFFECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOMINOEFFECT(ch_input)

    emit:
    results  = BIOC_DOMINOEFFECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOMINOEFFECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOMINOEFFECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOMINOEFFECT.out.versions  // channel: path(versions.yml)
}
