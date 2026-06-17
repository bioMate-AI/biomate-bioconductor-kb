#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylPipe — differential_methylation_analysis
// Identify and consolidate differentially methylated regions (DMRs) between experimental groups.
// Input: H1.IMR90.set, GR_chr20
// Container: quay.io/biocontainers/bioconductor-methylpipe:1.44.0--r45h01b2380_0
// R packages: GenomicRanges, methylPipe
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, methylPipe
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find candidate DMRs using findDMR
//  * 2. [Core Analysis] Consolidate and filter DMRs based on p-value and distance thresholds using consolidateDMRs

nextflow.enable.dsl = 2

process BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "methylPipe")
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
    library(methylPipe)
    library(GenomicRanges)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files from the Working Directory
    # ----------------------------------------------------------------------
    
    # Read H1.IMR90.set (BSdataSet object)
    if (file.exists("H1.IMR90.set")) {
      H1.IMR90.set <- readRDS("H1.IMR90.set")
    } else if (file.exists("H1.IMR90.set.rds")) {
      H1.IMR90.set <- readRDS("H1.IMR90.set.rds")
    } else if (file.exists("H1.IMR90.set.Rdata")) {
      load("H1.IMR90.set.Rdata")
    } else {
      stop("Required input file 'H1.IMR90.set' (BSdataSet) not found in the working directory.")
    }
    
    # Read GR_chr20 (GRanges object)
    if (file.exists("GR_chr20")) {
      GR_chr20 <- readRDS("GR_chr20")
    } else if (file.exists("GR_chr20.rds")) {
      GR_chr20 <- readRDS("GR_chr20.rds")
    } else if (file.exists("GR_chr20.Rdata")) {
      load("GR_chr20.Rdata")
    } else {
      stop("Required input file 'GR_chr20' (GRanges) not found in the working directory.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Run Differential Methylation Analysis (Documented Workflow)
    # ----------------------------------------------------------------------
    
    # Step 1: Find candidate DMRs
    DMRs <- findDMR(object= H1.IMR90.set, Nproc=1, ROI=GR_chr20, MCClass='mCG',
         dmrSize=6, dmrBp=800)
    
    # Step 2: Consolidate and filter DMRs based on p-value and distance thresholds
    hyper.DMRs.conso <- consolidateDMRs(DmrGR=DMRs, pvThr=0.05, GAP=100, type="hyper")
    
    # ----------------------------------------------------------------------
    # 3. Write Output Files
    # ----------------------------------------------------------------------
    
    # Save raw DMRs
    saveRDS(DMRs, file = "DMRs_raw.rds")
    write.csv(as.data.frame(DMRs), file = "DMRs_raw.csv", row.names = FALSE)
    
    # Save consolidated hyper-methylated DMRs
    saveRDS(hyper.DMRs.conso, file = "DMRs_consolidated_hyper.rds")
    write.csv(as.data.frame(hyper.DMRs.conso), file = "DMRs_consolidated_hyper.csv", row.names = FALSE)
    
    # Generate diagnostic plots of the identified DMRs
    pdf("DMR_analysis_summary.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    if (length(DMRs) > 0) {
      hist(DMRs\$pValue, 
           breaks = 20, 
           col = "skyblue", 
           main = "Distribution of Raw DMR p-values", 
           xlab = "p-value")
      abline(v = 0.05, col = "red", lty = 2, lwd = 2)
    } else {
      plot.new()
      text(0.5, 0.5, "No raw DMRs detected to plot", cex = 1.2)
    }
    
    if (length(hyper.DMRs.conso) > 0) {
      hist(hyper.DMRs.conso\$MethDiff_Perc, 
           breaks = 10, 
           col = "salmon", 
           main = "Consolidated Hyper-DMRs\nMethylation Difference (%)", 
           xlab = "Methylation Difference (%)")
    } else {
      plot.new()
      text(0.5, 0.5, "No consolidated hyper-DMRs to plot", cex = 1.2)
    }
    
    dev.off()
    
    cat("Differential methylation analysis completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - DMRs_raw.rds / .csv\n")
    cat(" - DMRs_consolidated_hyper.rds / .csv\n")
    cat(" - DMR_analysis_summary.pdf\n")

    writeLines(c(
        '"BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS":',
        paste0('    methylPipe: ', as.character(packageVersion('methylPipe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H1.IMR90.set, GR_chr20 ] ]

    main:
    BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_METHYLPIPE_DIFFERENTIAL_METHYLATION_ANALYSIS.out.versions
}
