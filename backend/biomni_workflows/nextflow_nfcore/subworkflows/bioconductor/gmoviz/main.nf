#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gmoviz
// Genetically modified organisms (GMOs) and cell lines are widely used models in all kinds of biologic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gmoviz/inst/doc/gmoviz_advanced.R
// Upstream  : BiocManager, pasillaBamSubset
// Downstream: none
//
// Install: BiocManager::install("gmoviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMOVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmoviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmoviz:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmoviz:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gmoviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmoviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmoviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gmoviz)
    library(GRanges)
    library(jsonlite)

    # --- Coverage Calculation [] ---
    # Key functions: getCoverage
    chr4_coverage <- getCoverage(
        regions_of_interest = "chr4",
        bam_file = pasillaBamSubset::untreated3_chr4(),
        window_size = 350,
        smoothing_window_size = 400
    )


    # --- Circular Visualization Initialization [] ---
    # Key functions: gmovizInitialise
    gmovizInitialise(
        ideogram_data = fly_ideogram,
        coverage_rectangle = "chr4",
        coverage_data = chr4_coverage,
        xaxis_spacing = 30,
        space_between_sectors = 25,
        start_degree = 78,
        sector_label_size = 1,
        track_height = 0.15
    )


    # --- Label Annotation [] ---
    # Key functions: getLabels, gmovizInitialise
    labels_from_file <- getLabels(
        gff_file = system.file("extdata", "example.gff3", package = "gmoviz"),
        colour_code = TRUE
    )
    gmovizInitialise(
        fly_ideogram,
        label_data = labels_from_file,
        label_colour = labels_from_file$colour,
        space_between_sectors = 25,
        start_degree = 78,
        sector_label_size = 1,
        xaxis_spacing = 30
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmoviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmoviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmoviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMOVIZ:", paste0("    gmoviz: ", packageVersion("gmoviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmoviz_results.csv
    touch ${prefix}_gmoviz_output.rds
    echo "BIOC_GMOVIZ:" > versions.yml
    echo "    gmoviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMOVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GMOVIZ(ch_input)

    emit:
    results  = BIOC_GMOVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMOVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMOVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMOVIZ.out.versions  // channel: path(versions.yml)
}
