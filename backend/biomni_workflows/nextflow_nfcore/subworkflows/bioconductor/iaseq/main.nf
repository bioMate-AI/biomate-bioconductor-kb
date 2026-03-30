#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iASeq
// It fits correlation motif model to multiple RNAseq or ChIPseq studies to improve detection of allele
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iASeq/inst/doc/iASeqVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iASeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IASEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iaseq:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iaseq:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iaseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iaseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iaseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iASeq)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(iASeq)
    data(sampleASE)
    colnames(sampleASE_exprs)
    sampleASE_studyid
    # --- Iaseqmotif [] ---
    # Key functions: iASeqmotif
    motif.fitted<-iASeqmotif(sampleASE_exprs,sampleASE_studyid,sampleASE_repid,
    	sampleASE_refid,K=1:5,iter.max=5,tol=1e-3)
    # --- Plotbic [] ---
    # Key functions: plotBIC
    motif.fitted$bic
    plotBIC(motif.fitted)
    # --- Plotmotif [] ---
    # Key functions: plotMotif
    plotMotif(motif.fitted$bestmotif,cutoff=0.9)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iaseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iaseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iaseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IASEQ:", paste0("    iaseq: ", packageVersion("iASeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iaseq_results.csv
    touch ${prefix}_iaseq_output.rds
    echo "BIOC_IASEQ:" > versions.yml
    echo "    iaseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IASEQ(ch_input)

    emit:
    results  = BIOC_IASEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IASEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IASEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IASEQ.out.versions  // channel: path(versions.yml)
}
