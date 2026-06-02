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
    library(CreateSeuratObject)
    library(DGEList)
    library(ExpressionSet)
    library(GeneSet)
    library(GeneSetCollection)
    library(MarkerBasedDecomposition)
    library(jsonlite)

    # --- LM markers [] ---
    # Key functions: get_lm_sig
    data("lm7", "lm22")
    LM <- get_lm_sig(lm7.pattern = "^NK", lm22.pattern = "NK cells")
    # --- MSigDB gene sets [] ---
    # Key functions: get_gsc_sig
    data("msigdb_gobp_nk")
    # --- set Names [] ---
    # Key functions: setNames, setName, gsc_plot
    gsn <- setNames(names(MSig), LETTERS[seq_along(MSig)])
    # --- merge MSigDB [] ---
    # Key functions: merge_markers, setName
    MSig <- merge_markers(MSig)
    setName(MSig) <- "MSigDB"
    # --- PanglaoDB markers [] ---
    # Key functions: list_panglao_organs, list_panglao_types, get_panglao_sig
    list_panglao_organs()
    list_panglao_types(organ = "Immune system")
    Panglao <- get_panglao_sig(type = "NK cells")
    # --- Gene Set [] ---
    # Key functions: GeneSet
    data("nk_markers")
    # --- integrate markers [] ---
    # Key functions: GeneSetCollection, merge_markers, gsc_plot
    gsc <- GeneSetCollection(c(nk_m, LM, MSig)) ## add Panglao if you run it
    Markers <- merge_markers(gsc)
    gsc_plot(gsc)
    # --- process_data [] ---
    # Key functions: process_data, attributes

    # --- select_sig [] ---
    # Key functions: select_sig
    set.seed(123)
    sig_ct <- select_sig(proc_data, feature_selection = "auto")
    head(sig_ct)
    # --- markers for cell type [] ---
    # Key functions: mapIds, geneIds, intersect

    # --- PCA on sig [] ---
    # Key functions: pca_matrix_plot, plot_annotation

    # --- bg data filtration [] ---
    # Key functions: rowSums
    keep <- rowSums(bg_mat > 1, na.rm = TRUE) > 2
    # --- remove bg in customized [] ---
    # Key functions: remove_bg_exp_mat

    # --- ccle construction [] ---
    # Key functions: pivot_longer

    # --- ccle to wide mat [] ---
    # Key functions: ccle_2_wide
    ccle <- ccle_2_wide(ccle = ccle)

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
