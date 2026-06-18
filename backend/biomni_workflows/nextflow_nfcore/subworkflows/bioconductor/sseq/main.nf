#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sSeq — simple_two_condition_comparison
// Discover differentially expressed genes between two independent conditions using shrinkage dispersion estimation and visualize the results.
// Input: countsTable, conds.Hammer
// Container: quay.io/biocontainers/bioconductor-sseq:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: matrixStats, sSeq
// Visualizations: smooth scatter, dispersion plot, volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Run the exact test using nbTestSH to obtain p-values and shrinkage dispersion estimates
//  * 3. [Visualization & Output] (Optional) Estimate dispersion only and plot the Average Squared Difference (ASD) curve
//  * 4. [Visualization & Output] Plot dispersion estimates against mean estimates
//  * 5. [Visualization & Output] Generate a mean-variance dependence plot
//  * 6. [Visualization & Output] Perform a within-condition comparison to generate an ECDF plot for specificity and sensitivity analysis
//  * 7. [Visualization & Output] Draw MA and volcano plots for visual inspection of the test results

nextflow.enable.dsl = 2

process BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON {
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
    .bm_deps <- c("sSeq", "matrixStats")
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
        library(sSeq)
        library(matrixStats)
        
        # ==========================================
        # 1. Load the data from the working directory
        # ==========================================
        
        # Read countsTable
        if (file.exists("countsTable")) {
          countsTable <- as.matrix(read.table("countsTable", header=TRUE, row.names=1))
        } else if (file.exists("countsTable.csv")) {
          countsTable <- as.matrix(read.csv("countsTable.csv", row.names=1))
        } else if (file.exists("countsTable.tsv")) {
          countsTable <- as.matrix(read.delim("countsTable.tsv", row.names=1))
        } else if (file.exists("countsTable.rds")) {
          countsTable <- as.matrix(readRDS("countsTable.rds"))
        } else {
          stop("Error: countsTable file not found in the working directory.")
        }
        
        # Read conds.Hammer
        if (file.exists("conds.Hammer")) {
          conds.Hammer <- scan("conds.Hammer", what=character(), quiet=TRUE)
        } else if (file.exists("conds.Hammer.txt")) {
          conds.Hammer <- scan("conds.Hammer.txt", what=character(), quiet=TRUE)
        } else if (file.exists("conds.Hammer.rds")) {
          conds.Hammer <- readRDS("conds.Hammer.rds")
        } else {
          stop("Error: conds.Hammer file not found in the working directory.")
        }
        
        # Print preview of loaded data
        print("Loaded countsTable preview:")
        print(head(countsTable))
        print("Loaded conds.Hammer:")
        print(conds.Hammer)
        
        # Extract unique conditions dynamically
        conds_unique <- unique(conds.Hammer)
        condA <- conds_unique[1]
        condB <- conds_unique[2]
        
        # ==========================================
        # 2. Run the exact test using nbTestSH
        # ==========================================
        res1 = nbTestSH( countsTable, conds.Hammer, condA, condB);
        print("Preview of res1:")
        print(head(res1));
        
        # Save res1 results
        write.csv(res1, "res1_results.csv", row.names=TRUE)
        saveRDS(res1, "res1_results.rds")
        
        # ==========================================
        # 3. Estimate dispersion only and plot ASD
        # ==========================================
        pdf("asd_plot.pdf")
        disp1 <- nbTestSH( countsTable, conds.Hammer, condA, condB, SHonly=TRUE, plotASD=TRUE);
        dev.off()
        
        print("Preview of disp1:")
        print(head(disp1));
        
        # Save dispersion estimates
        write.csv(disp1, "disp1_dispersion.csv", row.names=TRUE)
        saveRDS(disp1, "disp1_dispersion.rds")
        
        # ==========================================
        # 4. Plot dispersion estimates
        # ==========================================
        pdf("dispersion_plot.pdf")
        plotDispersion(disp1, legPos="bottomright")
        dev.off()
        
        # ==========================================
        # 5. Generate a mean-variance dependence plot
        # ==========================================
        rV = rowVars(countsTable);
        mu = rowMeans(countsTable); 
        SH.var =  (disp1\$SH * mu^2 + mu)
        
        pdf("variance_plot.pdf")
        smoothScatter(log(rV)~log(mu), main="Variance Plot", ylab='log(variance)', 
          xlab='log(mean)', col=blues9[5], cex.axis=1.8)
        points( log(SH.var)~log(mu), col="black", pch=16)
        leg1 =  expression(paste("log(", hat("V")[g]^"sSeq", ")", sep=''));
        leg2 =  expression(paste("log(", hat("V")[g]^"MM", ")", sep=''));
        legend("bottomright", legend=c(leg1,leg2), col=c("black",blues9[5]), 
          pch=c(16, 1), cex=2)
        dev.off()
        
        # ==========================================
        # 6. Within-condition comparison & ECDF plot
        # ==========================================
        # Find a condition with at least 2 replicates to ensure valid within-condition comparison
        rep_cond <- names(which(table(conds.Hammer) >= 2))[1]
        rep_cols <- which(conds.Hammer == rep_cond)[1:2]
        
        conds2.Hammer = c(condA, condB);
        res1.2 =  nbTestSH( countsTable[,rep_cols], conds2.Hammer, condA, condB);
        
        # Save within-condition comparison results
        write.csv(res1.2, "res1.2_results.csv", row.names=TRUE)
        
        dd = data.frame(AvsA=res1.2\$pval, AvsB=res1\$pval);
        
        pdf("ecdf_plot.pdf")
        ecdfAUC(dd, col.line=c("green", "red"), main = "ECDF, Hammer", drawRef = TRUE, rm1=TRUE)
        dev.off()
        
        # ==========================================
        # 7. Draw MA and volcano plots
        # ==========================================
        pdf("ma_volcano_plot.pdf")
        drawMA_vol(countsTable, conds.Hammer, res1\$pval, cutoff=0.05);
        dev.off()
        
        print("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON":',
        paste0('    sSeq: ', as.character(packageVersion('sSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simple_two_condition_comparison.csv versions.yml
    """
}

workflow BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsTable, conds.Hammer ] ]

    main:
    BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON.out.tables
    plots    = BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON.out.plots
    objects  = BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON.out.objects
    versions = BIOC_SSEQ_SIMPLE_TWO_CONDITION_COMPARISON.out.versions
}
