#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RankProd — multi_condition_contrast
// Simultaneously identify genes up-regulated under one condition and down-regulated under another by switching class labels.
// Input: multi_origin_expression_matrix.tsv, class_labels.txt, origin_labels.txt
// Container: quay.io/biocontainers/bioconductor-rankprod:3.36.0--r45hdfd78af_0
// R packages: RankProd
// Bioconductor: 3.20 | R: 4.4
// Requires: RankProd
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Modify class labels for one of the origins to invert the comparison direction
//  * 2. [Core Analysis] Run RP.advance with calculateProduct=FALSE to perform Rank Sum analysis
//  * 3. [Core Analysis] Extract significant genes using topGene
//  * 4. [Visualization & Output] Plot the results using plotRP

nextflow.enable.dsl = 2

process BIOC_RANKPROD_MULTI_CONDITION_CONTRAST {
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
    .bm_deps <- c("RankProd")
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
    
    # Load required library
    library(RankProd)
    
    # Read user inputs from the working directory
    # Expression matrix: rows are genes, columns are samples
    arab <- as.matrix(read.delim("multi_origin_expression_matrix.tsv", row.names = 1, check.names = FALSE))
    
    # Class labels vector (0 and 1)
    arab.cl <- scan("class_labels.txt", quiet = TRUE)
    
    # Origin labels vector (1, 2, etc.)
    arab.origin <- scan("origin_labels.txt", quiet = TRUE)
    
    # Gene names vector
    arab.gnames <- rownames(arab)
    
    # 1. Modify class labels for one of the origins to invert the comparison direction
    arab.cl2 <- arab.cl
    arab.cl2[arab.cl==0 &arab.origin==2] <- 1
    arab.cl2[arab.cl==1 &arab.origin==2] <- 0
    
    # 2. Run RP.advance with calculateProduct=FALSE to perform Rank Sum analysis
    Rsum.adv.out <- RP.advance(arab,arab.cl2,arab.origin,calculateProduct=FALSE,
    logged=TRUE,gene.names=arab.gnames,rand=123)
    
    # 3. Extract significant genes using topGene
    sig_genes <- topGene(Rsum.adv.out,cutoff=0.05,gene.names=arab.gnames)
    
    # Save the significant genes tables to CSV files
    if (!is.null(sig_genes\$Table1)) {
      write.csv(sig_genes\$Table1, "significant_genes_class1_less_than_class2.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message="No significant genes found"), "significant_genes_class1_less_than_class2.csv", row.names = FALSE)
    }
    
    if (!is.null(sig_genes\$Table2)) {
      write.csv(sig_genes\$Table2, "significant_genes_class1_greater_than_class2.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message="No significant genes found"), "significant_genes_class1_greater_than_class2.csv", row.names = FALSE)
    }
    
    # Save the full RankProd advance output object
    saveRDS(Rsum.adv.out, "Rsum_adv_out.rds")
    
    # 4. Plot the results using plotRP
    pdf("plotRP_results.pdf")
    plotRP(Rsum.adv.out,cutoff=0.05)
    dev.off()

    writeLines(c(
        '"BIOC_RANKPROD_MULTI_CONDITION_CONTRAST":',
        paste0('    RankProd: ', as.character(packageVersion('RankProd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_condition_contrast.csv versions.yml
    """
}

workflow BIOC_RANKPROD_MULTI_CONDITION_CONTRAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_origin_expression_matrix.tsv, class_labels.txt, origin_labels.txt ] ]

    main:
    BIOC_RANKPROD_MULTI_CONDITION_CONTRAST(ch_input)

    emit:
    tables   = BIOC_RANKPROD_MULTI_CONDITION_CONTRAST.out.tables
    plots    = BIOC_RANKPROD_MULTI_CONDITION_CONTRAST.out.plots
    objects  = BIOC_RANKPROD_MULTI_CONDITION_CONTRAST.out.objects
    versions = BIOC_RANKPROD_MULTI_CONDITION_CONTRAST.out.versions
}
