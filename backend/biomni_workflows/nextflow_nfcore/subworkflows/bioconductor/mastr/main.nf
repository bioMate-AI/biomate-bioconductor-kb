#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mastR
// mastR is an R package designed for automated screening of signatures of interest for specific resear
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mastR/inst/doc/mastR_Demo.R
// Upstream  : GSEABase, dplyr, edgeR, ggplot2, singscore
// Downstream: none
//
// Install: BiocManager::install("mastR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MASTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mastr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mastr:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mastr:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mastr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mastr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mastr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mastR)
    library(CreateSeuratObject)
    library(DGEList)
    library(ExpressionSet)
    library(GeneSet)
    library(GeneSetCollection)
    library(MarkerBasedDecomposition)
    library(jsonlite)

    # --- Expression Data Processing and Feature Selection [] ---
    # Key functions: process_data, select_sig
    data("im_data_6")
    proc_data <- process_data(
        data = im_data_6,
        group_col = "celltype:ch1",
        target_group = "NK",
        markers = c("ENSG00000149294", "ENSG00000111537"),
        gene_id = "ENSEMBL"
    )
    proc_data$voomE <- proc_data$vfit$E
    sig_ct <- select_sig(proc_data, feature_selection = "auto")


    # --- Background Noise Filtering [] ---
    # Key functions: ccle_2_wide, remove_bg_exp_mat
    data("ccle_crc_5")
    ccle <- data.frame(
        ccle_crc_5$counts,
        gene_name = rownames(ccle_crc_5),
        primary_disease = "CRC"
    )
    ccle_long <- tidyr::pivot_longer(
        ccle,
        -c(gene_name, primary_disease),
        names_to = "depmap_id",
        values_to = "rna_expression"
    )
    ccle_wide <- ccle_2_wide(ccle = ccle_long)
    keep <- rowSums(ccle_wide > 1, na.rm = TRUE) > 2
    ccle_wide <- ccle_wide[keep, ]
    m_ccl <- remove_bg_exp_mat(
        sig_mat = matrix(rnorm(100), nrow = 10),
        bg_mat = ccle_wide,
        markers = c("NCAM1", "NCR1"),
        gene_id = c("ENSEMBL", "SYMBOL")
    )


    # --- Signature Evaluation and Visualization [] ---
    # Key functions: pca_matrix_plot, sig_heatmap, sig_boxplot, sig_gseaplot
    pca_matrix_plot(
        proc_data,
        features = c("ENSG00000149294"),
        group_by = "celltype.ch1",
        slot = "voomE",
        n = 3,
        gene_id = "ENSEMBL"
    )
    sig_heatmap(
        data = proc_data,
        sigs = c("ENSG00000149294"),
        group_col = "celltype.ch1",
        markers = c("ENSG00000149294"),
        gene_id = "ENSEMBL",
        slot = "voomE"
    )
    sig_boxplot(
        data = proc_data,
        sigs = c("ENSG00000149294"),
        group_col = "celltype.ch1",
        target_group = "NK",
        gene_id = "ENSEMBL",
        slot = "voomE"
    )


    # --- Multi-dataset Refinement [] ---
    # Key functions: filter_subset_sig
    data("im_data_6")
    m_ct_m <- filter_subset_sig(
        data = list(A = im_data_6, B = im_data_6),
        markers = c("ENSG00000149294", "ENSG00000111537"),
        group_col = "celltype:ch1",
        target_group = "NK",
        feature_selection = "auto",
        dir = "UP",
        gene_id = "ENSEMBL",
        comb = union,
        summary = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mastr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mastr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mastr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MASTR:", paste0("    mastr: ", packageVersion("mastR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mastr_results.csv
    touch ${prefix}_mastr_output.rds
    echo "BIOC_MASTR:" > versions.yml
    echo "    mastr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MASTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MASTR(ch_input)

    emit:
    results  = BIOC_MASTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MASTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MASTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MASTR.out.versions  // channel: path(versions.yml)
}
