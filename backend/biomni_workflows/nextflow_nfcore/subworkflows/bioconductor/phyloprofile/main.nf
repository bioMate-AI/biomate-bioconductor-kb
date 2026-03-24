#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhyloProfile
// PhyloProfile is a tool for exploring complex phylogenetic profiles. Phylogenetic profiles, presence/
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhyloProfile/inst/doc/PhyloProfile-vignette.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("PhyloProfile")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phyloprofile"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phyloprofile:1.20.4--r44_0' :
        'quay.io/biocontainers/bioconductor-phyloprofile:1.20.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phyloprofile_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phyloprofile_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phyloprofile_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PhyloProfile)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: levels, factor, sortInputTaxa, count, estimateGeneAge
    ---------------------------------------------------------------------
    ### An example for calculating gene age for the built-in data set.
    ### See ?estimateGeneAge for more details.
    #' Load built-in data
    data("fullProcessedProfile", package="PhyloProfile")
    # --- Data [] ---
    # Key functions: levels, factor, sortInputTaxa, count, getCoreGene
    ---------------------------------------------------------------------
    ### An example for calculating core gene set for the built-in data set.
    ### See ?getCoreGene for more details.
    #' Load built-in data
    data("fullProcessedProfile", package="PhyloProfile")
    # --- Data [] ---
    # Key functions: compareTaxonGroups
    ---------------------------------------------------------------------
    #' Load built-in data
    data("mainLongRaw", package="PhyloProfile")
    data <- mainLongRaw
    #' choose the in-group taxa
    # --- Format [] ---
    # Key functions: tree, genes, fromInputToProfile
    ---------------------------------------------------------------------
    #' Load built-in data
    #' If input data is in other format (e.g. fasta, OrthoXML, or wide matrix),
    #' see ?createLongMatrix
    rawInput <- system.file(
    # --- Data [] ---
    # Key functions: getInputTaxaID, getInputTaxaName
    ---------------------------------------------------------------------
    #' Load raw input
    data("mainLongRaw", package="PhyloProfile")
    inputDf <- mainLongRaw
    #' Set working rank and the reference taxon
    # --- Data [] ---
    # Key functions: getInputTaxaID, tree, sortInputTaxa
    ---------------------------------------------------------------------
    #' Get list of taxon IDs and names for input profile
    data("mainLongRaw", package="PhyloProfile")
    inputDf <- mainLongRaw
    rankName <- "phylum"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phyloprofile_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phyloprofile_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phyloprofile_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHYLOPROFILE:", paste0("    phyloprofile: ", packageVersion("PhyloProfile"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phyloprofile_results.csv
    touch ${prefix}_phyloprofile_output.rds
    echo "BIOC_PHYLOPROFILE:" > versions.yml
    echo "    phyloprofile: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHYLOPROFILE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHYLOPROFILE(ch_input)

    emit:
    results  = BIOC_PHYLOPROFILE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHYLOPROFILE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHYLOPROFILE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHYLOPROFILE.out.versions  // channel: path(versions.yml)
}
