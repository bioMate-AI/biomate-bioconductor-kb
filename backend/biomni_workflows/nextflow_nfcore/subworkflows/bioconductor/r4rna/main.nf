#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: R4RNA
// A package for RNA basepair analysis, including the visualization of basepairs as arc diagrams for ea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/R4RNA/inst/doc/R4RNA.R
// Upstream  : Biostrings
// Downstream: none
//
// Install: BiocManager::install("R4RNA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R4RNA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-r4rna"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-r4rna:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-r4rna:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_r4rna_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_r4rna_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_r4rna_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(R4RNA)
    library(jsonlite)

    # --- Plothelix [] ---
    # Key functions: plotHelix
    plotHelix(known, line = TRUE, arrow = TRUE)
    mtext("Known Structure", side = 3, line = -2, adj = 0)
    # --- Plotdoublehelix [] ---
    # Key functions: plotDoubleHelix
    plotDoubleHelix(transat, known, line = TRUE, arrow = TRUE)
    mtext("TRANSAT\nPredicted\nStructure", side = 3, line = -5, adj = 0)
    mtext("Known Structure", side = 1, line = -2, adj = 0)
    # --- Colourbyvalue [] ---
    # Key functions: colourByValue, plotDoubleHelix, attr
    message("Assign colour to basepairs according to p-value")
    transat$col <- col <- colourByValue(transat, log = TRUE)
    message("Coloured encoded in 'col' column of transat structure")
    plotDoubleHelix(transat, known, line = TRUE, arrow = TRUE)
    # --- Plotoverlaphelix [] ---
    # Key functions: plotOverlapHelix
    plotOverlapHelix(transat, known, line = TRUE, arrow = TRUE, scale = FALSE)
    # --- Plotcovariance [] ---
    # Key functions: plotCovariance
    plotCovariance(fasta, transat, cex = 0.5, conflict.col = "grey")
    # --- Colourbycovariation [] ---
    # Key functions: colourByCovariation, plotCovariance, attr
    col <- colourByCovariation(known, fasta, get = TRUE)
    plotCovariance(fasta, col, grid = TRUE, legend = FALSE)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.1, bty = "n", border = NA, cex = 0.37, title = "Covariation")
    # --- Colourbycanonical [] ---
    # Key functions: colourByCanonical, plotCovariance, attr
    col <- colourByCanonical(known, fasta, custom_colours, get = TRUE)
    plotCovariance(fasta, col, base.colour = TRUE, cex = 0.5)
    legend("topright", legend = attr(col, "legend"), fill = attr(col, "fill"),
        inset = 0.15, bty = "n", border = NA, cex = 0.75, title = "% Canonical")
    # --- Colourbyunknottedgroups [] ---
    # Key functions: colourByUnknottedGroups, plotCovariance
    col <- colourByUnknottedGroups(known, c("red", "blue"), get = TRUE)
    plotCovariance(fasta, col, base.colour = TRUE, legend = FALSE, species = 23, grid = TRUE, text = TRUE, text.cex = 0.2, cex = 0.5)
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_r4rna_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_r4rna_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_r4rna_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_R4RNA:", paste0("    r4rna: ", packageVersion("R4RNA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r4rna_results.csv
    touch ${prefix}_r4rna_output.rds
    echo "BIOC_R4RNA:" > versions.yml
    echo "    r4rna: 0.0.0" >> versions.yml
    """
}


workflow BIOC_R4RNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_R4RNA(ch_input)

    emit:
    results  = BIOC_R4RNA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_R4RNA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_R4RNA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_R4RNA.out.versions  // channel: path(versions.yml)
}
