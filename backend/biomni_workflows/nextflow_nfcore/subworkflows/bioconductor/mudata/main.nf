#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MuData
// Save MultiAssayExperiments to h5mu files supported by muon and mudata. Muon is a Python framework fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MuData/inst/doc/Blood-CITE-seq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MuData")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUDATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mudata"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mudata:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mudata:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mudata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mudata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mudata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(H5Fopen)
    library(H5Gopen)
    library(H5close)
    library(MultiAssayExperiment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("CITEseq_example", package = "CiteFuse")
    lapply(CITEseq_example, dim)
    # --- Preprocessing [] ---
    # Key functions: preprocessing
    ---------------------------------------------------------------------
    sce_citeseq <- preprocessing(CITEseq_example)
    sce_citeseq
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts
    ---------------------------------------------------------------------
    sce_citeseq <- scater::logNormCounts(sce_citeseq)
    sce_citeseq  # new assay: logcounts
    # --- Normaliseexprs [] ---
    # Key functions: normaliseExprs, altExp
    ---------------------------------------------------------------------
    sce_citeseq <- CiteFuse::normaliseExprs(
      sce_citeseq, altExp_name = "ADT", transform = "log"
    )
    altExp(sce_citeseq, "ADT")  # new assay: logcounts
    # --- Runpca [] ---
    # Key functions: runPCA
    ---------------------------------------------------------------------
    sce_citeseq <- scater::runPCA(
      sce_citeseq, exprs_values = "logcounts", ncomponents = 20
    )
    # --- Plotreduceddim [] ---
    # Key functions: plotReducedDim
    ---------------------------------------------------------------------
    scater::plotReducedDim(sce_citeseq, dimred = "PCA",
                           by_exprs_values = "logcounts", colour_by = "CD27")
    # --- List [] ---
    # Key functions: altExp, MultiAssayExperiment
    ---------------------------------------------------------------------
    experiments <- list(
      ADT = altExp(sce_citeseq, "ADT"),
      HTO = altExp(sce_citeseq, "HTO")
    )
    # --- write H5 M U [] ---
    # Key functions: writeH5MU
    ---------------------------------------------------------------------
    writeH5MU(mae, "citefuse_example.h5mu")
    # --- H5 Fopen [] ---
    # Key functions: H5Fopen, h5ls, H5Gopen
    ---------------------------------------------------------------------
    h5 <- rhdf5::H5Fopen("citefuse_example.h5mu")
    h5ls(H5Gopen(h5, "mod"), recursive = FALSE)
    # --- h5ls [] ---
    # Key functions: h5ls, H5Gopen
    ---------------------------------------------------------------------
    h5ls(H5Gopen(h5, "mod/ADT"), FALSE)
    h5ls(H5Gopen(h5, "mod/ADT/layers"), FALSE)
    # --- h5ls [] ---
    # Key functions: h5ls, H5Gopen, H5close
    ---------------------------------------------------------------------
    h5ls(H5Gopen(h5, "mod/RNA/obsm"), FALSE)
    # There is an alternative way to access groups:
    # h5&'mod'&'RNA'&'obsm'
    rhdf5::H5close()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mudata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mudata_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mudata_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUDATA:", paste0("    mudata: ", packageVersion("MuData"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mudata_results.csv
    touch ${prefix}_mudata_output.rds
    echo "BIOC_MUDATA:" > versions.yml
    echo "    mudata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUDATA(ch_input)

    emit:
    results  = BIOC_MUDATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUDATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUDATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUDATA.out.versions  // channel: path(versions.yml)
}
