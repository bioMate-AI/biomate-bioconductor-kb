#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: normr
// Robust normalization and difference calling procedures for ChIP-seq and alike data. Read counts are 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/normr/inst/doc/normr.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("normr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-normr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-normr:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-normr:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_normr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_normr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_normr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(normr)
    library(jsonlite)

    # --- Getenrichment [] ---
    # Key functions: getEnrichment, rowSums, call, getCounts
    ---------------------------------------------------------------------
    #background normalized enrichment
    k4me3Enr <- getEnrichment(k4me3Fit)
    #restrict to regions with non-zero counts
    idx <- which(rowSums(do.call(cbind, getCounts(k4me3Fit))) != 0)
    # --- Getranges [] ---
    # Key functions: getRanges, na
    ---------------------------------------------------------------------
    k4me3Ranges <- getRanges(k4me3Fit)[!is.na(k4me3Classes)]
    #Alternatively you can extract ranges without storing the class vector
    k4me3Ranges <- getRanges(k4me3Fit, fdr = 0.05)
    #as expected we get 587 regions
    # --- Getranges [] ---
    # Key functions: getRanges, overlapOdds, countOverlaps
    ---------------------------------------------------------------------
    #Overlap of H3K36me3 with H3K4me3
    k36me3Ranges <- getRanges(k36me3Fit, fdr = 0.05)
    overlapOdds(k36me3Ranges, k4me3Ranges)
    #Overlap of H3K36me3 with H3K4me3 at promoter regions
    # --- Overlapodds [] ---
    # Key functions: overlapOdds, promoters
    ---------------------------------------------------------------------
    #Overlap of H3K36me3 in genes
    overlapOdds(k36me3Ranges, genes)
    #Overlap of H3K36me3 with promoters
    overlapOdds(k36me3Ranges, promoters(genes, 1500, 1500))
    # --- Enrichr [] ---
    # Key functions: enrichR
    ---------------------------------------------------------------------
    #Fit only on promoters
    promotersFit <- enrichR(treatment = k4me3Bamfile, control = inputBamfile,
                            genome = promoters, verbose = FALSE)
    summary(promotersFit)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_normr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_normr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_normr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NORMR:", paste0("    normr: ", packageVersion("normr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normr_results.csv
    touch ${prefix}_normr_output.rds
    echo "BIOC_NORMR:" > versions.yml
    echo "    normr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NORMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NORMR(ch_input)

    emit:
    results  = BIOC_NORMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NORMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NORMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NORMR.out.versions  // channel: path(versions.yml)
}
