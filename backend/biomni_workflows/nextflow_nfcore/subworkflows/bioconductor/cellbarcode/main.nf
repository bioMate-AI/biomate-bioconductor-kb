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

    # --- str_split_fixed [] ---
    # Key functions: str_split_fixed
    example_data <- system.file("extdata", "mef_test_data", package = "CellBarcode")
    fq_files <- dir(example_data, "fastq.gz", full=TRUE)
    metadata <- stringr::str_split_fixed(basename(fq_files), "_", 10)[, c(4, 6)]
    # --- bc_extract [] ---
    # Key functions: bc_extract, bc_cure_umi, bc_2df
    install.packages("stringr")
    library(CellBarcode)
    library(magrittr)
    # --- quality control 1 [] ---
    # Key functions: bc_seq_qc, bc_names
    qc_noFilter <- bc_seq_qc(fq_files)
    bc_names(qc_noFilter)
    class(qc_noFilter)
    # --- qc figure set1 [] ---
    # Key functions: bc_plot_seqQc
    bc_plot_seqQc(qc_noFilter)
    # --- qc figure single1 [] ---
    # Key functions: bc_plot_seqQc
    class(qc_noFilter[1])
    bc_plot_seqQc(qc_noFilter[1])
    # --- filter low quality seq [] ---
    # Key functions: bc_seq_filter, bc_plot_seqQc

    # --- extract barcode no UMI [] ---
    # Key functions: bc_extract
    pattern <- "CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"
    bc_obj <- bc_extract(
    pattern_type = c(barcode = 1))
    # --- extract barcode with UMI [] ---
    # Key functions: bc_extract
    pattern <- "([ACGA]{12})CTCGAGGTCATCGAAGTATC([ACGT]+)CCGTAGCAAGCTCGAGAGTAGACCTACT"
    bc_obj_umi <- bc_extract(
    pattern_type = c(UMI = 1, barcode = 2))
    # --- correct barcodde with UMI [] ---
    # Key functions: bc_cure_umi

    # --- correct barcodde with count [] ---
    # Key functions: bc_cure_depth, bc_cure_umi
    bc_obj_umi_sub <- bc_cure_depth(bc_obj_umi_sub, depth = 3, isUpdate = FALSE)
    # --- correct barcodde clustering [] ---
    # Key functions: bc_cure_cluster
    bc_cure_cluster(bc_obj_umi_sub)
    # --- bc_2matrix [] ---
    # Key functions: bc_2matrix, bc_cure_depth, bc_2df
    bc_2matrix(bc_obj_umi_sub)
    data(bc_obj)
    Applying bc_cure_depth() to merge them.

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
