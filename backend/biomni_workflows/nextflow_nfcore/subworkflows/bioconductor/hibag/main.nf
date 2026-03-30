#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HIBAG
// Imputes HLA classical alleles using GWAS SNP data, and it relies on a training set of HLA and SNP ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HIBAG/inst/doc/HIBAG.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("HIBAG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIBAG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hibag"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hibag:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hibag:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hibag_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hibag_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hibag_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HIBAG)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: hlaAllele, hlaSplitAllele
    ---------------------------------------------------------------------------------------------------
    library(HIBAG)
    # load HLA types and SNP genotypes in the package
    data(HLA_Type_Table, package="HIBAG")
    data(HapMap_CEU_Geno, package="HIBAG")
    # --- Summary [] ---
    # Key functions: hlaPredict, hlaCompareAllele
    ---------------------------------------------------------------------------------------------------
    summary(model)
    # validation
    pred <- hlaPredict(model, test.geno)
    summary(pred)
    # --- Hlareport [] ---
    # Key functions: hlaReport
    ---------------------------------------------------------------------------------------------------
    # report overall accuracy, per-allele sensitivity, specificity, etc
    hlaReport(comp, type="txt")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hibag_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hibag_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hibag_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIBAG:", paste0("    hibag: ", packageVersion("HIBAG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hibag_results.csv
    touch ${prefix}_hibag_output.rds
    echo "BIOC_HIBAG:" > versions.yml
    echo "    hibag: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIBAG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIBAG(ch_input)

    emit:
    results  = BIOC_HIBAG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIBAG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIBAG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIBAG.out.versions  // channel: path(versions.yml)
}
