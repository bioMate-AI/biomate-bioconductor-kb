#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sSeq
// The purpose of this package is to discover the genes that are differentially expressed between two c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sSeq/inst/doc/sSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sseq:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sseq:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sSeq)
    library(jsonlite)

    # --- Hammer [] ---
    # Key functions: data
    library(sSeq);
    data(Hammer2months);
    head(countsTable);
    conds.Hammer=c("A","A","B","B");
    # --- Res1 [] ---
    # Key functions: nbTestSH
    #exact test to get differential expressed genes
    res1 = nbTestSH( countsTable, conds.Hammer, "A", "B");
    # --- Avsb Asdplot [] ---
    # Key functions: nbTestSH
    disp1 <- nbTestSH( countsTable, conds.Hammer, "A", "B", SHonly=TRUE, plotASD=TRUE);
    # --- Dispplot [] ---
    # Key functions: plotDispersion
    plotDispersion(disp1, legPos="bottomright")
    # --- Varianceplot [] ---
    # Key functions: rowVars, rowMeans, smoothScatter, expression, hat
    rV = rowVars(countsTable);
     mu = rowMeans(countsTable);
     SH.var =  (disp1$SH * mu^2 + mu)
     smoothScatter(log(rV)~log(mu), main="Variance Plot", ylab='log(variance)',
       xlab='log(mean)', col=blues9[5], cex.axis=1.8)
    # --- Ecdf [] ---
    # Key functions: nbTestSH, frame, ecdfAUC
    #obtain the p-values for the comparison AvsA.
    conds2.Hammer = c("A","B");
    res1.2 =  nbTestSH( countsTable[,1:2], conds2.Hammer, "A", "B");
    #draw the ECDF plot;
    dd = data.frame(AvsA=res1.2$pval, AvsB=res1$pval);
    # --- Mv Volcano [] ---
    # Key functions: drawMA_vol
    drawMA_vol(countsTable, conds.Hammer, res1$pval, cutoff=0.05);
    # --- Paireddesign Data [] ---
    # Key functions: frame
    data(Tuch);
    head(countsTable);
    conds2 = c("normal", "normal", "normal", "tumor", "tumor", "tumor");
    coLevels=data.frame(subjects=c(1,2,3,1,2,3));
    # --- Paireddesign [] ---
    # Key functions: nbTestSH
    res2 = nbTestSH(countsTable, conds2, "normal", "tumor",
       coLevels= coLevels, pairedDesign=TRUE, pairedDesign.dispMethod="pooled");

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSEQ:", paste0("    sseq: ", packageVersion("sSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sseq_results.csv
    touch ${prefix}_sseq_output.rds
    echo "BIOC_SSEQ:" > versions.yml
    echo "    sseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSEQ(ch_input)

    emit:
    results  = BIOC_SSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSEQ.out.versions  // channel: path(versions.yml)
}
