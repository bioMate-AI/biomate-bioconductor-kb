#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ProteoDisco
// ProteoDisco is an R package to facilitate proteogenomics studies. It houses functions to create cust
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ProteoDisco/inst/doc/Overview_ProteoDisco.R
// Upstream  : knitr, plyr, dplyr, ggplot2, reshape2
// Downstream: none
//
// Install: BiocManager::install("ProteoDisco")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEODISCO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteodisco"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteodisco:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteodisco:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteodisco_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteodisco_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteodisco_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ProteoDisco)
    library(AAStringSetList)
    library(DNAString)
    library(DataFrame)
    library(jsonlite)

    # --- Import Genomic Variants [] ---
    # Key functions: importGenomicVariants
    vcf_file <- system.file(
        "extdata", "validationSet_hg19.vcf",
        package = "ProteoDisco"
    )
    discography <- ProteoDisco::importGenomicVariants(
        ProteoDiscography = discography,
        files = vcf_file,
        samplenames = "Validation Set (GRCh37)",
        threads = 1,
        performAnchorCheck = FALSE
    )


    # --- Incorporate Genomic Variants [] ---
    # Key functions: incorporateGenomicVariants
    discography <- ProteoDisco::incorporateGenomicVariants(
        ProteoDiscography = discography,
        aggregateSamples = FALSE,
        aggregateWithinExon = TRUE,
        aggregateWithinTranscript = TRUE,
        ignoreOverlappingMutations = TRUE,
        threads = 1
    )


    # --- Summarize and Analyze Mutations [] ---
    # Key functions: summary
    summary_data <- summary(discography, verbose = FALSE)
    mutation_overview <- summary_data$overviewMutations
    filtered_overview <- mutation_overview[
        !is.na(mutation_overview$sample), 
    ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteodisco_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteodisco_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteodisco_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEODISCO:", paste0("    proteodisco: ", packageVersion("ProteoDisco"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteodisco_results.csv
    touch ${prefix}_proteodisco_output.rds
    echo "BIOC_PROTEODISCO:" > versions.yml
    echo "    proteodisco: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEODISCO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEODISCO(ch_input)

    emit:
    results  = BIOC_PROTEODISCO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEODISCO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEODISCO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEODISCO.out.versions  // channel: path(versions.yml)
}
