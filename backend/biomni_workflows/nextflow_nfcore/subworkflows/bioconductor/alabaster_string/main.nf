#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.string
// Save Biostrings objects to file artifacts, and load them back into memory. This is a more portable a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.string/inst/doc/userguide.R
// Upstream  : BiocStyle, Biostrings
// Downstream: none
//
// Install: BiocManager::install("alabaster.string")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_STRING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_string"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.string:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.string:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_string_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_string_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_string_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(PhredQuality)
    library(QualityScaledDNAStringSet)
    library(jsonlite)

    # --- Dnastringset [] ---
    # Key functions: DNAStringSet, mcols, runif, tempfile, saveObject
    ---------------------------------------------------------------------
    library(Biostrings)
    x <- DNAStringSet(c(seq1="CTCNACCAGTAT", seq2="TTGA", seq3="TACCTAGAG"))
    mcols(x)$score <- runif(length(x))
    x
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    roundtrip <- readObject(tmp)
    class(roundtrip)
    # --- Dnastringset [] ---
    # Key functions: DNAStringSet, PhredQuality, QualityScaledDNAStringSet, tempfile, saveObject, readObject
    ---------------------------------------------------------------------
    x <- DNAStringSet(c("TTGA", "CTCN"))
    q <- PhredQuality(c("*+,-", "6789"))
    y <- QualityScaledDNAStringSet(x, q)
    library(alabaster.string)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_string_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_string_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_string_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_STRING:", paste0("    alabaster_string: ", packageVersion("alabaster.string"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_string_results.csv
    touch ${prefix}_alabaster_string_output.rds
    echo "BIOC_ALABASTER_STRING:" > versions.yml
    echo "    alabaster_string: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_STRING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_STRING(ch_input)

    emit:
    results  = BIOC_ALABASTER_STRING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_STRING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_STRING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_STRING.out.versions  // channel: path(versions.yml)
}
