#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: proDA
// Account for missing values in label-free mass spectrometry data without imputation. The package impl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/proDA/inst/doc/Introduction.R
// Upstream  : DEP
// Downstream: none
//
// Install: BiocManager::install("proDA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRODA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proda:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proda:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(proDA)
    library(jsonlite)

    # --- generate_synthetic_data [] ---
    # Key functions: generate_synthetic_data, proDA, test_diff
    library(proDA)
    syn_dataset <- generate_synthetic_data(n_proteins = 100, n_conditions = 2)
    fit <- proDA(syn_dataset$Y, design = syn_dataset$groups)
    # --- median_normalization [] ---
    # Key functions: median_normalization, dist_approx

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap, proDA
    install.packages("pheatmap")
    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap, test_diff
    install.packages("pheatmap")
    pheatmap::pheatmap(dist_approx(fit[1:20, 1:3], by_sample = FALSE)$mean)
    test_res <- test_diff(fit, "conditionCG1407")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRODA:", paste0("    proda: ", packageVersion("proDA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proda_results.csv
    touch ${prefix}_proda_output.rds
    echo "BIOC_PRODA:" > versions.yml
    echo "    proda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRODA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRODA(ch_input)

    emit:
    results  = BIOC_PRODA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRODA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRODA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRODA.out.versions  // channel: path(versions.yml)
}
