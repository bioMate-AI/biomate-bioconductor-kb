#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCBricks
// HiCBricks is a library designed for handling large high-resolution Hi-C datasets. Over the years, th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCBricks/inst/doc/IntroductionToHiCBricks.R
// Upstream  : GenomicRanges, curl, knitr
// Downstream: none
//
// Install: BiocManager::install("HiCBricks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICBRICKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicbricks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicbricks:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicbricks:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicbricks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicbricks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicbricks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiCBricks)
    library(Brick_add_ranges)
    library(Brick_get_ranges)
    library(Brick_vizart_plot_heatmap)
    library(jsonlite)

    # --- Load Hi-C Matrix Data [] ---
    # Key functions: load_BrickContainer, Brick_load_matrix
    brick_dir <- file.path(tempdir(), "HiCBricks_vignette_test")
    my_brick <- load_BrickContainer(project_dir = brick_dir)
    example_dir <- system.file("extdata", package = "HiCBricks")
    matrix_file <- file.path(example_dir,
        "Sexton2012_yaffetanay_CisTrans_100000_corrected_chr2L.txt.gz")
    Brick_load_matrix(Brick = my_brick,
        chr1 = "chr2L", chr2 = "chr2L",
        resolution = 100000, matrix_file = matrix_file,
        delim = " ", remove_prior = TRUE)


    # --- Query Genomic Ranges and Metadata [] ---
    # Key functions: load_BrickContainer, Brick_get_bintable, Brick_get_ranges, Brick_return_region_position
    brick_dir <- file.path(tempdir(), "HiCBricks_vignette_test")
    my_brick <- load_BrickContainer(project_dir = brick_dir)
    bin_table <- Brick_get_bintable(my_brick, resolution = 100000)
    chr3r_ranges <- Brick_get_ranges(Brick = my_brick,
        rangekey = "Bintable", chr = "chr3R", resolution = 100000)
    region_pos <- Brick_return_region_position(Brick = my_brick,
        region = "chr2L:5000000:10000000", resolution = 100000)


    # --- Extract Matrix Values by Distance [] ---
    # Key functions: load_BrickContainer, Brick_get_values_by_distance
    brick_dir <- file.path(tempdir(), "HiCBricks_vignette_test")
    my_brick <- load_BrickContainer(project_dir = brick_dir)
    failsafe_median <- function(x) {
        x[is.nan(x) | is.infinite(x) | is.na(x)] <- 0
        return(median(log10(x + 1)))
    }
    dist_values <- Brick_get_values_by_distance(Brick = my_brick,
        chr = "chr2L", distance = 4, resolution = 100000,
        FUN = failsafe_median)


    # --- Extract Sub-Matrix for Region [] ---
    # Key functions: load_BrickContainer, Brick_get_matrix_within_coords
    brick_dir <- file.path(tempdir(), "HiCBricks_vignette_test")
    my_brick <- load_BrickContainer(project_dir = brick_dir)
    sub_matrix <- Brick_get_matrix_within_coords(Brick = my_brick,
        x_coords = "chr2L:5000000:10000000",
        y_coords = "chr2L:5000000:10000000",
        resolution = 100000, force = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicbricks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicbricks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicbricks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICBRICKS:", paste0("    hicbricks: ", packageVersion("HiCBricks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicbricks_results.csv
    touch ${prefix}_hicbricks_output.rds
    echo "BIOC_HICBRICKS:" > versions.yml
    echo "    hicbricks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICBRICKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICBRICKS(ch_input)

    emit:
    results  = BIOC_HICBRICKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICBRICKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICBRICKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICBRICKS.out.versions  // channel: path(versions.yml)
}
