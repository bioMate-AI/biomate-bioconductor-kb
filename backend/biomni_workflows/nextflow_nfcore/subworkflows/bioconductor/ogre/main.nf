#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OGRE
// OGRE calculates overlap between user defined genomic region datasets. Any regions can be supplied i.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OGRE/inst/doc/OGRE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OGRE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OGRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ogre"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ogre:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ogre:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ogre_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ogre_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ogre_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OGRE)
    library(AnnotationHub)
    library(OGREDataSet)
    library(OGREDataSetFromDir)
    library(jsonlite)

    # --- Overlap Calculation [] ---
    # Key functions: fOverlaps, summarizeOverlap
    myOGRE <- fOverlaps(myOGRE)
    myOGRE <- summarizeOverlap(myOGRE)
    detail_dt <- metadata(myOGRE)$detailDT


    # --- Visualization [] ---
    # Key functions: sumPlot, plotHist, covPlot, gvizPlot
    myOGRE <- sumPlot(myOGRE)
    myOGRE <- plotHist(myOGRE)
    myOGRE <- covPlot(myOGRE)
    myOGRE <- gvizPlot(
        myOGRE, "ENSG00000142168",
        showPlot = FALSE,
        trackRegionLabels = setNames(
            c("name", "name"),
            c("genes", "CGI")
        )
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ogre_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ogre_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ogre_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OGRE:", paste0("    ogre: ", packageVersion("OGRE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ogre_results.csv
    touch ${prefix}_ogre_output.rds
    echo "BIOC_OGRE:" > versions.yml
    echo "    ogre: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OGRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OGRE(ch_input)

    emit:
    results  = BIOC_OGRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OGRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OGRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OGRE.out.versions  // channel: path(versions.yml)
}
