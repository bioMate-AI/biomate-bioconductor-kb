#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PharmacoGx — sensitivity_consistency
// Compare gene expression and drug sensitivity measures across different pharmacogenomic studies.
// Input: GDSCsmall, CCLEsmall
// Container: quay.io/biocontainers/bioconductor-pharmacogx:3.14.0--r45ha27e39d_0
// R packages: Biobase, CoreGx, ggplot2, PharmacoGx, S4Vectors, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: PharmacoGx, SummarizedExperiment
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the declared USER INPUT files from the working
//  * 2. [Visualization & Output] Execute the documented workflow EXACTLY as specified
//  * 3. [Visualization & Output] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "CoreGx", "ggplot2", "PharmacoGx", "S4Vectors", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(PharmacoGx)
    library(SummarizedExperiment)
    library(stats)
    
    # --- Read the declared USER INPUT files from the working ---
    if (file.exists("GDSCsmall")) {
      GDSCsmall <- readRDS("GDSCsmall")
    } else if (file.exists("GDSCsmall.rds")) {
      GDSCsmall <- readRDS("GDSCsmall.rds")
    } else {
      stop("Required input file 'GDSCsmall' or 'GDSCsmall.rds' not found in the working directory.")
    }
    
    if (file.exists("CCLEsmall")) {
      CCLEsmall <- readRDS("CCLEsmall")
    } else if (file.exists("CCLEsmall.rds")) {
      CCLEsmall <- readRDS("CCLEsmall.rds")
    } else {
      stop("Required input file 'CCLEsmall' or 'CCLEsmall.rds' not found in the working directory.")
    }
    
    # --- Execute the documented workflow EXACTLY as specified ---
    commonGenes <- intersect(fNames(GDSCsmall, "rna"), fNames(CCLEsmall,"rna"))
    common <- intersectPSet(list('CCLE'=CCLEsmall, 'GDSC'=GDSCsmall), intersectOn=c("cell.lines", "drugs"), strictIntersect=TRUE)
    GDSC.auc <- summarizeSensitivityProfiles( common\$GDSC, sensitivity.measure='auc_published', summary.stat="median", verbose=FALSE)
    CCLE.auc <- summarizeSensitivityProfiles( common\$CCLE, sensitivity.measure='auc_published', summary.stat="median", verbose=FALSE)
    GDSC.ic50 <- summarizeSensitivityProfiles( common\$GDSC, sensitivity.measure='ic50_published', summary.stat="median", verbose=FALSE)
    CCLE.ic50 <- summarizeSensitivityProfiles( common\$CCLE, sensitivity.measure='ic50_published', summary.stat="median", verbose=FALSE)
    GDSCexpression <- summarizeMolecularProfiles(common\$GDSC, cellNames(common\$GDSC), mDataType="rna", features=commonGenes, verbose=FALSE)
    CCLEexpression <- summarizeMolecularProfiles(common\$CCLE, cellNames(common\$CCLE), mDataType="rna", features=commonGenes, verbose=FALSE)
    gg <- fNames(common[[1]], 'rna')
    cc <- cellNames(common[[1]])
    ge.cor <- sapply(cc, function (x, d1, d2) { stats::cor(d1[ , x], d2[ , x], method="spearman", use="pairwise.complete.obs") }, d1=assay(GDSCexpression, 1), d2=assay(CCLEexpression, 1))
    ic50.cor <- sapply(cc, function (x, d1, d2) { stats::cor(d1[, x], d2[ , x], method="spearman", use="pairwise.complete.obs") }, d1=GDSC.ic50, d2=CCLE.ic50)
    auc.cor <- sapply(cc, function (x, d1, d2) { stats::cor(d1[ , x], d2[ , x], method="spearman", use="pairwise.complete.obs") }, d1=GDSC.auc, d2=CCLE.auc)
    w1 <- stats::wilcox.test(x=ge.cor, y=auc.cor, conf.int=TRUE, exact=FALSE)
    w2 <- stats::wilcox.test(x=ge.cor, y=ic50.cor, conf.int=TRUE, exact=FALSE)
    yylim <- c(-1, 1)
    ss <- sprintf("GE vs. AUC = %.1E\nGE vs. IC50 = %.1E", w1\$p.value, w2\$p.value)
    
    # --- Write named output files for the meaningful results ---
    # Save the boxplot as a PDF
    pdf("concordance_boxplot.pdf", width = 7, height = 7)
    boxplot(list("GE"=ge.cor, "AUC"=auc.cor, "IC50"=ic50.cor), main="Concordance between cell lines", ylab=expression(R[s]), sub=ss, ylim=yylim, col="lightgrey", pch=20, border="black")
    dev.off()
    
    # Save the correlation coefficients as a CSV table
    cor_df <- data.frame(
      CellLine = names(ge.cor),
      GeneExpression_Cor = ge.cor,
      IC50_Cor = ic50.cor,
      AUC_Cor = auc.cor,
      row.names = NULL
    )
    write.csv(cor_df, "correlations.csv", row.names = FALSE)
    
    # Save the Wilcoxon test results as an RDS object
    wilcox_results <- list(
      GE_vs_AUC = w1,
      GE_vs_IC50 = w2
    )
    saveRDS(wilcox_results, "wilcox_results.rds")

    writeLines(c(
        '"BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY":',
        paste0('    PharmacoGx: ', as.character(packageVersion('PharmacoGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sensitivity_consistency.csv versions.yml
    """
}

workflow BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GDSCsmall, CCLEsmall ] ]

    main:
    BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY(ch_input)

    emit:
    tables   = BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY.out.tables
    plots    = BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY.out.plots
    objects  = BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY.out.objects
    versions = BIOC_PHARMACOGX_SENSITIVITY_CONSISTENCY.out.versions
}
