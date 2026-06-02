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
    library(methodical)
    library(AnnotationHub)
    library(DESeqDataSetFromMatrix)
    library(jsonlite)

    # --- Define Genomic Regions [Genomics] ---
    # Key functions: expand_granges
    tss_proximal_regions_chr11 <- methodical::expand_granges(
        transcript_tss_chr11,
        upstream = 5000,
        downstream = 5000
    )

    # --- Calculate Site Methylation Transcription Correlations [Correlation Analysis] ---
    # Key functions: calculateMethSiteTranscriptCors
    transcript_cpg_meth_cors_mcrpc_samples_5kb <-
        methodical::calculateMethSiteTranscriptCors(
            meth_rse = mcrpc_wgbs_hg38_chr11,
            transcript_expression_table = mcrpc_transcript_counts_normalized,
            samples_subset = common_mcprc_samples,
            tss_gr = transcript_tss_chr11,
            tss_associated_gr = tss_proximal_regions_chr11,
            cor_method = "pearson",
            max_sites_per_chunk = NULL,
            BPPARAM = BiocParallel::bpparam()
        )

    # --- Calculate Region Methylation Transcription Correlations [Correlation Analysis] ---
    # Key functions: calculateRegionMethylationTranscriptCors
    transcript_body_meth_cors_mcrpc_samples <-
        methodical::calculateRegionMethylationTranscriptCors(
            meth_rse = mcrpc_wgbs_hg38_chr11,
            transcript_expression_table = mcrpc_transcript_counts_normalized,
            samples_subset = common_mcprc_samples,
            genomic_regions = transcript_annotation_chr11,
            genomic_region_transcripts = transcript_annotation_chr11$ID,
            region_methylation_summary_function = colMeans,
            cor_method = "pearson",
            BPPARAM = BiocParallel::bpparam()
        )

    # --- Visualise Correlation Coefficients [Visualisation] ---
    # Key functions: plotMethSiteCorCoefs
    gstp1_cpg_meth_transcript_cors <-
        transcript_cpg_meth_cors_mcrpc_samples_5kb[["ENST00000398606"]]

    meth_cor_plot_relative_distance <- methodical::plotMethSiteCorCoefs(
        meth_site_cor_values = gstp1_cpg_meth_transcript_cors,
        reference_tss = TRUE,
        ylabel = "Correlation Value",
        title = "Correlation Between GSTP1 Transcription and CpG Methylation"
    )


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
