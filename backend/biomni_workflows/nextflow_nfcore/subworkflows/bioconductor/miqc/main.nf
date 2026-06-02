#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miQC
// Single-cell RNA-sequencing (scRNA-seq) has made it possible to profile gene expression in tissues at
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miQC/inst/doc/miQC.R
// Upstream  : SingleCellExperiment, flexmix, scRNAseq, scater, splines
// Downstream: none
//
// Install: BiocManager::install("miQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-miqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-miqc:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-miqc:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_miqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_miqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_miqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BuettnerESCData)
    library(SingleCellExperiment)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData
    ---------------------------------------------------------------------
    sce <- ZeiselBrainData()
    sce
    # --- Addpercellqc [] ---
    # Key functions: addPerCellQC, colData
    ---------------------------------------------------------------------
    sce <- addPerCellQC(sce, subsets = feature_ctrls)
    head(colData(sce))
    # --- Plotmetrics [] ---
    # Key functions: plotMetrics
    ---------------------------------------------------------------------
    plotMetrics(sce)
    # --- Mixturemodel [] ---
    # Key functions: mixtureModel
    ---------------------------------------------------------------------
    model <- mixtureModel(sce)
    # --- Parameters [] ---
    # Key functions: parameters, posterior
    ---------------------------------------------------------------------
    parameters(model)
    head(posterior(model))
    # --- Plotmodel [] ---
    # Key functions: plotModel
    ---------------------------------------------------------------------
    plotModel(sce, model)
    # --- Plotfiltering [] ---
    # Key functions: plotFiltering
    ---------------------------------------------------------------------
    plotFiltering(sce, model)
    # --- Filtercells [] ---
    # Key functions: filterCells
    ---------------------------------------------------------------------
    sce <- filterCells(sce, model)
    sce
    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData, addPerCellQC, mixtureModel, plotModel, plotFiltering
    ---------------------------------------------------------------------
    sce <- ZeiselBrainData()
    sce <- addPerCellQC(sce, subsets = feature_ctrls)
    model2 <- mixtureModel(sce, model_type = "spline")
    plotModel(sce, model2)
    # --- Mixturemodel [] ---
    # Key functions: mixtureModel, plotModel, plotFiltering, get1DCutoff
    ---------------------------------------------------------------------
    model4 <- mixtureModel(sce, model_type = "one_dimensional")
    plotModel(sce, model4)
    plotFiltering(sce, model4)
    get1DCutoff(sce, model4)
    # --- Plotfiltering [] ---
    # Key functions: plotFiltering
    ---------------------------------------------------------------------
    plotFiltering(sce, model4, posterior_cutoff = 0.9)
    # --- Data [] ---
    # Key functions: SingleCellExperiment, mixtureModel, plotFiltering
    ---------------------------------------------------------------------
    data("hgsoc_metrics")
    sce <- SingleCellExperiment(colData = metrics)
    model <- mixtureModel(sce)
    # --- Plotfiltering [] ---
    # Key functions: plotFiltering
    ---------------------------------------------------------------------
    plotFiltering(sce, model, posterior_cutoff = 0.6, enforce_left_cutoff = FALSE,
                    keep_all_below_boundary = TRUE)
    # --- Buettnerescdata [] ---
    # Key functions: BuettnerESCData, rowData, addPerCellQC, plotMetrics
    ---------------------------------------------------------------------
    sce <- BuettnerESCData()
    mt_genes <- grepl("^mt-", rowData(sce)$AssociatedGeneName)
    feature_ctrls <- list(mito = rownames(sce)[mt_genes])
    sce <- addPerCellQC(sce, subsets = feature_ctrls)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_miqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_miqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_miqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIQC:", paste0("    miqc: ", packageVersion("miQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_miqc_results.csv
    touch ${prefix}_miqc_output.rds
    echo "BIOC_MIQC:" > versions.yml
    echo "    miqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIQC(ch_input)

    emit:
    results  = BIOC_MIQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIQC.out.versions  // channel: path(versions.yml)
}
