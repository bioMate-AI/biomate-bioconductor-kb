#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCcompare
// HiCcompare provides functions for joint normalization and difference detection in multiple Hi-C data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCcompare/inst/doc/HiCcompare-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HiCcompare")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICCOMPARE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hiccompare"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hiccompare:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hiccompare:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hiccompare_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hiccompare_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hiccompare_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KRnorm)
    library(SCN)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    # create list of `hic.table` objects
    data("HMEC.chr10")
    data("NHEK.chr10")
    # create the `hic.table` object
    # --- Hic Compare [] ---
    # Key functions: hic_compare
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    hic.table <- hic_compare(hic.table, A.min = 15, adjust.dist = TRUE, p.method = 'fdr', Plot = TRUE)
    # --- Kable [] ---
    # Key functions: kable
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    knitr::kable(head(hic.table))
    # --- Make Interactionset [] ---
    # Key functions: make_InteractionSet
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    IntSet <- make_InteractionSet(hic.table)
    # --- Sim Matrix [] ---
    # Key functions: sim_matrix
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    sims <- sim_matrix(nrow = number_of_unitdistances, medianIF = 50000, sdIF = 14000, powerlaw.alpha = 1.8, fold.change = 4,
                       i.range = i.range, j.range = j.range)
    # --- sparse2full [] ---
    # Key functions: sparse2full, full2sparse
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    full.NHEK <- sparse2full(NHEK.chr22)
    full.NHEK[1:5, 1:5]
    sparse.NHEK <- full2sparse(full.NHEK)
    head(sparse.NHEK)
    # --- Krnorm [] ---
    # Key functions: KRnorm
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    KR.NHEK <- KRnorm(full.NHEK)
    # --- Scn [] ---
    # Key functions: SCN
    -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    SCN.NHEK <- SCN(full.NHEK)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hiccompare_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hiccompare_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hiccompare_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICCOMPARE:", paste0("    hiccompare: ", packageVersion("HiCcompare"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hiccompare_results.csv
    touch ${prefix}_hiccompare_output.rds
    echo "BIOC_HICCOMPARE:" > versions.yml
    echo "    hiccompare: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICCOMPARE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICCOMPARE(ch_input)

    emit:
    results  = BIOC_HICCOMPARE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICCOMPARE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICCOMPARE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICCOMPARE.out.versions  // channel: path(versions.yml)
}
