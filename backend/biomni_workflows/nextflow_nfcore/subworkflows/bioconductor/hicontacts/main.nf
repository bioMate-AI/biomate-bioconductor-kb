#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiContacts
// HiContacts provides a collection of tools to analyse and visualize Hi-C datasets imported in R by Hi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiContacts/inst/doc/HiContacts.R
// Upstream  : GenomicRanges, HiCExperiment, HiContactsData, InteractionSet, dplyr
// Downstream: none
//
// Install: BiocManager::install("HiContacts")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICONTACTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicontacts"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicontacts:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicontacts:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicontacts_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicontacts_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicontacts_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiContacts)
    library(GRanges)
    library(HiContactsData)
    library(P)
    library(SerialParam)
    library(jsonlite)

    # --- Matrix Detrending and Autocorrelation [] ---
    # Key functions: autocorrelate, detrend, plotMatrix
    mcool_file <- HiContactsData::HiContactsData("mESCs", format = "mcool")
    hic <- import(
        mcool_file, format = "mcool", focus = "chr2",
        resolution = 160000
    )
    hic_auto <- autocorrelate(hic)
    hic_detrend <- detrend(hic)
    p_auto <- plotMatrix(
        hic_auto, use.scores = "autocorrelated",
        limits = c(-1, 1), scale = "linear"
    )


    # --- Matrix Operations [] ---
    # Key functions: merge, divide
    mcool_1 <- HiContactsData::HiContactsData("yeast_eco1", format = "mcool")
    mcool_2 <- HiContactsData::HiContactsData("yeast_wt", format = "mcool")
    hic_1 <- import(mcool_1, format = "mcool", focus = "II", resolution = 2000)
    hic_2 <- import(mcool_2, format = "mcool", focus = "II", resolution = 2000)
    merged_hic <- merge(hic_1, hic_2)
    div_hic <- divide(hic_1, by = hic_2)


    # --- Compartment and Saddle Analysis [] ---
    # Key functions: getCompartments, topologicalFeatures, plotSaddle
    mcool_file <- HiContactsData::HiContactsData("yeast_wt", format = "mcool")
    hic <- import(mcool_file, format = "mcool", resolution = 16000)
    hic <- getCompartments(hic, chromosomes = c("XV", "XVI"))
    comp_A <- topologicalFeatures(hic, "compartments")[
        topologicalFeatures(hic, "compartments")$compartment == "A"
    ]
    p_saddle <- plotSaddle(hic)


    # --- Insulation and Border Detection [] ---
    # Key functions: zoom, getDiamondInsulation, getBorders, topologicalFeatures
    mcool_file <- HiContactsData::HiContactsData("yeast_wt", format = "mcool")
    hic <- import(mcool_file, format = "mcool", resolution = 16000)
    hic_borders <- getBorders(
        getDiamondInsulation(
            zoom(hic, resolution = 1000),
            window_size = 8000
        )
    )
    borders <- topologicalFeatures(hic_borders, "borders")


    # --- Virtual 4C Analysis [] ---
    # Key functions: virtual4C, plot4C
    mcool_file <- HiContactsData::HiContactsData("mESCs", format = "mcool")
    hic <- import(
        mcool_file, format = "mcool",
        focus = "chr18:20000000-35000000", resolution = 40000
    )
    v4C <- virtual4C(
        hic,
        viewpoint = GenomicRanges::GRanges("chr18:31000000-31050000")
    )
    p_4c <- plot4C(v4C, ggplot2::aes(x = center, y = score))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicontacts_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicontacts_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicontacts_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICONTACTS:", paste0("    hicontacts: ", packageVersion("HiContacts"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicontacts_results.csv
    touch ${prefix}_hicontacts_output.rds
    echo "BIOC_HICONTACTS:" > versions.yml
    echo "    hicontacts: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICONTACTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICONTACTS(ch_input)

    emit:
    results  = BIOC_HICONTACTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICONTACTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICONTACTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICONTACTS.out.versions  // channel: path(versions.yml)
}
