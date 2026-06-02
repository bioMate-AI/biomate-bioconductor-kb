#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spatialSimGP
// This packages simulates spatial transcriptomics data with the mean- variance relationship using a Ga
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spatialSimGP/inst/doc/spatialSimGP.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("spatialSimGP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALSIMGP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialsimgp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialsimgp:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialsimgp:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_spatialsimgp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialsimgp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialsimgp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Visium_mouseCoronal)
    library(jsonlite)

    # --- Visium Mousecoronal [] ---
    # Key functions: Visium_mouseCoronal, colData, ifelse, spatialCoords
    ---------------------------------------------------------------------
    spe_demo <- Visium_mouseCoronal()
    # --- Frame [] ---
    # Key functions: frame, spatialCoords, counts, ggplot, aes, geom_point, coord_fixed
    ---------------------------------------------------------------------
    df <- as.data.frame(cbind(spatialCoords(spe), expr = counts(spe)[1, ]))
    ggplot(df, aes(x = pxl_col_in_fullres, y = pxl_row_in_fullres,
                   color = expr)) +
      geom_point(size = 2.2) +
    # --- Rep [] ---
    # Key functions: spatial_simulate
    ---------------------------------------------------------------------
    # 20 spots per side
    n_side <- 20
    # x and y coordinates for the grid
    x_coords <- rep(1:n_side, each = n_side)
    # --- Frame [] ---
    # Key functions: frame, spatialCoords, counts, ggplot, aes, geom_point, coord_fixed
    ---------------------------------------------------------------------
    df <- as.data.frame(cbind(spatialCoords(spe), expr = counts(spe)[1, ]))
    ggplot(df, aes(x = pxl_col_in_fullres, y = pxl_row_in_fullres,
                   color = expr)) +
      geom_point(size = 5) +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialsimgp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialsimgp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialsimgp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALSIMGP:", paste0("    spatialsimgp: ", packageVersion("spatialSimGP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialsimgp_results.csv
    touch ${prefix}_spatialsimgp_output.rds
    echo "BIOC_SPATIALSIMGP:" > versions.yml
    echo "    spatialsimgp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALSIMGP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_SPATIALSIMGP(ch_input)

    emit:
    results  = BIOC_SPATIALSIMGP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALSIMGP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALSIMGP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALSIMGP.out.versions  // channel: path(versions.yml)
}
