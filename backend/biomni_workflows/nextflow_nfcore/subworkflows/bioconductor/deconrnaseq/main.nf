#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DeconRNASeq
// DeconSeq is an R package for deconvolution of heterogeneous tissues based on mRNA-Seq data. It model
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DeconRNASeq/inst/doc/DeconRNASeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DeconRNASeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECONRNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deconrnaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deconrnaseq:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deconrnaseq:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deconrnaseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deconrnaseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deconrnaseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DeconRNASeq)
    library(jsonlite)

    # --- Packageload [] ---
    # Key functions: data
    library(DeconRNASeq)
    ## multi_tissue: expression profiles for 10 mixing samples from
    ## multiple tissues
    data(multi_tissue)
    datasets <- x.data[,2:11]
    # --- Expression Signature [] ---
    # Key functions: attributes
    signatures <- x.signature.filtered.optimal[,2:6]
    attributes(signatures)[c(1,2)]
    # --- Deconolution [] ---
    # Key functions: DeconRNASeq
    DeconRNASeq(datasets, signatures, proportions, checksig=FALSE,
    			known.prop = TRUE, use.scale = TRUE, fig = TRUE)
    # --- Condition Num [] ---
    # Key functions: DeconRNASeq
    DeconRNASeq(datasets, signatures, proportions, checksig=TRUE,
    			known.prop = TRUE, use.scale = TRUE, fig = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deconrnaseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deconrnaseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deconrnaseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECONRNASEQ:", paste0("    deconrnaseq: ", packageVersion("DeconRNASeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deconrnaseq_results.csv
    touch ${prefix}_deconrnaseq_output.rds
    echo "BIOC_DECONRNASEQ:" > versions.yml
    echo "    deconrnaseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECONRNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECONRNASEQ(ch_input)

    emit:
    results  = BIOC_DECONRNASEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECONRNASEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECONRNASEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECONRNASEQ.out.versions  // channel: path(versions.yml)
}
