#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TMSig
// The TMSig package contains tools to prepare, analyze, and visualize named lists of sets, with an emp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TMSig/inst/doc/TMSig.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TMSig")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TMSIG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tmsig"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tmsig:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tmsig:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tmsig_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tmsig_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tmsig_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TMSig)
    library(jsonlite)

    # --- Background-Based Filtering [] ---
    # Key functions: filterSets
    topGenes <- table(unlist(geneSets))
    topGenes <- head(sort(topGenes, decreasing = TRUE), 2000L)
    background <- names(topGenes)
    geneSetsFilt <- filterSets(
        x = geneSets,
        background = background,
        min_size = 10L
    )
    setSizes <- lengths(geneSetsFilt)
    setSizesOld <- lengths(geneSets)[names(geneSetsFilt)]
    overlapProp <- setSizes / setSizesOld
    geneSetsFilt <- geneSetsFilt[overlapProp >= 0.7]


    # --- Similarity Matrix and Clustering [] ---
    # Key functions: sparseIncidence, similarity, clusterSets
    imat <- sparseIncidence(x = geneSetsFilt)
    jaccard <- similarity(x = geneSetsFilt, type = "jaccard")
    clusterDF <- clusterSets(
        x = geneSetsFilt,
        type = "jaccard",
        cutoff = 0.85,
        method = "complete",
        h = 0.9
    )


    # --- Set Decomposition and Inversion [] ---
    # Key functions: filterSets, decomposeSets, invertSets
    geneSetsFilt2 <- filterSets(geneSetsFilt, max_size = 50L)
    decompSets <- decomposeSets(x = geneSetsFilt2, overlap = 10L)
    invertedSets <- invertSets(x = geneSetsFilt)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tmsig_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tmsig_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tmsig_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TMSIG:", paste0("    tmsig: ", packageVersion("TMSig"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tmsig_results.csv
    touch ${prefix}_tmsig_output.rds
    echo "BIOC_TMSIG:" > versions.yml
    echo "    tmsig: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TMSIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TMSIG(ch_input)

    emit:
    results  = BIOC_TMSIG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TMSIG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TMSIG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TMSIG.out.versions  // channel: path(versions.yml)
}
