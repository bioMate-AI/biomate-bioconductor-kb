#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: airpart
// Airpart identifies sets of genes displaying differential cell-type-specific allelic imbalance across
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/airpart/inst/doc/airpart.R
// Upstream  : SingleCellExperiment
// Downstream: none
//
// Install: BiocManager::install("airpart")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AIRPART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-airpart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-airpart:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-airpart:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_airpart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_airpart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_airpart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(airpart)
    library(jsonlite)

    # --- Unique [] ---
    # Key functions: rowData, assays
    ---------------------------------------------------------------------
    unique(rowData(sce)) # the true underlying allelic ratios
    table(sce$x) # counts of each cell type
    assays(sce)[["a1"]][1:5, 1:5] # allelic counts for the effect allele
    # --- Assaynames [] ---
    # Key functions: assayNames
    ---------------------------------------------------------------------
    assayNames(sce)
    sce$x
    # --- Preprocess [] ---
    # Key functions: preprocess, makeHeatmap
    ---------------------------------------------------------------------
    sce <- preprocess(sce)
    makeHeatmap(sce)
    # --- Cellqc [] ---
    # Key functions: cellQC
    ---------------------------------------------------------------------
    cellQCmetrics <- cellQC(sce, mad_detected = 4)
    cellQCmetrics
    # --- Features [] ---
    # Key functions: features
    ---------------------------------------------------------------------
    keep_cell <- (
      cellQCmetrics$filter_sum | # sufficient features (genes)
        cellQCmetrics$filter_detected | # sufficient molecules counted
        # sufficient features expressed compared to spike genes,
    # --- Genecluster [] ---
    # Key functions: geneCluster, metadata
    ---------------------------------------------------------------------
    sce <- geneCluster(sce, G = 1:4)
    metadata(sce)$geneCluster
    # --- Summaryallelicratio [] ---
    # Key functions: summaryAllelicRatio
    ---------------------------------------------------------------------
    summary <- summaryAllelicRatio(sce)
    summary
    # --- Sapply [] ---
    # Key functions: diff
    ---------------------------------------------------------------------
    sapply(1:length(summary), function(i) {
      inst <- summary[[i]]
      inst_order <- inst[order(inst$weighted.mean), ]
      max(diff(inst_order$weighted.mean)) > 0.05
    # --- Estdisp [] ---
    # Key functions: estDisp
    ---------------------------------------------------------------------
    estDisp(sce, genecluster = 1)
    # --- Fusedlasso [] ---
    # Key functions: fusedLasso
    ---------------------------------------------------------------------
    sce_sub <- fusedLasso(sce,
      model = "binomial",
      genecluster = 1, ncores = 1,
      niter = 2
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(sce_sub)$lambda
    # --- Seq [] ---
    # Key functions: wilcoxExt, metadata
    ---------------------------------------------------------------------
    thrs <- 10^seq(from = -2, to = -0.4, by = 0.2)
    sce_sub_w <- wilcoxExt(sce, genecluster = 1, threshold = thrs)
    knitr::kable(metadata(sce_sub_w)$partition, row.names = FALSE)
    metadata(sce_sub_w)$threshold
    # --- Extractresult [] ---
    # Key functions: extractResult
    ---------------------------------------------------------------------
    s <- extractResult(sce_sub, "svalue")
    apply(s[genepoi,],2, function(s){s<0.005})
    # --- Mcols [] ---
    # Key functions: mcols
    ---------------------------------------------------------------------
    adj.p <- mcols(sce_sub)$adj.p.value
    adj.p < 0.05
    # --- Rep [] ---
    # Key functions: makeSimulatedData, preprocess, cellQC, features, featureQC, makeHeatmap
    ---------------------------------------------------------------------
    nct <- 8
    p.vec <- (rep(c(
      -3, 0, -3, 3,
      rep(0, nct / 2),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_airpart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_airpart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_airpart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AIRPART:", paste0("    airpart: ", packageVersion("airpart"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_airpart_results.csv
    touch ${prefix}_airpart_output.rds
    echo "BIOC_AIRPART:" > versions.yml
    echo "    airpart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AIRPART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AIRPART(ch_input)

    emit:
    results  = BIOC_AIRPART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AIRPART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AIRPART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AIRPART.out.versions  // channel: path(versions.yml)
}
