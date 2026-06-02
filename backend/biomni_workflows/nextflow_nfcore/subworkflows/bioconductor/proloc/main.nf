#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pRoloc
// The pRoloc package implements machine learning and visualisation methods for the analysis and intero
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pRoloc/inst/doc/v01-pRoloc-tutorial.R
// Upstream  : BiocManager, MSnbase, class, knitr, pRolocGUI
// Downstream: bandle, pRolocGUI
//
// Install: BiocManager::install("pRoloc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROLOC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proloc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proloc:1.46.1--r44_0' :
        'quay.io/biocontainers/bioconductor-proloc:1.46.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proloc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proloc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proloc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pRoloc)
    library(jsonlite)

    # --- Normalisation and Preprocessing [] ---
    # Key functions: normalise
    data(tan2009r1, package = "pRolocdata")
    tan_norm <- normalise(tan2009r1, method = "sum")


    # --- Marker Profiling and Clustering [] ---
    # Key functions: mrkHClust, getMarkerClasses, mrkConsProfiles, plotConsProfiles
    data(tan2009r1, package = "pRolocdata")
    hc <- mrkHClust(tan2009r1, plot = FALSE)
    mm <- getMarkerClasses(tan2009r1)
    m_order <- levels(factor(mm))[order.dendrogram(hc)]
    fmat <- mrkConsProfiles(tan2009r1)
    plotConsProfiles(fmat, order = m_order)


    # --- Dimensionality Reduction and Visualisation [] ---
    # Key functions: plot2D, addLegend, FeaturesOfInterest, highlightOnPlot
    data(tan2009r1, package = "pRolocdata")
    plot2D(tan2009r1, fcol = "markers.orig")
    addLegend(tan2009r1, fcol = "markers.orig", where = "bottomright")
    foi1 <- FeaturesOfInterest(description = "Feats of interest 1",
                               fnames = featureNames(tan2009r1)[1:10])
    highlightOnPlot(tan2009r1, foi1, col = "black", lwd = 2)


    # --- Quality Control and Organelle Separation [] ---
    # Key functions: QSep, levelPlot
    data(hyperLOPIT2015, package = "pRolocdata")
    hlq <- QSep(hyperLOPIT2015)
    levelPlot(hlq)
    plot(hlq)


    # --- Unsupervised Clustering [] ---
    # Key functions: MLearn, kmeansI, hclustI, pamI
    data(tan2009r1, package = "pRolocdata")
    kcl <- MLearn(~ ., tan2009r1, kmeansI, centers = 5)
    plot(kcl, exprs(tan2009r1))
    hcl <- MLearn(~ ., tan2009r1, hclustI(distFun = dist,
                                          cutParm = list(k = 5)))
    plot(hcl, labels = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proloc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proloc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proloc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROLOC:", paste0("    proloc: ", packageVersion("pRoloc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proloc_results.csv
    touch ${prefix}_proloc_output.rds
    echo "BIOC_PROLOC:" > versions.yml
    echo "    proloc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROLOC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROLOC(ch_input)

    emit:
    results  = BIOC_PROLOC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROLOC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROLOC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROLOC.out.versions  // channel: path(versions.yml)
}
