#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cqn
// A normalization tool for RNA-Seq data, implementing the conditional quantile normalization method.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cqn/inst/doc/cqn.R
// Upstream  : edgeR
// Downstream: KnowSeq
//
// Install: BiocManager::install("cqn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CQN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cqn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cqn:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cqn:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cqn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cqn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cqn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(jsonlite)

    # --- Data1 [] ---
    # Key functions: data
    data(montgomery.subset)
    dim(montgomery.subset)
    montgomery.subset[1:4,1:4]
    colnames(montgomery.subset)
    # --- Data2 [] ---
    # Key functions: data
    data(sizeFactors.subset)
    sizeFactors.subset[1:4]
    # --- Data3 [] ---
    # Key functions: data
    data(uCovar)
    head(uCovar)
    # --- Cqncall [] ---
    # Key functions: cqn
    cqn.subset <- cqn(montgomery.subset, lengths = uCovar$length,
                      x = uCovar$gccontent, sizeFactors = sizeFactors.subset,
                      verbose = TRUE)
    cqn.subset
    # --- Cqnplot1 [] ---
    # Key functions: cqnplot
    par(mfrow=c(1,2))
    cqnplot(cqn.subset, n = 1, xlab = "GC content", lty = 1, ylim = c(1,7))
    cqnplot(cqn.subset, n = 2, xlab = "length", lty = 1, ylim = c(1,7))
    # --- Rpkmvalues [] ---
    # Key functions: sweep
    RPM <- sweep(log2(montgomery.subset + 1), 2, log2(sizeFactors.subset/10^6))
    RPKM.std <- sweep(RPM, 1, log2(uCovar$length / 10^3))
    # --- Whgenes [] ---
    # Key functions: rowMeans
    whGenes <- which(rowMeans(RPKM.std) >= 2 & uCovar$length >= 100)
    M.std <- rowMeans(RPKM.std[whGenes, grp1]) - rowMeans(RPKM.std[whGenes, grp2])
    A.std <- rowMeans(RPKM.std[whGenes,])
    M.cqn <- rowMeans(RPKM.cqn[whGenes, grp1]) - rowMeans(RPKM.cqn[whGenes, grp2])
    A.cqn <- rowMeans(RPKM.cqn[whGenes,])
    # --- Maplots [] ---
    # Key functions: alpha
    par(mfrow = c(1,2))
    plot(A.std, M.std, cex = 0.5, pch = 16, xlab = "A", ylab = "M",
         main = "Standard RPKM", ylim = c(-4,4), xlim = c(0,12),
         col = alpha("black", 0.25))
    plot(A.cqn, M.cqn, cex = 0.5, pch = 16, xlab = "A", ylab = "M",
    # --- Edgerconstructor [] ---
    # Key functions: DGEList
    library(edgeR)
    d.mont <- DGEList(counts = montgomery.subset, lib.size = sizeFactors.subset,
                      group = rep(c("grp1", "grp2"), each = 5), genes = uCovar)
    # --- Edgerdisp [] ---
    # Key functions: estimateGLMCommonDisp
    design <- model.matrix(~ d.mont$sample$group)
    d.mont$offset <- cqn.subset$glm.offset
    d.mont.cqn <- estimateGLMCommonDisp(d.mont, design = design)
    # --- Edgerfit [] ---
    # Key functions: glmFit, glmLRT, topTags
    efit.cqn <- glmFit(d.mont.cqn, design = design)
    elrt.cqn <- glmLRT(efit.cqn, coef = 2)
    topTags(elrt.cqn, n = 2)
    # --- Summary [] ---
    # Key functions: decideTests
    summary(decideTests(elrt.cqn))
    # --- Edgerstd [] ---
    # Key functions: estimateGLMCommonDisp, glmFit, glmLRT, decideTests
    d.mont.std <- estimateGLMCommonDisp(d.mont, design = design)
    efit.std <- glmFit(d.mont.std, design = design)
    elrt.std <- glmLRT(efit.std, coef = 2)
    summary(decideTests(elrt.std))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cqn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cqn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cqn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CQN:", paste0("    cqn: ", packageVersion("cqn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cqn_results.csv
    touch ${prefix}_cqn_output.rds
    echo "BIOC_CQN:" > versions.yml
    echo "    cqn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CQN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CQN(ch_input)

    emit:
    results  = BIOC_CQN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CQN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CQN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CQN.out.versions  // channel: path(versions.yml)
}
