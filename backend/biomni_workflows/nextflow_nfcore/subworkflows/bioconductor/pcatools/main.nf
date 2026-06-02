#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PCAtools
// Principal Component Analysis (PCA) is a very powerful technique that has wide applicability in data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PCAtools/inst/doc/PCAtools.R
// Upstream  : Biobase, DESeq2, GEOquery, airway, cowplot
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("PCAtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCATOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcatools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcatools:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcatools:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pcatools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcatools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcatools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCAtools)
    library(jsonlite)


    # --- Vroom Connection Size [] ---
    # Key functions: Sys.setenv, screeplot, biplot
    Sys.setenv(VROOM_CONNECTION_SIZE='512000')
    screeplot(p, axisLabSize = 18, titleLabSize = 22)
    biplot(p, showLoadings = TRUE,
        labSize = 5, pointSize = 5, sizeLoadingsNames = 5)

    # --- Ex3b [] ---
    # Key functions: biplot, pairsplot, plotloadings
    biplot(p, showLoadings = TRUE, lab = NULL)
    pairsplot(p)
    plotloadings(p, labSize = 3)

    # --- Ex6 [] ---
    # Key functions: eigencorplot, parallelPCA, findElbowPoint, screeplot, getComponents, geom_label, cumsum
    eigencorplot(p,
        metavars = c('Study','Age','Distant.RFS','ER',
          'GGI','Grade','Size','Time.RFS'))


    ## -----------------------------------------------------------------------------

      p$rotated[1:5,1:5]

      p$loadings[1:5,1:5]
    horn <- parallelPCA(mat)
      horn$n


    ## -----------------------------------------------------------------------------

      elbow <- findElbowPoint(p$variance)
      elbow
    library(ggplot2)


    # --- Ex8 [] ---
    # Key functions: biplot
    biplot(p,
        lab = paste0(p$metadata$Age, ' años'),
        colby = 'ER',
        hline = 0, vline = 0,
        legendPosition = 'right')
    biplot(p,
        colby = 'ER', colkey = c('ER+' = 'forestgreen', 'ER-' = 'purple'),
        colLegendTitle = 'ER-\nstatus',
        # encircle config
          encircle = TRUE,
          encircleFill = TRUE,
        hline = 0, vline = c(-25, 0, 25),
        legendPosition = 'top', legendLabSize = 16, legendIconSize = 8.0)

      biplot(p,
    biplot(p,
        colby = 'ER', colkey = c('ER+' = 'forestgreen', 'ER-' = 'purple'),
        # ellipse config
          ellipse = TRUE,
          ellipseType = 't',

    # --- Ex12a [] ---
    # Key functions: biplot, scale_colour_gradient
    biplot(p,
        lab = NULL,
        colby = 'ER', colkey = c('ER+'='royalblue', 'ER-'='red3'),
        hline = c(-25, 0, 25), vline = c(-25, 0, 25),
        vlineType = c('dotdash', 'solid', 'dashed'),
        gridlines.major = FALSE, gridlines.minor = FALSE,
        pointSize = 5,
        legendPosition = 'left', legendLabSize = 14, legendIconSize = 8.0,
        shape = 'Grade', shapekey = c('Grade 1'=15, 'Grade 2'=17, 'Grade 3'=8),
        drawConnectors = FALSE,
    biplot(p,
        # loadings parameters
          showLoadings = TRUE,
          lengthLoadingsArrowsFactor = 1.5,
          sizeLoadingsNames = 4,
          colLoadingsNames = 'red4',
        # other parameters
          lab = NULL,
          colby = 'ER', colkey = c('ER+'='royalblue', 'ER-'='red3'),
          hline = 0, vline = c(-25, 0, 25),

    # --- Ex14 [] ---
    # Key functions: pairsplot, getComponents, unit, plotloadings
    pairsplot(p,
        components = getComponents(p, c(1:10)),
        triangle = TRUE, trianglelabSize = 12,
        hline = 0, vline = 0,
        pointSize = 0.4,
        gridlines.major = FALSE, gridlines.minor = FALSE,
        colby = 'Grade',
        title = 'Pairs plot', plotaxes = FALSE,
        margingaps = unit(c(-0.01, -0.01, -0.01, -0.01), 'cm'))
    pairsplot(p,
        components = getComponents(p, c(4,33,11,1)),
        triangle = FALSE,
        hline = 0, vline = 0,
        pointSize = 0.8,
        gridlines.major = FALSE, gridlines.minor = FALSE,
        colby = 'ER',
        title = 'Pairs plot', titleLabSize = 22,
        axisLabSize = 14, plotaxes = TRUE,
        margingaps = unit(c(0.1, 0.1, 0.1, 0.1), 'cm'))
    plotloadings(p,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcatools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcatools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcatools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCATOOLS:", paste0("    pcatools: ", packageVersion("PCAtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcatools_results.csv
    touch ${prefix}_pcatools_output.rds
    echo "BIOC_PCATOOLS:" > versions.yml
    echo "    pcatools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCATOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PCATOOLS(ch_input)

    emit:
    results  = BIOC_PCATOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCATOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCATOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCATOOLS.out.versions  // channel: path(versions.yml)
}
