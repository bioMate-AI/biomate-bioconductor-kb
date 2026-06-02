#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: profileplyr
// Quick and straightforward visualization of read signal over genomic intervals is key for generating 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/profileplyr/inst/doc/profileplyr.R
// Upstream  : Rsamtools, SummarizedExperiment, ggplot2, magrittr
// Downstream: none
//
// Install: BiocManager::install("profileplyr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROFILEPLYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-profileplyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-profileplyr:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-profileplyr:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_profileplyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_profileplyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_profileplyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamBigwig_to_chipProfile)
    library(jsonlite)

    # --- generate Enriched Heatmap [] ---
    # Key functions: generateEnrichedHeatmap
    heatmap <- generateEnrichedHeatmap(proplyrObject)
    class(heatmap)
    # --- convert To Enriched Heatmap Mat [] ---
    # Key functions: convertToEnrichedHeatmapMat, summarize
    EH_mat <- convertToEnrichedHeatmapMat(proplyrObject)
    the matrices of this list can be inputs for EnrichedHeatmap()
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_boxplot
    library(ggplot2)
    ggplot(proplyrObject_long, aes(x = Sample, y = log(Signal))) +
    geom_boxplot()
    # --- cluster Ranges [] ---
    # Key functions: clusterRanges

    # --- cluster Ranges [] ---
    # Key functions: clusterRanges, rowRanges, params
    set.seed(0)
    # --- cluster Ranges [] ---
    # Key functions: clusterRanges
    set.seed(0)
    # --- generate Enriched Heatmap [] ---
    # Key functions: generateEnrichedHeatmap
    generateEnrichedHeatmap(kmeans)
    # --- Bam Bigwig_to_chip Profile [] ---
    # Key functions: BamBigwig_to_chipProfile, annotateRanges, groupBy, generateEnrichedHeatmap

    # --- import_deep Tools Mat [] ---
    # Key functions: import_deepToolsMat, annotateRanges, groupBy, clusterRanges, generateEnrichedHeatmap
    NOTE: could also use BamBigwig_to_chipProfile() and as_profileplyr()
    set.seed(0)
    annotated_object <- import_deepToolsMat(example) %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_profileplyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_profileplyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_profileplyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROFILEPLYR:", paste0("    profileplyr: ", packageVersion("profileplyr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profileplyr_results.csv
    touch ${prefix}_profileplyr_output.rds
    echo "BIOC_PROFILEPLYR:" > versions.yml
    echo "    profileplyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROFILEPLYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROFILEPLYR(ch_input)

    emit:
    results  = BIOC_PROFILEPLYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROFILEPLYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROFILEPLYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROFILEPLYR.out.versions  // channel: path(versions.yml)
}
