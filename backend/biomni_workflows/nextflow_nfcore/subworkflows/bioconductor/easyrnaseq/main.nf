#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: easyRNASeq
// Calculates the coverage of high-throughput short-reads against a genome of reference and summarizes 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/easyRNASeq/inst/doc/simpleRNASeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("easyRNASeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EASYRNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-easyrnaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-easyrnaseq:2.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-easyrnaseq:2.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_easyrnaseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_easyrnaseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_easyrnaseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotParam)
    library(BamParam)
    library(RnaSeqParam)
    library(jsonlite)

    # --- vignette Data [] ---
    # Key functions: vignetteData
    vDir <- vignetteData()
    # --- Annot Param [] ---
    # Key functions: AnnotParam
    annotParam <- AnnotParam(
    # --- create synthetic transcripts [] ---
    # Key functions: createSyntheticTranscripts
    annotParam <- createSyntheticTranscripts(annotParam,verbose=FALSE)
    # --- create synthetic transcripts as gI [] ---
    # Key functions: createSyntheticTranscripts
    gI <- createSyntheticTranscripts(
    # --- data unit test [] ---
    # Key functions: dir
    THIS IS A subset of the data (chr 19 only) used to speed up
    data(RobinsonDelhomme2014)
    lapply(RobinsonDelhomme2014[1:6,"Filename"],function(f){
    # --- Bam Param [] ---
    # Key functions: BamParam
    bamParam <- BamParam(paired = TRUE,
    # --- get Bam File List [] ---
    # Key functions: getBamFileList
    bamFiles <- getBamFileList(dir(".","*\\.bam$"),
    dir(".","*\\.bai$"))
    # --- Rna Seq Param [] ---
    # Key functions: RnaSeqParam
    rnaSeqParam <- RnaSeqParam(annotParam = annotParam,
    # --- simple R N A Seq [] ---
    # Key functions: simpleRNASeq
    sexp1 <- simpleRNASeq(bamFiles=bamFiles,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_easyrnaseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_easyrnaseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_easyrnaseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EASYRNASEQ:", paste0("    easyrnaseq: ", packageVersion("easyRNASeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_easyrnaseq_results.csv
    touch ${prefix}_easyrnaseq_output.rds
    echo "BIOC_EASYRNASEQ:" > versions.yml
    echo "    easyrnaseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EASYRNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EASYRNASEQ(ch_input)

    emit:
    results  = BIOC_EASYRNASEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EASYRNASEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EASYRNASEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EASYRNASEQ.out.versions  // channel: path(versions.yml)
}
