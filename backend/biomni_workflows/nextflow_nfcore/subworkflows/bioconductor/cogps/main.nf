#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: coGPS — outlier_detection_and_gsea
// Identify outlier genes across multiple genomic datasets using PCOPA, calculate permutation-based p-values, visualize top results, and perform gene set enrichmen
// Input: gene_expression.csv, methylation.csv, cnv.csv, class_labels.csv
// Container: quay.io/biocontainers/bioconductor-cogps:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: coGPS, limma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare input list of matrices and class labels
//  * 2. [Core Analysis] Run PCOPA to calculate outlier statistics (subtype or uniform)
//  * 3. [Visualization & Output] Plot top-ranked outlier genes using PlotTopPCOPA
//  * 4. [Core Analysis] Run permutation tests using permCOPA to calculate p-values
//  * 5. [Core Analysis] Perform downstream gene set enrichment analysis using Wilcoxon rank sum test (wilcoxGST from limma)

nextflow.enable.dsl = 2

process BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA {
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
    .bm_deps <- c("coGPS", "limma")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(coGPS)
    library(limma)
    
    # 1. Prepare matched and identically ordered input list of matrices and class labels
    # Read user input files from the working directory
    Exon_exprs_matched <- read.csv("gene_expression.csv", row.names=1, check.names=FALSE)
    Methy_exprs_matched <- read.csv("methylation.csv", row.names=1, check.names=FALSE)
    CNV_exprs_matched <- read.csv("cnv.csv", row.names=1, check.names=FALSE)
    class_labels <- read.csv("class_labels.csv", header=TRUE)
    
    # Convert expression data to matrices as required by coGPS
    Exon_exprs <- as.matrix(Exon_exprs_matched)
    Methy_exprs <- as.matrix(Methy_exprs_matched)
    CNV_exprs <- as.matrix(CNV_exprs_matched)
    
    # Extract class labels dynamically based on column names or indices
    col_names <- colnames(class_labels)
    exon_idx <- grep("exon|expression|exprs", col_names, ignore.case=TRUE)
    if(length(exon_idx) == 0) exon_idx <- 1
    methy_idx <- grep("methy|methylation", col_names, ignore.case=TRUE)
    if(length(methy_idx) == 0) methy_idx <- 2
    cnv_idx <- grep("cnv|copy", col_names, ignore.case=TRUE)
    if(length(cnv_idx) == 0) cnv_idx <- 3
    
    Exon_classlab <- unlist(class_labels[, exon_idx])
    Methy_classlab <- unlist(class_labels[, methy_idx])
    CNV_classlab <- unlist(class_labels[, cnv_idx])
    
    # Construct the trylist object
    trylist <- list()
    trylist[[1]] <- list(exprs=Exon_exprs, classlab=Exon_classlab)
    trylist[[2]] <- list(exprs=Methy_exprs, classlab=Methy_classlab)
    trylist[[3]] <- list(exprs=CNV_exprs, classlab=CNV_classlab)
    
    # 2. Run PCOPA to calculate outlier statistics
    a7 <- PCOPA(trylist, 0.05, side=c("up","down","up"), type="subtype")
    
    # 3. Plot top-ranked outlier genes using PlotTopPCOPA
    pdf("PlotTopPCOPA.pdf")
    PlotTopPCOPA(trylist, a7, topcut=1, typelist=c("Exon","Methy","CNV"))
    dev.off()
    
    # 4. Run permutation tests using permCOPA
    perma7 <- permCOPA(trylist, 0.05, side=c("up","down","up"), type="subtype", perms=2)
    
    pvaluea7 <- sapply(1:length(a7), function(i) 
      length(which(perma7[i,] > a7[i])) / ncol(perma7))
    
    # 5. Perform downstream gene set enrichment analysis using wilcoxGST from limma
    # Using a subset of genes as a proxy for a gene set
    index <- 1:min(50, length(a7))
    gsea_result <- wilcoxGST(index, a7)
    cat("GSEA Wilcoxon GST p-value for the selected gene set:\n")
    print(gsea_result)
    
    # Save the complete results as an RDS object
    saveRDS(list(PCOPA=a7, pvalue=pvaluea7, GSEA=gsea_result), "pcopa_results.rds")
    
    # Format and save the results as a structured CSV table
    outlier_df <- data.frame(
      Gene = rownames(Exon_exprs),
      PCOPA_Score = a7,
      P_Value = pvaluea7,
      stringsAsFactors = FALSE
    )
    write.csv(outlier_df, "pcopa_results.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA":',
        paste0('    coGPS: ', as.character(packageVersion('coGPS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_outlier_detection_and_gsea.csv versions.yml
    """
}

workflow BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.csv, methylation.csv, cnv.csv, class_labels.csv ] ]

    main:
    BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA(ch_input)

    emit:
    tables   = BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA.out.tables
    plots    = BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA.out.plots
    objects  = BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA.out.objects
    versions = BIOC_COGPS_OUTLIER_DETECTION_AND_GSEA.out.versions
}
