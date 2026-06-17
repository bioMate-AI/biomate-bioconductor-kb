#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ATACseqTFEA — step_by_step_tfea
// Perform transcription factor enrichment analysis step-by-step to allow parameter tuning at intermediate stages.
// Input: bamExp.bam, bamCtl.bam, bindingSites.granges
// Container: quay.io/biocontainers/bioconductor-atacseqtfea:1.12.0--r45hdfd78af_0
// R packages: ATACseqTFEA, GenomicRanges, Rsamtools, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: ATACseqTFEA, GenomicRanges, Rsamtools, Tal1, ggplot2
// Visualizations: enrichment plot
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Expand binding sites to define proximal and distal regions using expandBindingSites
//  * 2. [Core Analysis] Count 5' ends of reads in the defined regions using count5ends
//  * 3. [Core Analysis] Filter low-count binding sites using eventsFilter
//  * 4. [Core Analysis] Normalize counts to count per base (CPB) using countsNormalization
//  * 5. [Core Analysis] Calculate weighted binding scores using getWeightedBindingScore
//  * 6. [Core Analysis] Perform differential binding analysis using DBscore
//  * 7. [Core Analysis] Run TF enrichment analysis using doTFEA
//  * 8. [Visualization & Output] Plot enrichment scores using plotES

nextflow.enable.dsl = 2

process BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ATACseqTFEA", "GenomicRanges", "Rsamtools", "ggplot2")
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
        library(ATACseqTFEA)
        library(GenomicRanges)
        library(Rsamtools)
        library(ggplot2)
        
        # 1. Load User Inputs
        message("Loading user inputs...")
        bindingSites <- readRDS("bindingSites.granges")
        
        # Define BAM files by parsing a comma-separated string to allow multiple biological replicates
        args <- commandArgs(trailingOnly = TRUE)
        if (length(args) >= 2) {
          bamExp_str <- args[1]
          bamCtl_str <- args[2]
        } else {
          bamExp_str <- "bamExp.bam"
          bamCtl_str <- "bamCtl.bam"
        }
        
        bamExp <- trimws(unlist(strsplit(bamExp_str, ",")))
        bamCtl <- trimws(unlist(strsplit(bamCtl_str, ",")))
        
        # Ensure BAM files are indexed
        message("Checking BAM index files...")
        for (bam in c(bamExp, bamCtl)) {
          if (!file.exists(paste0(bam, ".bai"))) {
            Rsamtools::indexBam(bam)
          }
        }
        
        # 2. Step-by-step TFEA Workflow
        
        # Stage 1: Expand binding sites to define proximal and distal regions
        message("Expanding binding sites...")
        exbs <- expandBindingSites(bindingSites=bindingSites,
                                   proximal=40,
                                   distal=40,
                                   gap=10)
        
        # Stage 2: Count 5' ends of reads in the defined regions
        message("Counting 5' ends...")
        counts <- count5ends(bam=c(bamExp, bamCtl),
                             positive=0L, negative=0L,
                             bindingSites = bindingSites,
                             bindingSitesWithGap=exbs\$bindingSitesWithGap,
                             bindingSitesWithProximal=exbs\$bindingSitesWithProximal,
                             bindingSitesWithProximalAndGap=
                                 exbs\$bindingSitesWithProximalAndGap,
                             bindingSitesWithDistal=exbs\$bindingSitesWithDistal)
        
        # Stage 3: Filter low-count binding sites
        message("Filtering counts...")
        print(colnames(counts))
        counts <- eventsFilter(counts, "proximalRegion>0")
        
        # Stage 4: Normalize counts to count per base (CPB)
        message("Normalizing counts...")
        counts <- countsNormalization(counts, proximal=40, distal=40)
        
        # Stage 5: Calculate weighted binding scores
        message("Calculating weighted binding scores...")
        counts <- getWeightedBindingScore(counts)
        
        # Stage 6: Perform differential binding analysis
        message("Performing differential binding analysis...")
        n_exp <- length(bamExp)
        n_ctl <- length(bamCtl)
        design <- cbind(CTL=1, EXPvsCTL=c(rep(1, n_exp), rep(0, n_ctl)))
        counts <- DBscore(counts, design=design, coef="EXPvsCTL")
        
        # Stage 7: Run TF enrichment analysis
        message("Running TF enrichment analysis...")
        res <- doTFEA(counts)
        print(res)
        
        # Stage 8: Plot enrichment scores
        message("Plotting enrichment scores...")
        # Determine TF to plot (use the top TF from results, or default if empty)
        if (!is.null(res\$resultsTable) && nrow(res\$resultsTable) > 0) {
          TF <- res\$resultsTable\$TF[1]
        } else {
          TF <- "Tal1::Gata1"
        }
        
        p <- plotES(res, TF=TF, outfolder=NA)
        
        # Save outputs
        message("Saving outputs...")
        write.csv(res\$resultsTable, "tfea_results.csv", row.names=FALSE)
        saveRDS(res, "tfea_results.rds")
        
        if (!is.null(p)) {
          ggplot2::ggsave("enrichment_score_plot.pdf", plot = p, width = 7, height = 5)
        }
        
        message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA":',
        paste0('    ATACseqTFEA: ', as.character(packageVersion('ATACseqTFEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_tfea.csv versions.yml
    """
}

workflow BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamExp.bam, bamCtl.bam, bindingSites.granges ] ]

    main:
    BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA(ch_input)

    emit:
    tables   = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.tables
    plots    = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.plots
    objects  = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.objects
    versions = BIOC_ATACSEQTFEA_STEP_BY_STEP_TFEA.out.versions
}
