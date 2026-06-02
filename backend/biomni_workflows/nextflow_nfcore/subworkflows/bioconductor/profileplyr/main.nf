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
    library(profileplyr)
    library(BamBigwig_to_chipProfile)
    library(jsonlite)

    # --- Data Import and Object Creation [import] ---
    # Key functions: import_deepToolsMat, BamBigwig_to_chipProfile, as_profileplyr
    example_file <- system.file("extdata", "example_deepTools_MAT",
                                package = "profileplyr")
    proplyrObject <- import_deepToolsMat(example_file)
    test_ranges <- system.file("extdata", "newranges_small.bed",
                               package = "profileplyr")
    signal_files <- system.file("extdata",
                                "Sorted_Hindbrain_day_12_1_filtered.bam",
                                package = "profileplyr")
    chip_profile <- BamBigwig_to_chipProfile(signal_files, test_ranges,
                                             format = "bam", paired = FALSE,
                                             style = "percentOfRegion")
    proplyr_from_bam <- as_profileplyr(chip_profile)

    # --- Metadata Annotation and Sorting [annotation] ---
    # Key functions: sampleData, orderBy
    example_file <- system.file("extdata", "example_deepTools_MAT",
                                package = "profileplyr")
    proplyrObject <- import_deepToolsMat(example_file)
    rownames(sampleData(proplyrObject)) <- c("Hindbrain", "Liver", "Kidney")
    proplyr_ordered <- orderBy(proplyrObject, "score")

    # --- Clustering Genomic Ranges [clustering] ---
    # Key functions: clusterRanges
    example_file <- system.file("extdata", "example_deepTools_MAT",
                                package = "profileplyr")
    proplyrObject <- import_deepToolsMat(example_file)
    kmeans_clustered <- clusterRanges(proplyrObject,
                                      fun = rowMeans,
                                      kmeans_k = 4,
                                      silent = TRUE)
    hclust_clustered <- clusterRanges(proplyrObject,
                                      fun = rowMeans,
                                      cutree_rows = 4,
                                      silent = TRUE)

    # --- Signal Summarization [summarization] ---
    # Key functions: summarize
    example_file <- system.file("extdata", "example_deepTools_MAT",
                                package = "profileplyr")
    proplyrObject <- import_deepToolsMat(example_file)
    object_sum_mat <- summarize(proplyrObject,
                                fun = rowMeans,
                                output = "matrix")
    object_sum_long <- summarize(proplyrObject,
                                 fun = rowMeans,
                                 output = "long")
    object_sum_obj <- summarize(proplyrObject,
                                fun = rowMeans,
                                output = "object")

    # --- Heatmap Generation and Export [visualization] ---
    # Key functions: generateEnrichedHeatmap, convertToEnrichedHeatmapMat, export_deepToolsMat
    example_file <- system.file("extdata", "example_deepTools_MAT",
                                package = "profileplyr")
    proplyrObject <- import_deepToolsMat(example_file)
    heatmap_plot <- generateEnrichedHeatmap(proplyrObject)
    eh_matrix_list <- convertToEnrichedHeatmapMat(proplyrObject)
    output_path <- file.path(tempdir(), "ATAC_example.MAT.gz")
    export_deepToolsMat(proplyrObject, con = output_path)


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
