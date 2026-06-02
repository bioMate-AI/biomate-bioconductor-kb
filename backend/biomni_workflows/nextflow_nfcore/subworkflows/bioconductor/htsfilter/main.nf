#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HTSFilter
// This package implements a filtering procedure for replicated transcriptome sequencing data based on 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HTSFilter/inst/doc/HTSFilter.R
// Upstream  : DESeq2, EDASeq, edgeR
// Downstream: none
//
// Install: BiocManager::install("HTSFilter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HTSFILTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-htsfilter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-htsfilter:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-htsfilter:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_htsfilter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_htsfilter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_htsfilter_plots.pdf"),    emit: plots, optional: true
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
    library(HTSFilter)
    library(jsonlite)

    # --- p Data [] ---
    # Key functions: pData
    library(HTSFilter)
    library(edgeR)
    library(DESeq2)
    # --- exprs [] ---
    # Key functions: exprs, HTSFilter
    mat <- exprs(sultan)
    conds <- as.character(pData(sultan)$cell.line)
    filter <- HTSFilter(mat, conds, s.min=1, s.max=200, s.len=25)
    # --- Create DGEList count object [] ---
    # Key functions: DGEList, calcNormFactors, estimateDisp, exactTest, HTSFilter
    dge <- DGEList(counts=exprs(sultan), group=conds)
    dge <- calcNormFactors(dge)
    dge <- estimateDisp(dge)
    # --- Create DGEList count object [] ---
    # Key functions: DGEList, calcNormFactors, estimateDisp, glmFit, glmLRT
    design <- model.matrix(~conds)
    dge <- DGEList(counts=exprs(sultan), group=conds)
    dge <- calcNormFactors(dge)
    # --- Create DESeqDataSet from count matrix [] ---
    # Key functions: DESeqDataSetFromMatrix, DESeq, HTSFilter, results
    conds <- gsub(" ", ".", conds)
    dds <- DESeqDataSetFromMatrix(countData = exprs(sultan),
    colData = data.frame(cell.line = factor(conds)),
    # --- new Seq Expression Set [] ---
    # Key functions: newSeqExpressionSet
    library(EDASeq)
    ses <- newSeqExpressionSet(exprs(sultan),
    phenoData=pData(sultan))
    # --- H T S Filter [] ---
    # Key functions: HTSFilter
    filter <- HTSFilter(counts(ses.norm), conds, s.len=25, norm="none",
    head(filter$on)
    table(filter$on)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_htsfilter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_htsfilter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_htsfilter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HTSFILTER:", paste0("    htsfilter: ", packageVersion("HTSFilter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_htsfilter_results.csv
    touch ${prefix}_htsfilter_output.rds
    echo "BIOC_HTSFILTER:" > versions.yml
    echo "    htsfilter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HTSFILTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HTSFILTER(ch_input)

    emit:
    results  = BIOC_HTSFILTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HTSFILTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HTSFILTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HTSFILTER.out.versions  // channel: path(versions.yml)
}
