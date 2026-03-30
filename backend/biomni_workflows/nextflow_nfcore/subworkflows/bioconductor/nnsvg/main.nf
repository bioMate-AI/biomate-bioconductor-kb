#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nnSVG
// Method for scalable identification of spatially variable genes (SVGs) in spatially-resolved transcri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nnSVG/inst/doc/nnSVG.R
// Upstream  : STexampleData, SpatialExperiment, WeberDivechaLCdata, ggplot2, scran
// Downstream: none
//
// Install: BiocManager::install("nnSVG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NNSVG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nnsvg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nnsvg:1.10.3--r44_0' :
        'quay.io/biocontainers/bioconductor-nnsvg:1.10.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nnsvg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nnsvg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nnsvg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SlideSeqV2_mouseHPC)
    library(Visium_humanDLPFC)
    library(WeberDivechaLCdata_Visium)
    library(jsonlite)

    # --- Visium Humandlpfc [] ---
    # Key functions: Visium_humanDLPFC
    ---------------------------------------------------------------------
    # load example dataset from STexampleData package
    # see '?Visium_humanDLPFC' for more details
    spe <- Visium_humanDLPFC()
    dim(spe)
    # --- Coldata [] ---
    # Key functions: colData, filter_genes, logcounts, computeLibraryFactors, logNormCounts, assayNames
    ---------------------------------------------------------------------
    # preprocessing steps
    # keep only spots over tissue
    spe <- spe[, colData(spe)$in_tissue == 1]
    dim(spe)
    # --- Table [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    # number of significant SVGs
    table(rowData(spe)$padj <= 0.05)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    # show results for top n SVGs
    rowData(spe)[order(rowData(spe)$rank)[1:10], ]
    # --- Slideseqv2 Mousehpc [] ---
    # Key functions: SlideSeqV2_mouseHPC
    ---------------------------------------------------------------------
    # load example dataset from STexampleData package
    # see '?SlideSeqV2_mouseHPC' for more details
    spe <- SlideSeqV2_mouseHPC()
    dim(spe)
    # --- Na [] ---
    # Key functions: na, colData, filter_genes, computeLibraryFactors, logNormCounts, assayNames
    ---------------------------------------------------------------------
    # preprocessing steps
    # remove spots with NA cell type labels
    spe <- spe[, !is.na(colData(spe)$celltype)]
    dim(spe)
    # --- Matrix [] ---
    # Key functions: colData, nnSVG
    ---------------------------------------------------------------------
    # run nnSVG with covariates
    # create model matrix for cell type labels
    X <- model.matrix(~ colData(spe)$celltype)
    dim(X)
    # --- Matrix [] ---
    # Key functions: droplevels, factor, colData
    ---------------------------------------------------------------------
    # create model matrix after dropping empty factor levels
    X <- model.matrix(~ droplevels(as.factor(colData(spe)$celltype)))
    # --- Table [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    # number of significant SVGs
    table(rowData(spe)$padj <= 0.05)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    # show results for top n SVGs
    rowData(spe)[order(rowData(spe)$rank)[1:10], ]
    # --- Weberdivechalcdata Visium [] ---
    # Key functions: WeberDivechaLCdata_Visium, colData
    ---------------------------------------------------------------------
    # load example dataset from WeberDivechaLCdata package
    # see '?WeberDivechaLCdata_Visium' for more details
    spe <- WeberDivechaLCdata_Visium()
    dim(spe)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    # preprocessing steps
    # keep only spots over tissue
    spe <- spe[, colData(spe)$in_tissue == 1]
    dim(spe)
    # --- Rowsums [] ---
    # Key functions: rowSums, counts, colSums
    ---------------------------------------------------------------------
    # filter low-expressed genes
    # filter out genes with extremely low expression
    # using simple threshold on total UMI counts summed across all spots
    # approximate threshold of 10 UMI counts per sample
    # --- Levels [] ---
    # Key functions: levels, colData
    ---------------------------------------------------------------------
    # run nnSVG once per sample and store lists of top SVGs
    sample_ids <- levels(colData(spe)$sample_id)
    res_list <- as.list(rep(NA, length(sample_ids)))
    names(res_list) <- sample_ids
    # --- Filtering [] ---
    # Key functions: filtering
    ---------------------------------------------------------------------
    # combine results for multiple samples by averaging gene ranks
    # to generate an overall ranking
    # number of genes that passed filtering (and subsampling) for each sample
    sapply(res_list, nrow)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nnsvg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nnsvg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nnsvg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NNSVG:", paste0("    nnsvg: ", packageVersion("nnSVG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nnsvg_results.csv
    touch ${prefix}_nnsvg_output.rds
    echo "BIOC_NNSVG:" > versions.yml
    echo "    nnsvg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NNSVG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NNSVG(ch_input)

    emit:
    results  = BIOC_NNSVG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NNSVG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NNSVG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NNSVG.out.versions  // channel: path(versions.yml)
}
