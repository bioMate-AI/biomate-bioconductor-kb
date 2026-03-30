#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: standR
// standR is an user-friendly R package providing functions to assist conducting good-practice analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/standR/inst/doc/Quick_start.R
// Upstream  : ExperimentHub, SpatialExperiment, ggalluvial, limma
// Downstream: none
//
// Install: BiocManager::install("standR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STANDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-standr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-standr:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-standr:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_standr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_standr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_standr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(standR)
    library(jsonlite)

    # --- Coldata [] ---
    # Key functions: colData, plotSampleInfo
    ---------------------------------------------------------------------
    colData(spe)$regions <- paste0(colData(spe)$region,"_",colData(spe)$SegmentLabel) |>
      (\(.) gsub("_Geometric Segment","",.))() |>
      paste0("_",colData(spe)$pathology) |>
      (\(.) gsub("_NA","_ns",.))()
    # --- Addperroiqc [] ---
    # Key functions: addPerROIQC
    ---------------------------------------------------------------------
    spe <- addPerROIQC(spe, rm_genes = TRUE)
    # --- Plotgeneqc [] ---
    # Key functions: plotGeneQC
    ---------------------------------------------------------------------
    plotGeneQC(spe, ordannots = "regions", col = regions, point_size = 2)
    # --- Plotroiqc [] ---
    # Key functions: plotROIQC
    ---------------------------------------------------------------------
    plotROIQC(spe, y_threshold = 50000, col = SlideName)
    # --- Rownames [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    spe <- spe[,rownames(colData(spe))[colData(spe)$lib_size > 50000]]
    # --- Plotrlexpr [] ---
    # Key functions: plotRLExpr
    ---------------------------------------------------------------------
    plotRLExpr(spe, ordannots = "SlideName", assay = 2, col = SlideName)
    # --- Drawpca [] ---
    # Key functions: drawPCA
    ---------------------------------------------------------------------
    drawPCA(spe, assay = 2, col = SlideName, shape = regions)
    # --- Coldata [] ---
    # Key functions: colData, geomxNorm
    ---------------------------------------------------------------------
    colData(spe)$biology <- paste0(colData(spe)$disease_status, "_", colData(spe)$regions)
    spe_tmm <- geomxNorm(spe, method = "TMM")
    # --- Findncgs [] ---
    # Key functions: findNCGs, metadata
    ---------------------------------------------------------------------
    spe <- findNCGs(spe, batch_name = "SlideName", top_n = 500)
    metadata(spe) |> names()
    # --- Geomxbatchcorrection [] ---
    # Key functions: geomxBatchCorrection, metadata
    ---------------------------------------------------------------------
    spe_ruv <- geomxBatchCorrection(spe, factors = "biology",
                       NCGs = metadata(spe)$NCGs, k = 5)
    # --- Plotpairpca [] ---
    # Key functions: plotPairPCA
    ---------------------------------------------------------------------
    plotPairPCA(spe_ruv, assay = 2, color = disease_status, shape = regions, title = "RUV4")
    # --- Plotrlexpr [] ---
    # Key functions: plotRLExpr, ggtitle
    ---------------------------------------------------------------------
    plotRLExpr(spe_ruv, assay = 2, color = SlideName) + ggtitle("RUV4")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_standr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_standr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_standr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STANDR:", paste0("    standr: ", packageVersion("standR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standr_results.csv
    touch ${prefix}_standr_output.rds
    echo "BIOC_STANDR:" > versions.yml
    echo "    standr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STANDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STANDR(ch_input)

    emit:
    results  = BIOC_STANDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STANDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STANDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STANDR.out.versions  // channel: path(versions.yml)
}
