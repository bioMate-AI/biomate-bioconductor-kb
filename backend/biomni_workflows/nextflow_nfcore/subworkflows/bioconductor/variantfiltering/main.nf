#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VariantFiltering
// Filter genetic variants using different criteria such as inheritance model, amino acid change conseq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VariantFiltering/inst/doc/usingVariantFiltering.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VariantFiltering")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTFILTERING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-variantfiltering"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-variantfiltering:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-variantfiltering:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_variantfiltering_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_variantfiltering_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_variantfiltering_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamViews)
    library(DataFrame)
    library(jsonlite)

    # --- Unrelatedindividuals [] ---
    # Key functions: unrelatedIndividuals
    ## uind <- unrelatedIndividuals(vfpar)
    # --- Displayedvariant [] ---
    # Key functions: path, samples, BamViews, DataFrame, bamFiles
    path2bams <- file.path(system.file("extdata", package="VariantFiltering"),
                           paste0(samples(uind), ".subset.bam"))
    bv <- BamViews(bamPaths=path2bams,
                   bamSamples=DataFrame(row.names=samples(uind)))
    bamFiles(uind) <- bv
    # --- Samples [] ---
    # Key functions: samples
    samples(uind)
    samples(uind) <- c("NA12891", "NA12892")
    uind
    uindSO2sam <- summary(uind, method="SOfull")
    uindSO2sam[uindSO2sam$Level == 6, ]
    # --- Resetsamples [] ---
    # Key functions: resetSamples
    uind <- resetSamples(uind)
    uind
    # --- Active [] ---
    # Key functions: active, filters
    active(filters(uind))
    # --- Change [] ---
    # Key functions: change, cutoffs, active, filters
    change(cutoffs(uind), "SOterms") <- "UTR_variant"
    active(filters(uind))["SOterms"] <- TRUE
    summary(uind)
    summary(uind, method="SOfull")
    # --- Function [] ---
    # Key functions: start, allVariants, filters, active
    startLost <- function(x) {
      mask <- start(allVariants(x, groupBy="nothing")$CDSLOC) == 1 &
              as.character(allVariants(x, groupBy="nothing")$REFCODON) == "ATG" &
              as.character(allVariants(x, groupBy="nothing")$VARCODON) != "ATG"
      mask
    # --- Active [] ---
    # Key functions: active, filters, cutoffs, change
    active(filters(uind)) <- FALSE
    active(filters(uind))["maxMAF"] <- TRUE
    cutoffs(uind)$maxMAF
    cutoffs(uind)$maxMAF$popmask
    cutoffs(uind)$maxMAF$maxvalue
    # --- Filteredvariants [] ---
    # Key functions: filteredVariants
    filteredVariants(uind)
    # --- Reportvariants [] ---
    # Key functions: reportVariants
    ## reportVariants(uind, type="csv", file="uind.csv")
    # --- Info [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_variantfiltering_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_variantfiltering_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_variantfiltering_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VARIANTFILTERING:", paste0("    variantfiltering: ", packageVersion("VariantFiltering"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variantfiltering_results.csv
    touch ${prefix}_variantfiltering_output.rds
    echo "BIOC_VARIANTFILTERING:" > versions.yml
    echo "    variantfiltering: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VARIANTFILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VARIANTFILTERING(ch_input)

    emit:
    results  = BIOC_VARIANTFILTERING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VARIANTFILTERING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VARIANTFILTERING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VARIANTFILTERING.out.versions  // channel: path(versions.yml)
}
