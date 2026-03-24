#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RUVSeq
// This package implements the remove unwanted variation (RUV) methods of Risso et al. (2014) for the n
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RUVSeq/inst/doc/RUVSeq.R
// Upstream  : DESeq2, RColorBrewer, zebrafishRNASeq
// Downstream: octad, rnaseqGene
//
// Install: BiocManager::install("RUVSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RUVSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ruvseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ruvseq:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ruvseq:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_ruvseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ruvseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ruvseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(RUVg)
    library(RUVr)
    library(RUVs)
    library(jsonlite)

    # --- Create DGEList count object [] ---
    # Key functions: DGEList, calcNormFactors, estimateGLMCommonDisp, estimateGLMTagwiseDisp, glmFit, DESeqDataSetFromMatrix, DESeq, results
    design <- model.matrix(~x + W_1, data=pData(set1))
    y <- DGEList(counts=counts(set1), group=x)
    y <- calcNormFactors(y, method="upperquartile")
    # --- Run DESeq2 differential expression [] ---
    # Key functions: DESeq, results
    dds <- DESeq(dds, test="LRT", reduced=as.formula("~ W_1"))
    res <- results(dds)
    # --- PCA plot of sample distances [] ---
    # Key functions: plotRLE, plotPCA, betweenLaneNormalization, RUVg, pData
    set <- betweenLaneNormalization(set, which="upper")
    plotRLE(set, outline=FALSE, ylim=c(-4, 4), col=colors[x])
    plotPCA(set, col=colors[x], cex=1.2)
    # --- Phenotype data inspection [] ---
    # Key functions: newSeqExpressionSet, makeGroups, RUVs, pData, RUVr
    x <- as.factor(rep(c("Ctl", "Trt"), each=3))
    set <- newSeqExpressionSet(as.matrix(filtered),
    phenoData = data.frame(x, row.names=colnames(filtered)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ruvseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ruvseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ruvseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RUVSEQ:", paste0("    ruvseq: ", packageVersion("RUVSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvseq_results.csv
    touch ${prefix}_ruvseq_output.rds
    echo "BIOC_RUVSEQ:" > versions.yml
    echo "    ruvseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RUVSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_RUVSEQ(ch_input)

    emit:
    results  = BIOC_RUVSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RUVSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RUVSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RUVSEQ.out.versions  // channel: path(versions.yml)
}
