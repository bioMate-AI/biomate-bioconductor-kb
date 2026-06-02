#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: drawProteins
// This package draws protein schematics from Uniprot API output. From the JSON returned by the GET com
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/drawProteins/inst/doc/drawProteins_BiocStyle.R
// Upstream  : BiocStyle, ggplot2, httr, knitr
// Downstream: none
//
// Install: BiocManager::install("drawProteins")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DRAWPROTEINS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-drawproteins"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-drawproteins:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-drawproteins:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_drawproteins_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_drawproteins_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_drawproteins_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(drawProteins)
    library(jsonlite)

    # --- Feature Extraction [] ---
    # Key functions: feature_to_dataframe
    prot_data <- drawProteins::feature_to_dataframe(prot_json)


    # --- Canvas Initialization and Chain Drawing [] ---
    # Key functions: draw_canvas, draw_chains
    p <- draw_canvas(prot_data)
    p <- draw_chains(
        p,
        prot_data,
        fill = "lightsteelblue1",
        outline = "grey",
        label_size = 5
    )


    # --- Domain and Motif Annotation [] ---
    # Key functions: draw_domains, draw_regions, draw_motif, draw_repeat
    p <- draw_domains(p, prot_data)
    p <- draw_regions(p, prot_data)
    p <- draw_motif(p, prot_data)
    p <- draw_repeat(p, prot_data)


    # --- Post-Translational Modification and Styling [] ---
    # Key functions: draw_phospho
    p <- draw_phospho(p, prot_data, size = 8, fill = "red")
    p <- p + ggplot2::theme_bw(base_size = 20) +
        ggplot2::theme(
            panel.grid.minor = ggplot2::element_blank(),
            panel.grid.major = ggplot2::element_blank(),
            axis.ticks = ggplot2::element_blank(),
            axis.text.y = ggplot2::element_blank(),
            panel.border = ggplot2::element_blank(),
            legend.position = "top"
        ) +
        ggplot2::labs(
            title = "Schematic of human NF-kappaB proteins",
            subtitle = "circles = phosphorylation sites\nsource: UniProt",
            fill = ""
        )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_drawproteins_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_drawproteins_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_drawproteins_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DRAWPROTEINS:", paste0("    drawproteins: ", packageVersion("drawProteins"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drawproteins_results.csv
    touch ${prefix}_drawproteins_output.rds
    echo "BIOC_DRAWPROTEINS:" > versions.yml
    echo "    drawproteins: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DRAWPROTEINS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DRAWPROTEINS(ch_input)

    emit:
    results  = BIOC_DRAWPROTEINS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DRAWPROTEINS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DRAWPROTEINS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DRAWPROTEINS.out.versions  // channel: path(versions.yml)
}
