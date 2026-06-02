#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellBarcode
// The package CellBarcode performs Cellular DNA Barcode analysis. It can handle all kinds of DNA barco
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellBarcode/inst/doc/UMI_VDJ_Barcode.R
// Upstream  : magrittr
// Downstream: none
//
// Install: BiocManager::install("CellBarcode")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLBARCODE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellbarcode"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellbarcode:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellbarcode:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellbarcode_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellbarcode_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellbarcode_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CellBarcode)
    library(jsonlite)

    # --- Barcode Extraction [] ---
    # Key functions: bc_extract, bc_meta
    pattern <- "([ACGA]{12})CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"
    bc_obj <- bc_extract(
        fq_filter,
        sample_name = basename(fq_filter),
        pattern = pattern,
        maxLDist = 0,
        pattern_type = c(UMI = 1, barcode = 2)
    )
    metadata_df <- bc_meta(bc_obj)


    # --- Barcode Curing and Filtering [] ---
    # Key functions: bc_cure_umi, bc_cure_depth, bc_cure_cluster
    bc_cured_umi <- bc_cure_umi(
        bc_obj,
        depth = 1,
        isUniqueUMI = TRUE,
        doFish = TRUE
    )
    bc_cured_depth <- bc_cure_depth(
        bc_cured_umi,
        depth = 3,
        isUpdate = TRUE
    )
    bc_clustered <- bc_cure_cluster(bc_cured_depth)


    # --- Export and Abundance Analysis [] ---
    # Key functions: bc_2df, bc_2matrix, bc_cleanBc
    barcode_df <- bc_2df(bc_clustered)
    barcode_matrix <- bc_2matrix(bc_clustered)
    clean_bc_list <- bc_cleanBc(bc_clustered, isList = FALSE)


    # --- Visualization [] ---
    # Key functions: bc_plot_single, bc_plot_seqQc
    bc_plot_seqQc(qc_filtered)
    bc_plot_single(
        bc_clustered,
        count_marks = 10,
        highlight = c("AAGTCCAGTACTATCGTACTA", "AAGTCCAGTACTGTAGCTACTA")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellbarcode_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellbarcode_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellbarcode_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLBARCODE:", paste0("    cellbarcode: ", packageVersion("CellBarcode"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellbarcode_results.csv
    touch ${prefix}_cellbarcode_output.rds
    echo "BIOC_CELLBARCODE:" > versions.yml
    echo "    cellbarcode: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLBARCODE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLBARCODE(ch_input)

    emit:
    results  = BIOC_CELLBARCODE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLBARCODE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLBARCODE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLBARCODE.out.versions  // channel: path(versions.yml)
}
