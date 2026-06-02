#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epiregulon
// Gene regulatory networks model the underlying gene regulation hierarchies that drive gene expression
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epiregulon/inst/doc/multiome.mae.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("epiregulon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIREGULON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epiregulon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epiregulon:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epiregulon:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epiregulon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epiregulon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epiregulon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epiregulon)
    library(jsonlite)

    # --- Regulon Construction [] ---
    # Key functions: addTFMotifInfo, getRegulon
    overlap <- addTFMotifInfo(
        grl = grl,
        p2g = p2g,
        peakMatrix = PeakMatrix
    )
    regulon <- getRegulon(
        p2g = p2g,
        overlap = overlap,
        aggregate = FALSE
    )


    # --- Network Pruning [] ---
    # Key functions: pruneRegulon
    pruned.regulon <- pruneRegulon(
        expMatrix = GeneExpressionMatrix,
        exp_assay = "normalizedCounts",
        peakMatrix = PeakMatrix,
        peak_assay = "counts",
        test = "chi.sq",
        regulon = regulon,
        clusters = GeneExpressionMatrix$Clusters,
        prune_value = "pval",
        regulon_cutoff = 0.05
    )


    # --- Regulon Weighting and Annotation [] ---
    # Key functions: addWeights, addMotifScore, addLogFC
    regulon.w <- addWeights(
        regulon = pruned.regulon,
        expMatrix = GeneExpressionMatrix,
        exp_assay = "normalizedCounts",
        peakMatrix = PeakMatrix,
        peak_assay = "counts",
        clusters = GeneExpressionMatrix$Clusters,
        method = "wilcox"
    )
    regulon.w <- addMotifScore(
        regulon = regulon.w,
        peaks = rowRanges(PeakMatrix),
        species = "human",
        genome = "hg38"
    )
    regulon.w <- addLogFC(
        regulon = regulon.w,
        clusters = GeneExpressionMatrix$hash_assignment,
        expMatrix = GeneExpressionMatrix,
        assay.type = "normalizedCounts",
        pval.type = "any",
        logFC_condition = c("HTO10_GATA6_UTR", "HTO2_GATA6_v2"),
        logFC_ref = "HTO5_NeonG_v2"
    )


    # --- Transcription Factor Activity Estimation [] ---
    # Key functions: calculateActivity
    score.combine <- calculateActivity(
        expMatrix = GeneExpressionMatrix,
        regulon = regulon.w,
        mode = "weight",
        method = "weightedMean",
        exp_assay = "normalizedCounts",
        normalize = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epiregulon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epiregulon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epiregulon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIREGULON:", paste0("    epiregulon: ", packageVersion("epiregulon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epiregulon_results.csv
    touch ${prefix}_epiregulon_output.rds
    echo "BIOC_EPIREGULON:" > versions.yml
    echo "    epiregulon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIREGULON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIREGULON(ch_input)

    emit:
    results  = BIOC_EPIREGULON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIREGULON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIREGULON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIREGULON.out.versions  // channel: path(versions.yml)
}
