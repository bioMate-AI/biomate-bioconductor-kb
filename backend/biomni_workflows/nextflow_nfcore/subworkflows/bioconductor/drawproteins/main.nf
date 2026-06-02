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

    # --- download rel json [] ---
    # Key functions: get_features
    drawProteins::get_features("Q04206") ->
    # --- generate dataframe [] ---
    # Key functions: feature_to_dataframe
    drawProteins::feature_to_dataframe(rel_json) -> rel_data
    head(rel_data[1:4])
    # --- using draw canvas [] ---
    # Key functions: draw_canvas
    draw_canvas(rel_data) -> p
    # --- using draw chains [] ---
    # Key functions: draw_chains
    p <- draw_chains(p, rel_data)
    # --- using draw domains [] ---
    # Key functions: draw_domains
    p <- draw_domains(p, rel_data)
    # --- white background [] ---
    # Key functions: theme
    p <- p + theme_bw(base_size = 20) + # white background
    theme(panel.grid.minor=element_blank(),
    panel.grid.major=element_blank()) +
    # --- show draw regions [] ---
    # Key functions: draw_regions
    draw_regions(p, rel_data) # adds activation domain
    # --- show draw repeat [] ---
    # Key functions: draw_repeat
    draw_repeat(p, rel_data) # doesn't add anything in this case
    # --- show draw motif [] ---
    # Key functions: draw_motif
    draw_motif(p, rel_data) # adds 9aa Transactivation domain & NLS
    # --- show draw phospho [] ---
    # Key functions: draw_phospho
    draw_phospho(p, rel_data, size = 8)
    # --- relA workflow [] ---
    # Key functions: draw_canvas, draw_chains, draw_domains, draw_regions, draw_motif
    draw_canvas(rel_data) -> p
    p <- draw_chains(p, rel_data)
    p <- draw_domains(p, rel_data)
    # --- five NFkappaB [] ---
    # Key functions: get_features, feature_to_dataframe, draw_canvas, draw_chains, draw_domains
    prot_data <- drawProteins::get_features("Q04206 Q01201 Q04864 P19838 Q00653")
    prot_data <- drawProteins::feature_to_dataframe(prot_data)
    p <- draw_canvas(prot_data)
    # --- draw_canvas [] ---
    # Key functions: draw_canvas, draw_chains
    data("five_rel_data")
    p <- draw_canvas(five_rel_data)
    # --- draw_canvas [] ---
    # Key functions: draw_canvas, draw_chains, draw_phospho
    p <- draw_canvas(five_rel_data)

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
