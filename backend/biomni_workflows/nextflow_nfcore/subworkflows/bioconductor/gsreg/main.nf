#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSReg — pathway_variability_analysis
// Identify dysregulated pathways between two phenotypes based on gene expression variability using DIRAC and EVA.
// Input: exprsdata.csv, diracpathways.rds, phenotypes.csv
// Container: quay.io/biocontainers/bioconductor-gsreg:1.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSReg
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run DIRAC analysis with permutation testing or normal approximation using GSReg.GeneSets.DIRAC
//  * 2. [Core Analysis] Run EVA analysis using U-statistics theory approximation via GSReg.GeneSets.EVA

nextflow.enable.dsl = 2

process BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS {
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
    .bm_deps <- c("GSReg")
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
        library(GSReg)
        
        # Check for input files
        if (!file.exists("exprsdata.csv") || !file.exists("diracpathways.rds") || !file.exists("phenotypes.csv")) {
          stop("Required input files (exprsdata.csv, diracpathways.rds, phenotypes.csv) are missing in the working directory.")
        }
        
        # Read expression data
        exprsdata <- as.matrix(read.csv("exprsdata.csv", row.names=1, check.names=FALSE))
        
        # Clean NA/NaN values
        if (any(is.na(exprsdata)) || any(is.nan(exprsdata))) {
          keep_rows <- apply(exprsdata, 1, function(x) !any(is.na(x) | is.nan(x)))
          exprsdata <- exprsdata[keep_rows, , drop=FALSE]
        }
        
        # Read pathways
        diracpathways <- readRDS("diracpathways.rds")
        
        # Read phenotypes
        phenotypes_raw <- read.csv("phenotypes.csv", header=FALSE, stringsAsFactors=FALSE)
        if (nrow(phenotypes_raw) == ncol(exprsdata) + 1) {
          phenotypes <- phenotypes_raw[-1, 1]
        } else {
          phenotypes <- phenotypes_raw[[1]]
        }
        phenotypes <- as.character(phenotypes)
        
        # Filter pathways to ensure they have enough genes present in the expression matrix
        valid_genes <- rownames(exprsdata)
        diracpathways <- lapply(diracpathways, function(p) intersect(p, valid_genes))
        diracpathways <- diracpathways[sapply(diracpathways, length) >= 5]
        
        if (length(diracpathways) == 0) {
          stop("No pathways have 5 or more genes represented in the expression data.")
        }
        
        # Run DIRAC analysis with permutation testing and normal approximation
        Nperm = 10
        DIRACperm =GSReg.GeneSets.DIRAC(exprsdata,diracpathways,as.factor(phenotypes),Nperm=Nperm)
        DIRACAn =GSReg.GeneSets.DIRAC(exprsdata,diracpathways,as.factor(phenotypes))
        
        # Run EVA analysis using U-statistics theory approximation
        VarAnKendallV = GSReg.GeneSets.EVA(geneexpres=exprsdata, pathways=diracpathways, phenotypes=as.factor(phenotypes))
        
        # Save DIRAC results
        dirac_df <- data.frame(
          Pathway = names(DIRACAn\$pvalues),
          pvalue = DIRACAn\$pvalues,
          zscore = DIRACAn\$zscores,
          mu1 = DIRACAn\$mu1,
          mu2 = DIRACAn\$mu2,
          stringsAsFactors = FALSE
        )
        write.csv(dirac_df, "dirac_results.csv", row.names=FALSE)
        
        # Save EVA results
        eva_df <- data.frame(
          Pathway = names(VarAnKendallV),
          E1 = sapply(VarAnKendallV, function(x) x\$E1),
          E2 = sapply(VarAnKendallV, function(x) x\$E2),
          zscore = sapply(VarAnKendallV, function(x) x\$zscore),
          pvalue = sapply(VarAnKendallV, function(x) x\$pvalue),
          pvalueTotal = sapply(VarAnKendallV, function(x) x\$pvalueTotal),
          stringsAsFactors = FALSE
        )
        write.csv(eva_df, "eva_results.csv", row.names=FALSE)
        
        # Generate plots
        pdf("pathway_variability_plots.pdf", width=10, height=10)
        par(mfrow=c(2,2))
        
        # Plot 1: Hist of DIRAC p-values
        hist(DIRACAn\$pvalues, xlab="pvalue", main="Hist of pvalues applying DIRAC Analysis.")
        
        # Plot 2: DIRAC p-value comparisons
        plot(x=abs(DIRACAn\$zscores), y=DIRACperm\$pvalues, xlab="|Z-score|",
             ylab="p-value", col="red1", main="DIRAC p-value comparisons")
        zscorelin <- seq(min(abs(DIRACAn\$zscores)), max(abs(DIRACAn\$zscores)), by = 0.1)
        pvaltheoretic = (1-pnorm(zscorelin))*2
        lines(x=zscorelin, y=pvaltheoretic, type="l", pch=50, lty=5, col="darkblue")
        legend("topright", legend=c("permutation test", "Normal Approx."),
               col=c("red1", "blue"), text.col=c("red1", "blue"),
               lty=c(NA, 1), lwd=c(NA, 2.5), pch=c(21, NA))
        
        # Plot 3: P-value Hist of U-Stat
        pvalustat = sapply(VarAnKendallV, function(x) x\$pvalue)
        hist(x=pvalustat, breaks=20, main="P-value Hist of U-Stat", xlim=c(0,1))
        
        # Plot 4: P-value Comparison DIRAC vs EVA
        correlation <- tryCatch(cor(x=DIRACAn\$pvalues, y=pvalustat, use="complete.obs"), error=function(e) NA)
        plot(x=DIRACAn\$pvalues, y=pvalustat, xlab ="DIRAC",
             ylab="EVA", main=sprintf("P-value Comparison corr=%2.2g", correlation))
        lmfit = lm(pvalustat ~ DIRACAn\$pvalues - 1)
        abline(lmfit)
        
        dev.off()
        
        # Generate dysregulated pathways plots
        pdf("dysregulated_pathways_plots.pdf", width=12, height=6)
        par(mfrow=c(1,2))
        
        # DIRAC dysregulated
        significantPathwaysDIRAC = names(DIRACAn\$mu1)[which(DIRACAn\$pvalues < 0.05)]
        if (length(significantPathwaysDIRAC) > 0) {
          mu1 = DIRACAn\$mu1[significantPathwaysDIRAC]
          mu2 = DIRACAn\$mu2[significantPathwaysDIRAC]
          plot(x=mu1, y=mu2,
               xlim=c(0, max(c(mu1, mu2), na.rm=TRUE)), ylim=c(0, max(c(mu1, mu2), na.rm=TRUE)),
               xlab="normal", ylab="disease",
               main="DIRAC significantly dysregulated pathways")
          lines(x=c(0, max(c(mu1, mu2), na.rm=TRUE)), y=c(0, max(c(mu1, mu2), na.rm=TRUE)))
        } else {
          plot(1, type="n", axes=FALSE, xlab="", ylab="", main="No significant DIRAC pathways (p < 0.05)")
        }
        
        # EVA dysregulated
        significantPathwaysGSV = names(which(pvalustat < 0.05))
        if (length(significantPathwaysGSV) > 0) {
          eta1 = sapply(VarAnKendallV, function(x) x\$E1)[significantPathwaysGSV]
          eta2 = sapply(VarAnKendallV, function(x) x\$E2)[significantPathwaysGSV]
          plot(x=eta1, y=eta2,
               xlim=c(0, max(c(eta1, eta2), na.rm=TRUE)), ylim=c(0, max(c(eta1, eta2), na.rm=TRUE)),
               xlab="normal", ylab="disease",
               main="EVA: Dysregulated pathways")
          lines(x=c(0, max(c(eta1, eta2), na.rm=TRUE)), y=c(0, max(c(eta1, eta2), na.rm=TRUE)))
        } else {
          plot(1, type="n", axes=FALSE, xlab="", ylab="", main="No significant EVA pathways (p < 0.05)")
        }
        
        dev.off()

    writeLines(c(
        '"BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS":',
        paste0('    GSReg: ', as.character(packageVersion('GSReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_variability_analysis.csv versions.yml
    """
}

workflow BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprsdata.csv, diracpathways.rds, phenotypes.csv ] ]

    main:
    BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS.out.tables
    plots    = BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS.out.plots
    objects  = BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS.out.objects
    versions = BIOC_GSREG_PATHWAY_VARIABILITY_ANALYSIS.out.versions
}
