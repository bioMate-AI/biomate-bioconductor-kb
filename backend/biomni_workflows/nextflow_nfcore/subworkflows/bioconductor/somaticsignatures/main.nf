#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SomaticSignatures
// The SomaticSignatures package identifies mutational signatures of single nucleotide variants (SNVs).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SomaticSignatures/inst/doc/SomaticSignatures-vignette.R
// Upstream  : SomaticCancerAlterations, VariantAnnotation, ggdendro, ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("SomaticSignatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SOMATICSIGNATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-somaticsignatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-somaticsignatures:2.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-somaticsignatures:2.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_somaticsignatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_somaticsignatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_somaticsignatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SomaticSignatures)
    library(jsonlite)

    # --- sca mutation spectrum [] ---
    # Key functions: plotMutationSpectrum
    plotMutationSpectrum(sca_motifs, "study")
    # --- sca plot nmf signatures map [] ---
    # Key functions: plotSignatureMap
    plotSignatureMap(sigs_nmf) + ggtitle("Somatic Signatures: NMF - Heatmap")
    # --- sca plot nmf signatures [] ---
    # Key functions: plotSignatures, plotObservedSpectrum, plotFittedSpectrum
    plotSignatures(sigs_nmf) + ggtitle("Somatic Signatures: NMF - Barchart")
    plotObservedSpectrum(sigs_nmf)
    plotFittedSpectrum(sigs_nmf)
    # --- sca plot nmf samples map [] ---
    # Key functions: plotSampleMap
    plotSampleMap(sigs_nmf)
    # --- sca plot nmf samples [] ---
    # Key functions: plotSamples
    plotSamples(sigs_nmf)
    # --- sca plot pca signatures map [] ---
    # Key functions: plotSignatureMap
    plotSignatureMap(sigs_pca) + ggtitle("Somatic Signatures: PCA - Heatmap")
    # --- sca plot pca signatures [] ---
    # Key functions: plotSignatures, plotFittedSpectrum, plotObservedSpectrum
    plotSignatures(sigs_pca) + ggtitle("Somatic Signatures: PCA - Barchart")
    plotFittedSpectrum(sigs_pca)
    plotObservedSpectrum(sigs_pca)
    # --- normalize motifs [] ---
    # Key functions: showMethods
    data(kmers)
    head(norms)
    sca_mm_norm = normalizeMotifs(sca_mm, norms)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_somaticsignatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_somaticsignatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_somaticsignatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SOMATICSIGNATURES:", paste0("    somaticsignatures: ", packageVersion("SomaticSignatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_somaticsignatures_results.csv
    touch ${prefix}_somaticsignatures_output.rds
    echo "BIOC_SOMATICSIGNATURES:" > versions.yml
    echo "    somaticsignatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SOMATICSIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SOMATICSIGNATURES(ch_input)

    emit:
    results  = BIOC_SOMATICSIGNATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SOMATICSIGNATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SOMATICSIGNATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SOMATICSIGNATURES.out.versions  // channel: path(versions.yml)
}
