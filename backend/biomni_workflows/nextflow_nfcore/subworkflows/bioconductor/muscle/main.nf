#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: muscle
// MUSCLE performs multiple sequence alignments of nucleotide or amino acid sequences.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/muscle/inst/doc/muscle-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("muscle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSCLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-muscle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-muscle:3.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-muscle:3.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_muscle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_muscle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_muscle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(muscle)
    library(jsonlite)

    # --- Muscle Vignette.Rnw:88 90 [] ---
    # Key functions: readDNAStringSet
    file.path <- system.file("extdata", "someORF.fa", package = "Biostrings")
    orf <- readDNAStringSet(file.path, format = "fasta")
    # --- Muscle Vignette.Rnw:109 110 [] ---
    # Key functions: muscle
    aln <- muscle(umax, diags = TRUE)
    # --- Muscle Vignette.Rnw:115 116 [] ---
    # Key functions: muscle
    aln <- muscle(umax, gapopen = -30)
    # --- Muscle Vignette.Rnw:121 122 [] ---
    # Key functions: muscle
    aln <- muscle(umax, quiet = TRUE)
    # --- Muscle Vignette.Rnw:127 128 [] ---
    # Key functions: muscle
    aln <- muscle(umax, maxhours = 24.0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_muscle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_muscle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_muscle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUSCLE:", paste0("    muscle: ", packageVersion("muscle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_muscle_results.csv
    touch ${prefix}_muscle_output.rds
    echo "BIOC_MUSCLE:" > versions.yml
    echo "    muscle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUSCLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUSCLE(ch_input)

    emit:
    results  = BIOC_MUSCLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUSCLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUSCLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUSCLE.out.versions  // channel: path(versions.yml)
}
