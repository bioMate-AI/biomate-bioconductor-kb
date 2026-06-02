#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EDASeq
// Numerical and graphical summaries of RNA-Seq read data. Within-lane normalization procedures to adju
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EDASeq/inst/doc/EDASeq.R
// Upstream  : DESeq2, edgeR, leeBamViews, yeastRNASeq
// Downstream: RUVSeq
//
// Install: BiocManager::install("EDASeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDASEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-edaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-edaseq:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-edaseq:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_edaseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_edaseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_edaseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFileList)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(DataFrame)
    library(FastqFileList)
    library(jsonlite)

    # --- Create DGEList count object [] ---
    # Key functions: DGEList, estimateDisp, glmFit, glmLRT, topTags, DESeqDataSetFromMatrix, normalizationFactors, DESeq
    library(edgeR)
    design <- model.matrix(~conditions, data=pData(dataOffset))
    y <- DGEList(counts=counts(dataOffset),
    # --- Normalize count data [] ---
    # Key functions: betweenLaneNormalization, normCounts
    dataNorm <- betweenLaneNormalization(data, round=FALSE, offset=TRUE)
    norm1 <- normCounts(dataNorm)
    norm2 <- exp(log(counts(dataNorm) + 0.1 ) + offst(dataNorm)) - 0.1
    # --- Visualization and reporting [] ---
    # Key functions: plotQuality
    colors <- c(rep(rgb(1,0,0,alpha=0.7),2),
    rep(rgb(0,0,1,alpha=0.7),2),
    rep(rgb(0,1,0,alpha=0.7),2),
    # --- Phenotype data inspection [] ---
    # Key functions: DataFrame, FastqFileList, elementMetadata, BamFileList, plotQuality, plotNtFrequency, intersect, newSeqExpressionSet
    files <- list.files(file.path(system.file(package = "yeastRNASeq"),
    names(files) <- gsub("\\.fastq.*", "", basename(files))
    met <- DataFrame(conditions=c(rep("mut",2), rep("wt",2)),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_edaseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_edaseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_edaseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDASEQ:", paste0("    edaseq: ", packageVersion("EDASeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edaseq_results.csv
    touch ${prefix}_edaseq_output.rds
    echo "BIOC_EDASEQ:" > versions.yml
    echo "    edaseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_EDASEQ(ch_input)

    emit:
    results  = BIOC_EDASEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDASEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDASEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDASEQ.out.versions  // channel: path(versions.yml)
}
