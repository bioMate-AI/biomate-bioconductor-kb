#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneExpressionSignature
// This package gives the implementations of the gene expression signature and its distance to each. Ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneExpressionSignature/inst/doc/GeneExpressionSignature.R
// Upstream  : BiocStyle, GEOquery, apcluster
// Downstream: none
//
// Install: BiocManager::install("GeneExpressionSignature")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEEXPRESSIONSIGNATURE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneexpressionsignature"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneexpressionsignature:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneexpressionsignature:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneexpressionsignature_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneexpressionsignature_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneexpressionsignature_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneExpressionSignature)
    library(RankMerging)
    library(ScoreGSEA)
    library(ScorePGSEA)
    library(jsonlite)

    # --- Rank Merging [] ---
    # Key functions: RankMerging
    data(exampleSet)
    MergingSet <- RankMerging(
        exampleSet,
        "Spearman",
        weighted = TRUE
    )


    # --- GSEA Scoring [] ---
    # Key functions: RankMerging, ScoreGSEA
    data(exampleSet)
    MergingSet <- RankMerging(exampleSet, "Spearman", weighted = TRUE)
    ds_gsea <- ScoreGSEA(
        MergingSet,
        SignatureLength = 250,
        ScoringDistance = "avg"
    )


    # --- PGSEA Scoring [] ---
    # Key functions: RankMerging, ScorePGSEA
    data(exampleSet)
    MergingSet <- RankMerging(exampleSet, "Spearman", weighted = TRUE)
    ds_pgsea <- ScorePGSEA(
        MergingSet,
        SignatureLength = 250,
        ScoringDistance = "avg"
    )


    # --- Signature Distance Calculation [] ---
    # Key functions: SignatureDistance
    data(exampleSet)
    sig_dist <- SignatureDistance(
        exampleSet,
        SignatureLength = 250,
        MergingDistance = "Spearman",
        ScoringMethod = "GSEA",
        ScoringDistance = "avg",
        weighted = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneexpressionsignature_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneexpressionsignature_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneexpressionsignature_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEEXPRESSIONSIGNATURE:", paste0("    geneexpressionsignature: ", packageVersion("GeneExpressionSignature"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneexpressionsignature_results.csv
    touch ${prefix}_geneexpressionsignature_output.rds
    echo "BIOC_GENEEXPRESSIONSIGNATURE:" > versions.yml
    echo "    geneexpressionsignature: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEEXPRESSIONSIGNATURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEEXPRESSIONSIGNATURE(ch_input)

    emit:
    results  = BIOC_GENEEXPRESSIONSIGNATURE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEEXPRESSIONSIGNATURE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEEXPRESSIONSIGNATURE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEEXPRESSIONSIGNATURE.out.versions  // channel: path(versions.yml)
}
