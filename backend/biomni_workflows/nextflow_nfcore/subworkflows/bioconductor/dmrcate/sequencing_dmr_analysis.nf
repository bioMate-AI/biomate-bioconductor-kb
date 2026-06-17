#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcate — sequencing_dmr_analysis
// Identify and plot differentially methylated regions from sequencing-based methylation data (WGBS).
// Input: bis_1072, methdesign, cont.mat
// Container: quay.io/biocontainers/bioconductor-dmrcate:3.6.0--r45hdfd78af_0
// R packages: DMRcate, SummarizedExperiment, bsseq
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcate, SummarizedExperiment, bsseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Annotate sequencing data and model differential
//  * 2. [Visualization & Output] Adjust the FDR threshold of the annotated object
//  * 3. [Visualization & Output] Call DMRs
//  * 4. [Visualization & Output] Extract genomic coordinates of the identified DMRs
//  * 5. [Visualization & Output] Plot specific DMRs

nextflow.enable.dsl = 2

process BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS {
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
    .bm_deps <- c("DMRcate", "SummarizedExperiment", "bsseq")
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
    library(DMRcate)
    library(SummarizedExperiment)
    library(bsseq)
    
    # Helper function to read RDS files robustly
    read_input <- function(name) {
      if (file.exists(name)) {
        return(readRDS(name))
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else {
        stop(paste("Required input file not found:", name))
      }
    }
    
    # Read user input files
    bis_1072 <- read_input("bis_1072")
    methdesign <- read_input("methdesign")
    cont.mat <- read_input("cont.mat")
    
    # Extract tissue and set up colors for plotting
    tissue <- factor(colData(bis_1072)\$tissue)
    unique_tissues <- unique(tissue)
    color_palette <- c("darkorange", "maroon", "blue", "black", "magenta")
    color_map <- color_palette[1:length(unique_tissues)]
    names(color_map) <- unique_tissues
    cols <- color_map[as.character(tissue)]
    names(cols) <- tissue
    
    # --- Annotate sequencing data and model differential ---
    seq_annot <- sequencing.annotate(bis_1072, methdesign, all.cov = TRUE, 
                                     contrasts = TRUE, cont.matrix = cont.mat, 
                                     coef = "treg_vs_tcon", fdr=0.05)
    
    # --- Adjust the FDR threshold of the annotated object ---
    seq_annot <- changeFDR(seq_annot, 0.25)
    
    # --- Call DMRs ---
    dmrcate.res <- dmrcate(seq_annot, C=2, min.cpgs = 5)
    
    # --- Extract genomic coordinates of the identified DMRs ---
    treg_vs_tcon.ranges <- extractRanges(dmrcate.res, genome="mm10")
    
    # Save results
    saveRDS(dmrcate.res, "dmrcate_res.rds")
    saveRDS(treg_vs_tcon.ranges, "treg_vs_tcon_ranges.rds")
    write.csv(as.data.frame(treg_vs_tcon.ranges), "treg_vs_tcon_ranges.csv", row.names=FALSE)
    
    # --- Plot specific DMRs ---
    tryCatch({
      if (length(treg_vs_tcon.ranges) >= 1) {
        pdf("treg_vs_tcon_dmr1_plot.pdf", width=10, height=8)
        DMR.plot(treg_vs_tcon.ranges, dmr = 1, 
                 CpGs=bis_1072[,tissue %in% c("Lymph_N_Tcon", "Lymph_N_Treg")], 
                 phen.col = cols[tissue %in% c("Lymph_N_Tcon", "Lymph_N_Treg")], 
                 genome="mm10")
        dev.off()
      } else {
        warning("No DMRs found to plot.")
      }
    }, error = function(e) {
      warning("Plotting failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS":',
        paste0('    DMRcate: ', as.character(packageVersion('DMRcate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequencing_dmr_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bis_1072, methdesign, cont.mat ] ]

    main:
    BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS.out.tables
    plots    = BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS.out.plots
    objects  = BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS.out.objects
    versions = BIOC_DMRCATE_SEQUENCING_DMR_ANALYSIS.out.versions
}
