#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASURAT
// ASURAT is a software for single-cell data analysis. Using ASURAT, one can simultaneously perform uns
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASURAT/inst/doc/ASURAT.R
// Upstream  : SingleCellExperiment, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("ASURAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASURAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-asurat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-asurat:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-asurat:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_asurat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_asurat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_asurat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PBMC)
    library(SingleCellExperiment)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Singlecellexperiment [] ---
    # Key functions: SingleCellExperiment, frame
    ---------------------------------------------------------------------
    pbmc <- SingleCellExperiment(assays = list(counts = pbmc_counts),
                                 rowData = data.frame(gene = rownames(pbmc_counts)),
                                 colData = data.frame(cell = colnames(pbmc_counts)))
    # --- Add Metadata [] ---
    # Key functions: add_metadata
    ---------------------------------------------------------------------
    pbmc <- add_metadata(sce = pbmc, mitochondria_symbol = "^MT-")
    # --- Remove Variables [] ---
    # Key functions: remove_variables
    ---------------------------------------------------------------------
    pbmc <- remove_variables(sce = pbmc, min_nsamples = 10)
    # --- Frame [] ---
    # Key functions: frame, colData, ggplot, geom_point, aes, labs, theme_classic
    ---------------------------------------------------------------------
    df <- data.frame(x = colData(pbmc)$nReads, y = colData(pbmc)$nGenes)
    ggplot2::ggplot() +
      ggplot2::geom_point(ggplot2::aes(x = df$x, y = df$y), size = 1, alpha = 1) +
      ggplot2::labs(x = "Number of reads", y = "Number of genes") +
    # --- Remove Samples [] ---
    # Key functions: remove_samples
    ---------------------------------------------------------------------
    pbmc <- remove_samples(sce = pbmc, min_nReads = 5000, max_nReads = 20000,
                           min_nGenes = 100, max_nGenes = 1e+10,
                           min_percMT = 0, max_percMT = 10)
    # --- Frame [] ---
    # Key functions: frame, rowData, ggplot, scale_y_log10, geom_point, aes
    ---------------------------------------------------------------------
    df <- data.frame(x = 1:nrow(rowData(pbmc)),
                     y = sort(rowData(pbmc)$nSamples, decreasing = TRUE))
    ggplot2::ggplot() + ggplot2::scale_y_log10() +
      ggplot2::geom_point(ggplot2::aes(x = df$x, y = df$y), size = 1, alpha = 1) +
    # --- Remove Variables Second [] ---
    # Key functions: remove_variables_second
    ---------------------------------------------------------------------
    pbmc <- remove_variables_second(sce = pbmc, min_meannReads = 0.05)
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    assay(pbmc, "logcounts") <- log(assay(pbmc, "counts") + 1)
    # --- Assay [] ---
    # Key functions: assay, sweep
    ---------------------------------------------------------------------
    mat <- assay(pbmc, "logcounts")
    assay(pbmc, "centered") <- sweep(mat, 1, apply(mat, 1, mean), FUN = "-")
    # --- Altexp [] ---
    # Key functions: altExp, SummarizedExperiment, assay
    ---------------------------------------------------------------------
    sname <- "logcounts"
    altExp(pbmc, sname) <- SummarizedExperiment(list(counts = assay(pbmc, sname)))
    # --- Load [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    urlpath <- "https://github.com/keita-iida/ASURATDB/blob/main/genes2bioterm/"
    load(url(paste0(urlpath, "20201213_human_CO.rda?raw=TRUE")))         # CO
    load(url(paste0(urlpath, "20220308_human_MSigDB.rda?raw=TRUE")))     # MSigDB
    load(url(paste0(urlpath, "20201213_human_GO_red.rda?raw=TRUE")))     # GO
    # --- List [] ---
    # Key functions: call
    ---------------------------------------------------------------------
    d <- list(human_CO[["cell"]], human_MSigDB[["cell"]])
    res <- do.call("rbind", d)
    human_CB <- list(cell = res)
    # --- List [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    pbmcs <- list(CB = pbmc, GO = pbmc, KG = pbmc)
    metadata(pbmcs$CB) <- list(sign = human_CB[["cell"]])
    metadata(pbmcs$GO) <- list(sign = human_GO[["BP"]])
    metadata(pbmcs$KG) <- list(sign = human_KEGG[["pathway"]])
    # --- Remove Signs [] ---
    # Key functions: remove_signs
    ---------------------------------------------------------------------
    pbmcs$CB <- remove_signs(sce = pbmcs$CB, min_ngenes = 2, max_ngenes = 1000)
    pbmcs$GO <- remove_signs(sce = pbmcs$GO, min_ngenes = 2, max_ngenes = 1000)
    pbmcs$KG <- remove_signs(sce = pbmcs$KG, min_ngenes = 2, max_ngenes = 1000)
    # --- Create Signs [] ---
    # Key functions: create_signs
    ---------------------------------------------------------------------
    pbmcs$CB <- create_signs(sce = pbmcs$CB, min_cnt_strg = 2, min_cnt_vari = 2)
    pbmcs$GO <- create_signs(sce = pbmcs$GO, min_cnt_strg = 4, min_cnt_vari = 4)
    pbmcs$KG <- create_signs(sce = pbmcs$KG, min_cnt_strg = 3, min_cnt_vari = 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_asurat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_asurat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_asurat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASURAT:", paste0("    asurat: ", packageVersion("ASURAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asurat_results.csv
    touch ${prefix}_asurat_output.rds
    echo "BIOC_ASURAT:" > versions.yml
    echo "    asurat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASURAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASURAT(ch_input)

    emit:
    results  = BIOC_ASURAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASURAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASURAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASURAT.out.versions  // channel: path(versions.yml)
}
