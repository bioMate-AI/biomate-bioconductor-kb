#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AWFisher
// Implementation of the adaptively weighted fisher's method, including fast p-value computing, variabi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AWFisher/inst/doc/AWFisher.R
// Upstream  : limma, tightClust
// Downstream: none
//
// Install: BiocManager::install("AWFisher")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AWFISHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-awfisher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-awfisher:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-awfisher:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_awfisher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_awfisher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_awfisher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AWFisher_pvalue)
    library(jsonlite)

    # --- Awfisher Pvalue [] ---
    # Key functions: AWFisher_pvalue, adjust
    ---------------------------------------------------------------------
    res <- AWFisher_pvalue(pmatrix) ## Perform AW Fisehr meta analysis
    qvalue <- p.adjust(res$pvalue, "BH") ## Perform BH correction to control for multiple comparison.
    sum(qvalue < 0.05) ## Differentially expressed genes with FDR 5%
    head(res$weights) ## Show the AW weight of the first few genes
    # --- Clust [] ---
    # Key functions: clust
    ---------------------------------------------------------------------
    library(tightClust) ## load tightClust package
    tightClustResult <- tight.clust(result$dissimilarity, target=4, k.min=15, random.seed=15213)
    clusterMembership <- tightClustResult$cluster

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_awfisher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_awfisher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_awfisher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AWFISHER:", paste0("    awfisher: ", packageVersion("AWFisher"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_awfisher_results.csv
    touch ${prefix}_awfisher_output.rds
    echo "BIOC_AWFISHER:" > versions.yml
    echo "    awfisher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AWFISHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AWFISHER(ch_input)

    emit:
    results  = BIOC_AWFISHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AWFISHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AWFISHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AWFISHER.out.versions  // channel: path(versions.yml)
}
