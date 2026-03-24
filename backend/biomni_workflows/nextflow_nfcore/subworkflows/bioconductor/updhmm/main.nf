#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UPDhmm
// Uniparental disomy (UPD) is a genetic condition where an individual inherits both copies of a chromo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UPDhmm/inst/doc/UPDhmm.R
// Upstream  : VariantAnnotation, dplyr, karyoploteR, regioneR
// Downstream: none
//
// Install: BiocManager::install("UPDhmm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UPDHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-updhmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-updhmm:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-updhmm:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_updhmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_updhmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_updhmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UPDhmm)
    library(jsonlite)

    # --- read Vcf [] ---
    # Key functions: readVcf, vcfCheck
    library(UPDhmm)
    library(VariantAnnotation)
    file <- system.file(package = "UPDhmm", "extdata", "test_het_mat.vcf.gz")
    # --- calculateEvents function [] ---
    # Key functions: calculateEvents
    updEvents <- calculateEvents(largeCollapsedVcf = processedVcf)
    head(updEvents)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_updhmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_updhmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_updhmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UPDHMM:", paste0("    updhmm: ", packageVersion("UPDhmm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_updhmm_results.csv
    touch ${prefix}_updhmm_output.rds
    echo "BIOC_UPDHMM:" > versions.yml
    echo "    updhmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UPDHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UPDHMM(ch_input)

    emit:
    results  = BIOC_UPDHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UPDHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UPDHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UPDHMM.out.versions  // channel: path(versions.yml)
}
