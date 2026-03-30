#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scoreInvHap
// scoreInvHap can get the samples' inversion status of known inversions. scoreInvHap uses SNP data as 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scoreInvHap/inst/doc/scoreInvHap.R
// Upstream  : snpStats, VariantAnnotation
// Downstream: none
//
// Install: BiocManager::install("scoreInvHap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCOREINVHAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scoreinvhap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scoreinvhap:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scoreinvhap:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scoreinvhap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scoreinvhap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scoreinvhap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scoreInvHap)
    library(jsonlite)

    # --- Load SNPs [] ---
    # Key functions: readVcf, checkSNPs
    library(VariantAnnotation)
    vcf_file <- system.file("extdata", "example.vcf", package = "scoreInvHap")
    vcf <- readVcf(vcf_file, "hg19")
    # --- score Inv Hap [] ---
    # Key functions: scoreInvHap
    res <- scoreInvHap(SNPlist = vcf, inv = "inv7_005")
    # --- scoreInvHap scores [] ---
    # Key functions: plotScores, plotCallRate
    head(maxscores(res))
    head(diffscores(res))
    plotScores(res, pch = 16, main = "QC based on scores")
    # --- score Inv Hap [] ---
    # Key functions: scoreInvHap
    res_imp <- scoreInvHap(SNPlist = vcf, inv = "inv7_005", probs = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scoreinvhap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scoreinvhap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scoreinvhap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCOREINVHAP:", paste0("    scoreinvhap: ", packageVersion("scoreInvHap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scoreinvhap_results.csv
    touch ${prefix}_scoreinvhap_output.rds
    echo "BIOC_SCOREINVHAP:" > versions.yml
    echo "    scoreinvhap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCOREINVHAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCOREINVHAP(ch_input)

    emit:
    results  = BIOC_SCOREINVHAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCOREINVHAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCOREINVHAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCOREINVHAP.out.versions  // channel: path(versions.yml)
}
