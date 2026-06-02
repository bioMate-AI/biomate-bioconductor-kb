#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BRAIN
// Package for calculating aggregated isotopic distribution and exact center-masses for chemical substa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BRAIN/inst/doc/BRAIN-vignette.R
// Upstream  : lattice
// Downstream: none
//
// Install: BiocManager::install("BRAIN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRAIN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-brain"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-brain:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-brain:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_brain_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_brain_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_brain_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BRAIN)
    library(jsonlite)

    # --- Isotopic Distribution Prediction [] ---
    # Key functions: useBRAIN
    peptide_seq <- "ACDEFGHIKLMNPQRSTVWY"
    brain_res <- useBRAIN(aSeq = peptide_seq)
    iso_probabilities <- brain_res$isoDistribution


    # --- Uniprot Data Processing [] ---
    # Key functions: uniprotBRAIN
    data(uniprotBRAIN, package = "brain")
    uniprot_subset <- uniprotBRAIN[uniprotBRAIN$monoMass < 10^5, ]
    target_sequences <- head(uniprot_subset$sequence, n = 10)


    # --- High-Throughput Isotopic Modeling [] ---
    # Key functions: useBRAIN
    data(uniprotBRAIN, package = "brain")
    uniprot_subset <- uniprotBRAIN[uniprotBRAIN$monoMass < 10^5, ]
    target_sequences <- head(uniprot_subset$sequence, n = 5)
    batch_distributions <- lapply(
        target_sequences,
        function(seq) useBRAIN(aSeq = seq)$isoDistribution
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_brain_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_brain_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_brain_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BRAIN:", paste0("    brain: ", packageVersion("BRAIN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brain_results.csv
    touch ${prefix}_brain_output.rds
    echo "BIOC_BRAIN:" > versions.yml
    echo "    brain: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BRAIN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BRAIN(ch_input)

    emit:
    results  = BIOC_BRAIN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BRAIN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BRAIN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BRAIN.out.versions  // channel: path(versions.yml)
}
