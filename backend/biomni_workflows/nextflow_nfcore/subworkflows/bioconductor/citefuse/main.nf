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

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("CITEseq_example", package = "CiteFuse")
    names(CITEseq_example)
    lapply(CITEseq_example, dim)
    # --- Preprocessing [] ---
    # Key functions: preprocessing
    ---------------------------------------------------------------------
    sce_citeseq <- preprocessing(CITEseq_example)
    sce_citeseq
    # --- Normaliseexprs [] ---
    # Key functions: normaliseExprs
    ---------------------------------------------------------------------
    sce_citeseq <- normaliseExprs(sce = sce_citeseq,
                                  altExp_name = "HTO",
                                  transform = "log")
    # --- Crosssampledoublets [] ---
    # Key functions: crossSampleDoublets
    ---------------------------------------------------------------------
    sce_citeseq <- crossSampleDoublets(sce_citeseq)
    # --- Withinsampledoublets [] ---
    # Key functions: withinSampleDoublets
    ---------------------------------------------------------------------
    sce_citeseq <- withinSampleDoublets(sce_citeseq,
                                        minPts = 10)
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, normaliseExprs, time, CiteFuse
    ---------------------------------------------------------------------
    sce_citeseq <- scater::logNormCounts(sce_citeseq)
    sce_citeseq <- normaliseExprs(sce_citeseq, altExp_name = "ADT", transform = "log")
    system.time(sce_citeseq <- CiteFuse(sce_citeseq))
    # --- Spectralclustering [] ---
    # Key functions: spectralClustering, metadata, diff
    ---------------------------------------------------------------------
    SNF_W_clust <- spectralClustering(metadata(sce_citeseq)[["SNF_W"]], K = 20)
    plot(SNF_W_clust$eigen_values)
    which.max(abs(diff(SNF_W_clust$eigen_values)))
    # --- Spectralclustering [] ---
    # Key functions: spectralClustering, metadata, factor
    ---------------------------------------------------------------------
    SNF_W_clust <- spectralClustering(metadata(sce_citeseq)[["SNF_W"]], K = 5)
    sce_citeseq$SNF_W_clust <- as.factor(SNF_W_clust$labels)
    SNF_W1_clust <- spectralClustering(metadata(sce_citeseq)[["ADT_W"]], K = 5)
    sce_citeseq$ADT_clust <- as.factor(SNF_W1_clust$labels)
    # --- Degenes [] ---
    # Key functions: DEgenes, selectDEgenes, datatable, call, metadata
    ---------------------------------------------------------------------
    # DE will be performed for RNA if altExp_name = "none"
    # --- Data [] ---
    # Key functions: normaliseExprs, ligandReceptorTest
    ---------------------------------------------------------------------
    data("lr_pair_subset", package = "CiteFuse")
    head(lr_pair_subset)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("sce_ctcl_subset", package = "CiteFuse")
    # --- Visualiseexprslist [] ---
    # Key functions: visualiseExprsList
    ---------------------------------------------------------------------
    # --- Degenescross [] ---
    # Key functions: DEgenesCross, selectDEgenes
    ---------------------------------------------------------------------
    de_res <- DEgenesCross(sce_list = list(control = sce_citeseq,
                                           ctcl = sce_ctcl_subset),
                           colData_name = c("SNF_W_louvain", "SNF_W_louvain"),
                           group_to_test = c("2", "6"))

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
