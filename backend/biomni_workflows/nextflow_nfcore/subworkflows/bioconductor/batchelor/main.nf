#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: batchelor
// Implements a variety of methods for batch correction of single-cell (RNA sequencing) data. This incl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/batchelor/inst/doc/correction.R
// Upstream  : knitr, scRNAseq, scater, scran, scuttle
// Downstream: OSCA.advanced, OSCA.intro, OSCA.multisample, OSCA.workflows
//
// Install: BiocManager::install("batchelor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BATCHELOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-batchelor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-batchelor:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-batchelor:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_batchelor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_batchelor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_batchelor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NoCorrectParam)
    library(TasicBrainData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Zeiselbraindata [] ---
    # Key functions: ZeiselBrainData, TasicBrainData
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce1 <- ZeiselBrainData()
    sce1
    sce2 <- TasicBrainData()
    # --- Addpercellqc [] ---
    # Key functions: addPerCellQC, quickPerCellQC, colData
    ---------------------------------------------------------------------
    library(scuttle)
    sce1 <- addPerCellQC(sce1, subsets=list(Mito=grep("mt-", rownames(sce1))))
    qc1 <- quickPerCellQC(colData(sce1), sub.fields="subsets_Mito_percent")
    sce1 <- sce1[,!qc1$discard]
    # --- Intersect [] ---
    # Key functions: intersect
    ---------------------------------------------------------------------
    universe <- intersect(rownames(sce1), rownames(sce2))
    sce1 <- sce1[universe,]
    sce2 <- sce2[universe,]
    # --- Multibatchnorm [] ---
    # Key functions: multiBatchNorm
    ---------------------------------------------------------------------
    out <- multiBatchNorm(sce1, sce2)
    sce1 <- out[[1]]
    sce2 <- out[[2]]
    # --- Modelgenevar [] ---
    # Key functions: modelGeneVar, combineVar, getTopHVGs
    ---------------------------------------------------------------------
    library(scran)
    dec1 <- modelGeneVar(sce1)
    dec2 <- modelGeneVar(sce2)
    combined.dec <- combineVar(dec1, dec2)
    # --- Correctexperiments [] ---
    # Key functions: correctExperiments, NoCorrectParam, runPCA, runTSNE, plotTSNE
    ---------------------------------------------------------------------
    combined <- correctExperiments(A=sce1, B=sce2, PARAM=NoCorrectParam())
    library(scater)
    set.seed(100)
    combined <- runPCA(combined, subset_row=chosen.hvgs)
    # --- Rle [] ---
    # Key functions: rle
    ---------------------------------------------------------------------
    rle(f.out$batch)
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    cor.exp <- assay(f.out)[1,]
    hist(cor.exp, xlab="Corrected expression for gene 1", col="grey80")
    # --- Head [] ---
    # Key functions: mnnCorrect
    ---------------------------------------------------------------------
    # Using fewer genes as it is much, much slower.
    fewer.hvgs <- head(order(combined.dec$bio, decreasing=TRUE), 100)
    classic.out <- mnnCorrect(sce1, sce2, subset.row=fewer.hvgs)
    # --- Clustermnn [] ---
    # Key functions: clusterMNN
    ---------------------------------------------------------------------
    # Removing the 'unclassified' cluster, which makes no sense:
    not.unclass <- sce2$broad_type!="Unclassified"
    # --- Metadata [] ---
    # Key functions: metadata, split
    ---------------------------------------------------------------------
    clust.info <- metadata(clust.out)$cluster
    split(clust.info$cluster, clust.info$meta)
    # --- Rescalebatches [] ---
    # Key functions: rescaleBatches
    ---------------------------------------------------------------------
    rescale.out <- rescaleBatches(sce1, sce2)
    rescale.out
    # --- Runpca [] ---
    # Key functions: runPCA, plotPCA
    ---------------------------------------------------------------------
    rescale.out <- runPCA(rescale.out, subset_row=chosen.hvgs,
        exprs_values="corrected")
    plotPCA(rescale.out, colour_by="batch")
    # --- Regressbatches [] ---
    # Key functions: regressBatches, assay
    ---------------------------------------------------------------------
    regress.out <- regressBatches(sce1, sce2)
    assay(regress.out)
    # --- List [] ---
    # Key functions: rescaleBatches
    ---------------------------------------------------------------------
    # Pretend the first X cells in each batch are controls.
    restrict <- list(1:100, 1:200)
    rescale.out <- rescaleBatches(sce1, sce2, restrict=restrict)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_batchelor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_batchelor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_batchelor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BATCHELOR:", paste0("    batchelor: ", packageVersion("batchelor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batchelor_results.csv
    touch ${prefix}_batchelor_output.rds
    echo "BIOC_BATCHELOR:" > versions.yml
    echo "    batchelor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BATCHELOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BATCHELOR(ch_input)

    emit:
    results  = BIOC_BATCHELOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BATCHELOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BATCHELOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BATCHELOR.out.versions  // channel: path(versions.yml)
}
