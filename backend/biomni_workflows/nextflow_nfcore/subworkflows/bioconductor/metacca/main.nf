#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metaCCA
// metaCCA performs multivariate analysis of a single or multiple GWAS based on univariate regression c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metaCCA/inst/doc/metaCCA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("metaCCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METACCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metacca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metacca:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metacca:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metacca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metacca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metacca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metaCCA)
    library(jsonlite)

    # --- Mychunk1 [] ---
    # Key functions: data
    library(metaCCA)
    data( package = 'metaCCA' )
    # --- Mychunk4 [] ---
    # Key functions: estimateSyy
    # Estimating phenotypic correlation structure of study 1
    S_YY_study1 = estimateSyy( S_XY = S_XY_full_study1 )
    # Estimating phenotypic correlation structure of study 2
    S_YY_study2 = estimateSyy( S_XY = S_XY_full_study2 )
    # --- Mychunk6 [] ---
    # Key functions: metaCcaGp, metaCcaPlusGp
    # Default single-SNP--multi-trait meta-analysis of 2 studies
    # Association analysis according to metaCCA algorithm
    # --- Mychunk8 [] ---
    # Key functions: metaCcaGp
    # Single-SNP--multi-trait meta-analysis of 2 studies
    # and one selected SNP
    # metaCCA
    # --- Mychunk9 [] ---
    # Key functions: metaCcaPlusGp
    # metaCCA+
    # --- Mychunk11 [] ---
    # Key functions: metaCcaGp
    # Multi-SNP--multi-trait meta-analysis of 2 studies
    # metaCCA
    # --- Mychunk12 [] ---
    # Key functions: metaCcaPlusGp
    # metaCCA+
    # --- Mychunk14 [] ---
    # Key functions: metaCcaGp
    # metaCCA
    # --- Mychunk15 [] ---
    # Key functions: metaCcaPlusGp
    # metaCCA+

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metacca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metacca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metacca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METACCA:", paste0("    metacca: ", packageVersion("metaCCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metacca_results.csv
    touch ${prefix}_metacca_output.rds
    echo "BIOC_METACCA:" > versions.yml
    echo "    metacca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METACCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METACCA(ch_input)

    emit:
    results  = BIOC_METACCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METACCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METACCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METACCA.out.versions  // channel: path(versions.yml)
}
