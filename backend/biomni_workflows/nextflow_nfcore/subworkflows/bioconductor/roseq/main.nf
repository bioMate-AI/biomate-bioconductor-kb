#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ROSeq
// ROSeq - A rank based approach to modeling gene expression with filtered and normalized read count ma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ROSeq/inst/doc/ROSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ROSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-roseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-roseq:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-roseq:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_roseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_roseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_roseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ROSeq)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
        collapse = TRUE,
        comment = "#>"
    )

    # --- Data [] ---
    # Key functions: roseq
    samples<-list()
    samples$count<-ROSeq::L_Tung_single$NA19098_NA19101_count
    samples$group<-ROSeq::L_Tung_single$NA19098_NA19101_group
    samples$count[1:5,1:5]

    # --- Preprocesing [] ---
    # Key functions: function, colSums, voom, TMMnormalization
    gene_names<-rownames(samples$count)
    samples$count<-apply(samples$count,2,function(x) as.numeric(x))
    rownames(samples$count)<-gene_names
    samples$count<-samples$count[,colSums(samples$count> 0) > 2000]
    gkeep<-apply(samples$count,1,function(x) sum(x>2)>=3)
    samples$count<-samples$count[gkeep,]
    samples$count<-limma::voom(ROSeq::TMMnormalization(samples$count))

    # --- Main [] ---
    # Key functions: ROSeq
    output<-ROSeq(countData=samples$count$E, condition = samples$group, numCores=1)

    # --- Output [] ---
    # Key functions: roseq
    output[1:5,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_roseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_roseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_roseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ROSEQ:", paste0("    roseq: ", packageVersion("ROSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_roseq_results.csv
    touch ${prefix}_roseq_output.rds
    echo "BIOC_ROSEQ:" > versions.yml
    echo "    roseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ROSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ROSEQ(ch_input)

    emit:
    results  = BIOC_ROSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ROSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ROSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ROSEQ.out.versions  // channel: path(versions.yml)
}
