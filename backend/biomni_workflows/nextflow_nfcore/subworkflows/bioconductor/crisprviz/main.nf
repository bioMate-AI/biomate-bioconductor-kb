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

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("krasGuideSet", package="crisprViz")
    data("krasGeneModel", package="crisprViz")
    length(krasGuideSet) # number of candidate gRNAs
    # --- Plotguideset [] ---
    # Key functions: plotGuideSet
    ---------------------------------------------------------------------
    plotGuideSet(krasGuideSet[1:4],
                 geneModel=krasGeneModel,
                 targetGene="KRAS")
    # --- Min [] ---
    # Key functions: start, end, plotGuideSet
    ---------------------------------------------------------------------
    from <- min(start(krasGeneModel$transcripts))
    to <- max(end(krasGeneModel$transcripts))
    plotGuideSet(krasGuideSet[1:4],
                 geneModel=krasGeneModel,
    # --- Querytxobject [] ---
    # Key functions: queryTxObject, start, end, plotGuideSet
    ---------------------------------------------------------------------
    # new window range around target exon
    targetExon <- queryTxObject(krasGeneModel,
                                featureType="cds",
                                queryColumn="exon_id",
    # --- Plotguideset [] ---
    # Key functions: plotGuideSet
    ---------------------------------------------------------------------
    plotGuideSet(krasGuideSet,
                 geneModel=krasGeneModel,
                 targetGene="KRAS",
                 from=from,
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("gpr21GuideSet", package="crisprViz")
    data("gpr21GeneModel", package="crisprViz")
    # --- Min [] ---
    # Key functions: start, end, plotGuideSet
    ---------------------------------------------------------------------
    from <- min(start(mmp7GuideSet))
    to <- max(end(mmp7GuideSet))
    plotGuideSet(mmp7GuideSet,
                 geneModel=mmp7GeneModel,
    # --- Removerepeats [] ---
    # Key functions: removeRepeats, plotGuideSet
    ---------------------------------------------------------------------
    filteredGuideSet <- crisprDesign::removeRepeats(mmp7GuideSet,
                                                    gr.repeats=repeats)
    filteredGuideSet <- filteredGuideSet[!filteredGuideSet$hasSNP]
    plotGuideSet(filteredGuideSet,
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("cage", package="crisprViz")
    data("dnase", package="crisprViz")
    # --- Plotguideset [] ---
    # Key functions: plotGuideSet
    ---------------------------------------------------------------------
    plotGuideSet(filteredGuideSet,
                 geneModel=mmp7GeneModel,
                 targetGene="MMP7",
                 guideStacking="dense",
    # --- Findoverlaps [] ---
    # Key functions: findOverlaps, queryHits, plotGuideSet
    ---------------------------------------------------------------------
    # filter GuideSet for gRNAs overlapping DNase track
    overlaps <- findOverlaps(filteredGuideSet, dnase, ignore.strand=TRUE)
    finalGuideSet <- filteredGuideSet[queryHits(overlaps)]
    plotGuideSet(finalGuideSet,
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("cas9GuideSet", package="crisprViz")
    data("cas12aGuideSet", package="crisprViz")
    data("ltn1GeneModel", package="crisprViz")

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
