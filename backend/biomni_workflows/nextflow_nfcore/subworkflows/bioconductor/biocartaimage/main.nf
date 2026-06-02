#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioCartaImage
// The core functionality of the package is to provide coordinates of genes on the BioCarta pathway ima
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioCartaImage/inst/doc/BioCartaImage.R
// Upstream  : grid, knitr
// Downstream: none
//
// Install: BiocManager::install("BioCartaImage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCARTAIMAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocartaimage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocartaimage:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocartaimage:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocartaimage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocartaimage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocartaimage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioCartaImage)
    library(jsonlite)

    # --- Gene Querying [] ---
    # Key functions: genes_in_pathway
    genes_by_id <- genes_in_pathway("h_RELAPathway")
    genes_by_obj <- genes_in_pathway(p_obj)


    # --- Pathway Visualization [] ---
    # Key functions: grid.biocarta
    grid::grid.newpage()
    grid.biocarta(
        "h_RELAPathway",
        color = c("1387" = "yellow")
    )
    grid::grid.newpage()
    grid.biocarta(
        "h_RELAPathway",
        x = grid::unit(0.2, "npc"),
        y = grid::unit(0.9, "npc"),
        just = c("left", "top"),
        color = c("1387" = "yellow"),
        width = grid::unit(6, "cm")
    )


    # --- Advanced Gene Marking and Customization [] ---
    # Key functions: biocartaGrob, mark_gene, pos_by_polygon
    grob <- biocartaGrob("h_RELAPathway")
    grid::grid.newpage()
    grob_marked <- mark_gene(grob, "1387", function(x, y) {
        pos <- pos_by_polygon(x, y, where = "left")
        grid::pointsGrob(
            pos[1], pos[2],
            default.units = "native",
            pch = 16,
            gp = grid::gpar(col = "yellow")
        )
    })
    grid::grid.draw(grob_marked)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocartaimage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocartaimage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocartaimage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCARTAIMAGE:", paste0("    biocartaimage: ", packageVersion("BioCartaImage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocartaimage_results.csv
    touch ${prefix}_biocartaimage_output.rds
    echo "BIOC_BIOCARTAIMAGE:" > versions.yml
    echo "    biocartaimage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCARTAIMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCARTAIMAGE(ch_input)

    emit:
    results  = BIOC_BIOCARTAIMAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCARTAIMAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCARTAIMAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCARTAIMAGE.out.versions  // channel: path(versions.yml)
}
