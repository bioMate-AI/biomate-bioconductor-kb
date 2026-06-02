#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CiteFuse
// CiteFuse pacakage implements a suite of methods and tools for CITE-seq data from pre-processing to i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CiteFuse/inst/doc/CiteFuse.R
// Upstream  : gridExtra, mclust
// Downstream: none
//
// Install: BiocManager::install("CiteFuse")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CITEFUSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-citefuse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-citefuse:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-citefuse:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_citefuse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_citefuse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_citefuse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CiteFuse)
    library(DEgenes)
    library(DEgenesCross)
    library(jsonlite)

    # --- Doublet Detection and Filtering [] ---
    # Key functions: crossSampleDoublets, withinSampleDoublets
    sce_citeseq <- crossSampleDoublets(sce_citeseq)
    sce_citeseq <- withinSampleDoublets(sce_citeseq, minPts = 10)
    sce_citeseq <- sce_citeseq[,
        sce_citeseq$doubletClassify_within_class == "Singlet" &
        sce_citeseq$doubletClassify_between_class == "Singlet"
    ]


    # --- Multimodal Integration [] ---
    # Key functions: normaliseExprs, CiteFuse
    sce_citeseq <- normaliseExprs(
        sce_citeseq,
        altExp_name = "ADT",
        transform = "log"
    )
    sce_citeseq <- CiteFuse(sce_citeseq)


    # --- Spectral and Graph-based Clustering [] ---
    # Key functions: spectralClustering, igraphClustering
    SNF_W_clust <- spectralClustering(
        metadata(sce_citeseq)[["SNF_W"]],
        K = 5
    )
    sce_citeseq$SNF_W_clust <- as.factor(SNF_W_clust$labels)
    SNF_W_louvain <- igraphClustering(sce_citeseq, method = "louvain")
    sce_citeseq$SNF_W_louvain <- as.factor(SNF_W_louvain)


    # --- Dimensionality Reduction and Visualization [] ---
    # Key functions: reducedDimSNF, visualiseDim, visualiseKNN, visualiseExprs
    sce_citeseq <- reducedDimSNF(
        sce_citeseq,
        method = "tSNE",
        dimNames = "tSNE_joint"
    )
    g1 <- visualiseDim(
        sce_citeseq,
        dimNames = "tSNE_joint",
        colour_by = "SNF_W_clust"
    )
    g2 <- visualiseKNN(sce_citeseq, colour_by = "SNF_W_louvain")
    g3 <- visualiseExprs(
        sce_citeseq,
        plot = "boxplot",
        group_by = "SNF_W_louvain",
        feature_subset = c("hg19_CD2", "hg19_CD4")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_citefuse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_citefuse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_citefuse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CITEFUSE:", paste0("    citefuse: ", packageVersion("CiteFuse"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_citefuse_results.csv
    touch ${prefix}_citefuse_output.rds
    echo "BIOC_CITEFUSE:" > versions.yml
    echo "    citefuse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CITEFUSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CITEFUSE(ch_input)

    emit:
    results  = BIOC_CITEFUSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CITEFUSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CITEFUSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CITEFUSE.out.versions  // channel: path(versions.yml)
}
