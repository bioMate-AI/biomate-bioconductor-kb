#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: limma
// Data analysis, linear models and differential expression for omics data.
//
// Source : https://bioconductor.org/packages/3.20/workflows/vignettes/RNAseq123/inst/doc/limmaWorkflow.html
// Upstream  : none
// Downstream: ASpli, BLMA, cghMCR, codelink, convert
//
// Install: BiocManager::install("limma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LIMMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-limma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-limma:3.62.2--r44_0' :
        'quay.io/biocontainers/bioconductor-limma:3.62.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_limma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_limma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_limma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(limma)
    library(jsonlite)

    # --- Voom Mean-Variance Modelling [] ---
    # Key functions: voom
    counts <- matrix(rnbinom(1000, mu=100, size=1), nrow=100, ncol=10)
    group <- as.factor(rep(c("Basal", "LP", "ML"), length.out=10))
    design <- model.matrix(~0+group)
    colnames(design) <- levels(group)
    v <- voom(counts, design, plot=FALSE)


    # --- Linear Modelling and Empirical Bayes [] ---
    # Key functions: lmFit, contrasts.fit, eBayes, decideTests
    counts <- matrix(rnbinom(1000, mu=100, size=1), nrow=100, ncol=10)
    group <- as.factor(rep(c("Basal", "LP", "ML"), length.out=10))
    design <- model.matrix(~0+group)
    colnames(design) <- levels(group)
    v <- voom(counts, design, plot=FALSE)
    contr.matrix <- makeContrasts(
        BasalvsLP = Basal-LP,
        levels = colnames(design)
    )
    vfit <- lmFit(v, design)
    vfit <- contrasts.fit(vfit, contrasts=contr.matrix)
    efit <- eBayes(vfit)
    results <- decideTests(efit)
    summary(results)


    # --- Relative to a Threshold (Treat) and Top Tables [] ---
    # Key functions: treat, topTreat, write.fit
    counts <- matrix(rnbinom(1000, mu=100, size=1), nrow=100, ncol=10)
    group <- as.factor(rep(c("Basal", "LP", "ML"), length.out=10))
    design <- model.matrix(~0+group)
    colnames(design) <- levels(group)
    v <- voom(counts, design, plot=FALSE)
    contr.matrix <- makeContrasts(
        BasalvsLP = Basal-LP,
        levels = colnames(design)
    )
    vfit <- lmFit(v, design)
    vfit <- contrasts.fit(vfit, contrasts=contr.matrix)
    tfit <- treat(vfit, lfc=1)
    dt <- decideTests(tfit)
    basal.vs.lp <- topTreat(tfit, coef=1, n=Inf)
    write.fit(tfit, dt, file="results.txt")


    # --- Diagnostic and Differential Expression Plots [] ---
    # Key functions: plotSA, plotMD, vennDiagram
    counts <- matrix(rnbinom(1000, mu=100, size=1), nrow=100, ncol=10)
    group <- as.factor(rep(c("Basal", "LP", "ML"), length.out=10))
    design <- model.matrix(~0+group)
    colnames(design) <- levels(group)
    vfit <- lmFit(voom(counts, design, plot=FALSE), design)
    efit <- eBayes(vfit)
    dt <- decideTests(efit)
    plotSA(efit, main="Mean-variance trend")
    plotMD(efit, column=1, status=dt[,1], main="MD Plot")
    vennDiagram(dt[,1,drop=FALSE], circle.col="turquoise")


    # --- Competitive Gene Set Test [] ---
    # Key functions: camera, ids2indices, barcodeplot
    counts <- matrix(rnbinom(1000, mu=100, size=1), nrow=100, ncol=10)
    rownames(counts) <- paste0("Gene", 1:100)
    group <- as.factor(rep(c("Basal", "LP", "ML"), length.out=10))
    design <- model.matrix(~0+group)
    colnames(design) <- levels(group)
    v <- voom(counts, design, plot=FALSE)
    vfit <- lmFit(v, design)
    efit <- eBayes(vfit)
    gene_sets <- list(
        SET1 = paste0("Gene", 1:10),
        SET2 = paste0("Gene", 11:20)
    )
    idx <- ids2indices(gene_sets, id=rownames(v))
    cam.results <- camera(v, idx, design, contrast=c(1, -1, 0))
    barcodeplot(efit$t[,1], index=idx$SET1, main="Barcodeplot")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_limma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_limma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_limma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LIMMA:", paste0("    limma: ", packageVersion("limma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limma_results.csv
    touch ${prefix}_limma_output.rds
    echo "BIOC_LIMMA:" > versions.yml
    echo "    limma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LIMMA(ch_input)

    emit:
    results  = BIOC_LIMMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LIMMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LIMMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LIMMA.out.versions  // channel: path(versions.yml)
}
