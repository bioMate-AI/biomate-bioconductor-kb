#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phenomis
// The 'phenomis' package provides methods to perform post-processing (i.e. quality control and normali
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phenomis/inst/doc/phenomis-vignette.R
// Upstream  : MultiAssayExperiment, MultiDataSet, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("phenomis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOMIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenomis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenomis:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenomis:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenomis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenomis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenomis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(phenomis)
    library(ExpressionSet)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Signal Correction and Transformation [] ---
    # Key functions: correcting, transforming
    sacurine.se <- correcting(
        sacurine.se,
        reference.vc = "pool",
        report.c = "none"
    )
    sacurine.se <- transforming(
        sacurine.se,
        method.vc = "log10"
    )


    # --- Statistical Hypothesis Testing [] ---
    # Key functions: hypotesting
    sacurine.se <- hypotesting(
        sacurine.se,
        test.c = "ttest",
        factor_names.vc = "gender",
        adjust.c = "BH",
        adjust_thresh.n = 0.05,
        report.c = "none"
    )


    # --- Clustering [] ---
    # Key functions: clustering
    sacurine.se <- clustering(
        sacurine.se,
        clusters.vi = c(5, 3)
    )
    clustered_data <- sacurine.se


    # --- Metabolite Annotation [] ---
    # Key functions: annotating
    sacurine.se <- annotating(
        sacurine.se,
        database.c = "local.ms",
        param.ls = list(
            query.type = "mz",
            query.col = "mass_to_charge",
            ms.mode = "neg",
            mz.tol = 5,
            local.ms.db = msdbDF
        ),
        report.c = "none"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenomis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenomis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenomis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENOMIS:", paste0("    phenomis: ", packageVersion("phenomis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenomis_results.csv
    touch ${prefix}_phenomis_output.rds
    echo "BIOC_PHENOMIS:" > versions.yml
    echo "    phenomis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENOMIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENOMIS(ch_input)

    emit:
    results  = BIOC_PHENOMIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENOMIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENOMIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENOMIS.out.versions  // channel: path(versions.yml)
}
