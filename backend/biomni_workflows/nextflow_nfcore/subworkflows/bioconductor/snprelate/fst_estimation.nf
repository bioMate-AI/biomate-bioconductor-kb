#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNPRelate — fst_estimation
// Estimate Weir & Cockerham (1984) Fst coefficients for two or more populations.
// Input: genofile, samp.sel, pop.sel
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// Requires: SNPRelate, gdsfmt
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate weighted and mean Fst using snpgdsFst

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_FST_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("SNPRelate", "gdsfmt")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(gdsfmt)
    library(SNPRelate)
    
    # Read user inputs from the working directory
    # samp.sel: Vector of selected sample IDs
    # pop.sel: Vector of population codes matching the selected samples
    # genofile: Open GDS file handle (opened from genofile.gds)
    samp.sel <- readRDS("samp.sel.rds")
    pop.sel <- readRDS("pop.sel.rds")
    genofile <- snpgdsOpen("genofile.gds")
    
    # Estimate Weir & Cockerham (1984) Fst coefficients
    v <- snpgdsFst(genofile, sample.id=samp.sel, population=as.factor(pop.sel), method="W&C84")
    
    # Print summary to console/log
    cat("Weighted Fst:", v\$Fst, "\n")
    cat("Mean Fst:", v\$MeanFst, "\n")
    print(summary(v\$FstSNP))
    
    # Save results to RDS
    saveRDS(v, "fst_results.rds")
    
    # Save summary metrics to CSV
    fst_summary <- data.frame(
      Metric = c("Weighted_Fst", "Mean_Fst"),
      Value = c(v\$Fst, v\$MeanFst)
    )
    write.csv(fst_summary, "fst_summary_metrics.csv", row.names = FALSE)
    
    # Save SNP-specific Fst values to CSV
    snp_fst_df <- data.frame(
      Fst = v\$FstSNP
    )
    write.csv(snp_fst_df, "snp_specific_fst.csv", row.names = FALSE)
    
    # Generate a PDF plot of the Fst distribution
    pdf("fst_distribution.pdf", width = 6, height = 6)
    hist(v\$FstSNP, breaks = 50, col = "skyblue", xlab = "Fst per SNP",
         main = "Distribution of SNP-specific Fst (W&C84)")
    abline(v = v\$Fst, col = "red", lwd = 2, lty = 2)
    legend("topright", legend = c(paste("Weighted Fst =", round(v\$Fst, 4))),
           col = "red", lty = 2, lwd = 2)
    dev.off()
    
    # Close the GDS file
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_FST_ESTIMATION":',
        paste0('    SNPRelate: ', as.character(packageVersion('SNPRelate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fst_estimation.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_FST_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile, samp.sel, pop.sel ] ]

    main:
    BIOC_SNPRELATE_FST_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_FST_ESTIMATION.out.tables
    plots    = BIOC_SNPRELATE_FST_ESTIMATION.out.plots
    objects  = BIOC_SNPRELATE_FST_ESTIMATION.out.objects
    versions = BIOC_SNPRELATE_FST_ESTIMATION.out.versions
}
