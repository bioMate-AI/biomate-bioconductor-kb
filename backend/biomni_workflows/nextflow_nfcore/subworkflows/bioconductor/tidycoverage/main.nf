#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidyCoverage
// `tidyCoverage` framework enables tidy manipulation of collections of genomic tracks and features usi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidyCoverage/inst/doc/tidyCoverage.R
// Upstream  : AnnotationHub, ggplot2, plyranges, purrr, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("tidyCoverage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYCOVERAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidycoverage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidycoverage:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidycoverage:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidycoverage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidycoverage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidycoverage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(BigWigFileList)
    library(CoverageExperiment)
    library(GRanges)
    library(jsonlite)

    # --- Showclass [] ---
    # Key functions: showClass, rowData, rowRanges, colData, assays, assay
    ---------------------------------------------------------------------
    library(tidyCoverage)
    showClass("CoverageExperiment")
    data(ce)
    ce
    # --- Assay [] ---
    # Key functions: assay, rowData, width
    ---------------------------------------------------------------------
    assay(ce, 'coverage')
    assay(ce, 'coverage')[1, 1] |> class()
    assay(ce, 'coverage')[1, 1] |> length()
    assay(ce, 'coverage')[1, 1][[1]] |> class()
    # --- Showclass [] ---
    # Key functions: showClass, rowData, rowRanges, colData, assays, assay
    ---------------------------------------------------------------------
    showClass("AggregatedCoverage")
    data(ac)
    ac
    rowData(ac)
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    assay(ac[1, 1], 'mean')[[1]] |> dim()
    assay(ac[1, 1], 'mean')[[1]] |> length()
    assay(ac[1, 1], 'mean')[[1]][1:10]
    # --- Coverageexperiment [] ---
    # Key functions: CoverageExperiment, import, assay
    ---------------------------------------------------------------------
    CE2 <- CoverageExperiment(
        tracks = import(bw_file, as = "Rle"),
        features = import(bed_file),
        width = 3000,
    # --- Coarsen [] ---
    # Key functions: coarsen
    ---------------------------------------------------------------------
    CE3 <- coarsen(CE, window = 20)
    CE3
    identical(CE2, CE3)
    # --- Expand [] ---
    # Key functions: expand
    ---------------------------------------------------------------------
    expand(CE)
    # --- List [] ---
    # Key functions: BigWigFileList, GRanges, CoverageExperiment, width
    ---------------------------------------------------------------------
    # ~~~~~~~~~~~~~~~ Import coverage tracks into a named list ~~~~~~~~~~~~~~~ #
    tracks <- list(
        Scc1 = system.file("extdata", "Scc1.bw", package = "tidyCoverage"),
        RNA_fwd = system.file("extdata", "RNA.fwd.bw", package = "tidyCoverage"),
    # --- Coarsen [] ---
    # Key functions: coarsen, expand, ggplot, aes, geom_col, facet_grid, scale_x_continuous
    ---------------------------------------------------------------------
    library(ggplot2)
    CE_chrII |>
        coarsen(window = 10) |>
        expand() |>
    # --- Aggregate [] ---
    # Key functions: aggregate, assay
    ---------------------------------------------------------------------
    AC <- aggregate(CE)
    AC
    assay(AC, 'mean')[1, 1][[1]] |> length()
    # --- As Tibble [] ---
    # Key functions: as_tibble
    ---------------------------------------------------------------------
    as_tibble(AC20)
    # --- Coverageexperiment [] ---
    # Key functions: CoverageExperiment, import, coarsen, aggregate, as_tibble
    ---------------------------------------------------------------------
    # Coarsen `CoverageExperiment` with `window = ...` then per-bin `aggregate`:
    CoverageExperiment(
        tracks = import(bw_file, as = "Rle"), features = import(bed_file),
        width = 3000
    # --- List [] ---
    # Key functions: map, CoverageExperiment, aggregate
    ---------------------------------------------------------------------
    library(purrr)
    library(plyranges)
    # ~~~~~~~~~~~~~~~ Import genomic features into a named list ~~~~~~~~~~~~~~~ #
    features <- list(
    # --- As Tibble [] ---
    # Key functions: as_tibble, ggplot, geom_aggrcoverage
    ---------------------------------------------------------------------
    AC |>
        as_tibble() |>
        ggplot() +
        geom_aggrcoverage()
    # --- As Tibble [] ---
    # Key functions: as_tibble, ggplot, aes, geom_aggrcoverage, facet_grid
    ---------------------------------------------------------------------
    AC |>
        as_tibble() |>
        ggplot(aes(col = track)) +
        geom_aggrcoverage() +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidycoverage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidycoverage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidycoverage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYCOVERAGE:", paste0("    tidycoverage: ", packageVersion("tidyCoverage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidycoverage_results.csv
    touch ${prefix}_tidycoverage_output.rds
    echo "BIOC_TIDYCOVERAGE:" > versions.yml
    echo "    tidycoverage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYCOVERAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYCOVERAGE(ch_input)

    emit:
    results  = BIOC_TIDYCOVERAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYCOVERAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYCOVERAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYCOVERAGE.out.versions  // channel: path(versions.yml)
}
