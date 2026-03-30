#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NBAMSeq
// High-throughput sequencing experiments followed by differential expression analysis is a widely used
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NBAMSeq/inst/doc/NBAMSeq-vignette.R
// Upstream  : BiocParallel, ggplot2
// Downstream: none
//
// Install: BiocManager::install("NBAMSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NBAMSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nbamseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nbamseq:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nbamseq:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nbamseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nbamseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nbamseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NBAMSeq)
    library(NBAMSeqDataSet)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnbinom, mode
    ---------------------------------------------------------------------
    ## An example of countData
    n = 50  ## n stands for number of genes
    m = 20   ## m stands for sample size
    countData = matrix(rnbinom(n*m, mu=100, size=1/3), ncol = m) + 1
    # --- Runif [] ---
    # Key functions: runif, rnorm, factor, sample, frame
    ---------------------------------------------------------------------
    ## An example of colData
    pheno = runif(m, 20, 80)
    var1 = rnorm(m)
    var2 = rnorm(m)
    # --- Nbamseqdataset [] ---
    # Key functions: NBAMSeqDataSet
    ---------------------------------------------------------------------
    gsd = NBAMSeqDataSet(countData = countData, colData = colData, design = design)
    gsd
    # --- Nbamseq [] ---
    # Key functions: NBAMSeq
    ---------------------------------------------------------------------
    gsd = NBAMSeq(gsd)
    # --- Results [] ---
    # Key functions: results
    ---------------------------------------------------------------------
    res1 = results(gsd, name = "pheno")
    head(res1)
    # --- Makeplot [] ---
    # Key functions: makeplot
    ---------------------------------------------------------------------
    ## assuming we are interested in the nonlinear relationship between gene10's
    ## expression and "pheno"
    makeplot(gsd, phenoname = "pheno", genename = "gene10", main = "gene10")
    # --- Order [] ---
    # Key functions: getsf
    ---------------------------------------------------------------------
    ## here we explore the most significant nonlinear association
    res1 = res1[order(res1$pvalue),]
    topgene = rownames(res1)[1]
    sf = getsf(gsd)  ## get the estimated size factors
    # --- Frame [] ---
    # Key functions: frame, ggplot, aes, geom_point, geom_smooth, xlab
    ---------------------------------------------------------------------
    library(ggplot2)
    setTitle = topgene
    df = data.frame(pheno = pheno, logcount = log2(countnorm[topgene,]+1))
    ggplot(df, aes(x=pheno, y=logcount))+geom_point(shape=19,size=1)+

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nbamseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nbamseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nbamseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NBAMSEQ:", paste0("    nbamseq: ", packageVersion("NBAMSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nbamseq_results.csv
    touch ${prefix}_nbamseq_output.rds
    echo "BIOC_NBAMSEQ:" > versions.yml
    echo "    nbamseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NBAMSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NBAMSEQ(ch_input)

    emit:
    results  = BIOC_NBAMSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NBAMSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NBAMSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NBAMSEQ.out.versions  // channel: path(versions.yml)
}
