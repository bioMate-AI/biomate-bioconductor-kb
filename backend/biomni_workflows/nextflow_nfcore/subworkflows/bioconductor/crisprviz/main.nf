#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: crisprViz
// Provides functionalities to visualize and contextualize CRISPR guide RNAs (gRNAs) on genomic tracks 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/crisprViz/inst/doc/intro.R
// Upstream  : crisprDesign
// Downstream: none
//
// Install: BiocManager::install("crisprViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprviz:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprviz:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(crisprViz)
    library(jsonlite)

    # --- Targeted Exon Visualization [] ---
    # Key functions: queryTxObject, plotGuideSet
    data("krasGuideSet", package="crisprViz")
    data("krasGeneModel", package="crisprViz")
    targetExon <- queryTxObject(
        krasGeneModel,
        featureType="cds",
        queryColumn="exon_id",
        queryValue="ENSE00000936617"
    )
    targetExon <- unique(targetExon)
    plotGuideSet(
        krasGuideSet,
        geneModel=krasGeneModel,
        targetGene="KRAS",
        from=start(targetExon),
        to=end(targetExon),
        extend.left=20,
        extend.right=20
    )


    # --- Genomic Annotation and Repeat Visualization [] ---
    # Key functions: plotGuideSet
    data("mmp7GuideSet", package="crisprViz")
    data("mmp7GeneModel", package="crisprViz")
    data("repeats", package="crisprViz")
    from <- min(start(mmp7GuideSet))
    to <- max(end(mmp7GuideSet))
    plotGuideSet(
        mmp7GuideSet,
        geneModel=mmp7GeneModel,
        targetGene="MMP7",
        guideStacking="dense",
        annotations=list(Repeats=repeats),
        pamSiteOnly=TRUE,
        from=from,
        to=to,
        extend.left=600,
        extend.right=100,
        includeSNPTrack=TRUE
    )


    # --- Epigenetic Track Integration [] ---
    # Key functions: plotGuideSet
    data("mmp7GuideSet", package="crisprViz")
    data("mmp7GeneModel", package="crisprViz")
    data("cage", package="crisprViz")
    data("dnase", package="crisprViz")
    plotGuideSet(
        mmp7GuideSet,
        geneModel=mmp7GeneModel,
        targetGene="MMP7",
        guideStacking="dense",
        annotations=list(CAGE=cage, DNase=dnase),
        pamSiteOnly=TRUE,
        margin=0.4
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRVIZ:", paste0("    crisprviz: ", packageVersion("crisprViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprviz_results.csv
    touch ${prefix}_crisprviz_output.rds
    echo "BIOC_CRISPRVIZ:" > versions.yml
    echo "    crisprviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRVIZ(ch_input)

    emit:
    results  = BIOC_CRISPRVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRVIZ.out.versions  // channel: path(versions.yml)
}
