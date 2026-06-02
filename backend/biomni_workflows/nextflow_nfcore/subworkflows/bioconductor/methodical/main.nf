#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methodical
// DNA methylation is generally considered to be associated with transcriptional silencing. However, co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methodical/inst/doc/calculating_methylation_transcription_correlations.R
// Upstream  : AnnotationHub
// Downstream: none
//
// Install: BiocManager::install("methodical")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHODICAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methodical"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methodical:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methodical:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methodical_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methodical_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methodical_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(DESeqDataSetFromMatrix)
    library(jsonlite)

    # --- Download Meth Dataset [] ---
    # Key functions: download_meth_dataset, download_rnaseq_dataset, frame, fread
    ---------------------------------------------------------------------
    # Download mcrpc_wgbs_hg38 from TumourMethDatasets.
    mcrpc_wgbs_hg38_chr11 <- TumourMethData::download_meth_dataset(dataset = "mcrpc_wgbs_hg38_chr11")
    # Download transcript counts
    mcrpc_transcript_counts_file <- TumourMethData::download_rnaseq_dataset(dataset = "mcrpc_wgbs_hg38_chr11")
    # --- Annotationhub [] ---
    # Key functions: AnnotationHub, seqnames, resize, expand_granges
    ---------------------------------------------------------------------
    # Download Gencode annotation
    library(AnnotationHub)
    transcript_annotation <- AnnotationHub()[["AH75119"]]
    # Import the Gencode annotation and subset for transcript annotation for non-mitochondrial protein-coding genes
    # --- Deseqdatasetfrommatrix [] ---
    # Key functions: DESeqDataSetFromMatrix, frame, estimateSizeFactors, counts
    ---------------------------------------------------------------------
    # Subset mcrpc_transcript_counts for protein-coding transcripts
    mcrpc_transcript_counts <- mcrpc_transcript_counts[transcript_tss_chr11$ID, ]
    # Create a DESeqDataSet from Kallisto counts.
    # --- Intersect [] ---
    # Key functions: intersect, bpparam, time, calculateMethSiteTranscriptCors
    ---------------------------------------------------------------------
    # Find samples with both WGBS and RNA-seq count data
    common_mcprc_samples <- intersect(names(mcrpc_transcript_counts), colnames(mcrpc_wgbs_hg38_chr11))
    # Create a BPPARAM class
    BPPARAM = BiocParallel::bpparam()
    # --- Head [] ---
    # Key functions: attributes
    ---------------------------------------------------------------------
    # Extract correlation results for ENST00000398606 transcript
    gstp1_cpg_meth_transcript_cors <- transcript_cpg_meth_cors_mcrpc_samples_5kb[["ENST00000398606"]]
    # Examine first few rows of the results
    head(gstp1_cpg_meth_transcript_cors)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methodical_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methodical_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methodical_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHODICAL:", paste0("    methodical: ", packageVersion("methodical"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methodical_results.csv
    touch ${prefix}_methodical_output.rds
    echo "BIOC_METHODICAL:" > versions.yml
    echo "    methodical: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHODICAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHODICAL(ch_input)

    emit:
    results  = BIOC_METHODICAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHODICAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHODICAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHODICAL.out.versions  // channel: path(versions.yml)
}
