#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: atena — telescope_quantification
// Quantify transposable element expression from RNA-seq BAM files using the Telescope Bayesian EM reassignment method.
// Input: *.bam, rmskLTR
// Container: quay.io/biocontainers/bioconductor-atena:1.16.1--r45hdfd78af_0
// R packages: BiocParallel, SummarizedExperiment, atena
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SummarizedExperiment, atena
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Retrieve and parse TE annotations using annotaTEs() and getLTRs()
//  * 2. [Input & Preparation] Build the Telescope parameter object using TelescopeParam()
//  * 3. [Core Analysis] Quantify expression using qtex()

nextflow.enable.dsl = 2

process BIOC_ATENA_TELESCOPE_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("BiocParallel", "SummarizedExperiment", "atena")
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
    library(atena)
    library(BiocParallel)
    
    # Stage 1: Retrieve and parse TE annotations
    # We prioritize the user-provided rmskLTR file from the working directory
    # to ensure matching annotations for the user's BAM files.
    # If not found, we fall back to the documented online retrieval for dm6.
    rmskLTR_files <- list.files(pattern="^rmskLTR", full.names=TRUE)
    
    if (length(rmskLTR_files) > 0) {
      rmskLTR <- readRDS(rmskLTR_files[1])
    } else {
      message("Local 'rmskLTR' file not found. Attempting online annotation retrieval for 'dm6'.")
      teann <- tryCatch({
        annotaTEs(genome="dm6", parsefun=OneCodeToFindThemAll, strict=FALSE,
                  insert=500, BPPARAM=SerialParam(progress=FALSE))
      }, error = function(e) {
        stop("Error: Online annotation retrieval failed and no local 'rmskLTR' file found.")
      })
      
      rmskLTR <- getLTRs(teann, relLength=0.8, fullLength=TRUE, partial=TRUE,
                         otherLTR=TRUE)
    }
    
    # Locate BAM files from the working directory (replacing system.file)
    bamfiles <- list.files(path=".", pattern="\\\\.bam\$", full.names=TRUE)
    if (length(bamfiles) == 0) {
      stop("Error: No BAM files (*.bam) found in the working directory.")
    }
    
    # Stage 2: Build the Telescope parameter object
    tspar <- TelescopeParam(bfl=bamfiles, 
                            teFeatures=rmskLTR, 
                            singleEnd=TRUE, 
                            ignoreStrand=TRUE)
    
    # Stage 3: Quantify expression using qtex()
    tsq <- qtex(tspar)
    
    # Save meaningful results
    # 1. Save the SummarizedExperiment object
    saveRDS(tsq, file="telescope_quantification_results.rds")
    
    # 2. Save the count matrix as a CSV file
    write.csv(assay(tsq), file="telescope_counts.csv", row.names=TRUE)
    
    # 3. Generate a summary PDF plot of the quantified counts
    pdf("telescope_counts_summary.pdf", width=7, height=5)
    if (ncol(tsq) > 0) {
      barplot(colSums(assay(tsq)), 
              main="Telescope Quantified Reads per Sample", 
              col="skyblue", 
              las=2,
              ylab="Total Quantified Reads")
    } else {
      plot.new()
      text(0.5, 0.5, "No samples to plot", cex=1.5)
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'telescope_quantification_results.rds', 'telescope_counts.csv', and 'telescope_counts_summary.pdf'.")

    writeLines(c(
        '"BIOC_ATENA_TELESCOPE_QUANTIFICATION":',
        paste0('    atena: ', as.character(packageVersion('atena')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_telescope_quantification.csv versions.yml
    """
}

workflow BIOC_ATENA_TELESCOPE_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ *.bam, rmskLTR ] ]

    main:
    BIOC_ATENA_TELESCOPE_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_ATENA_TELESCOPE_QUANTIFICATION.out.tables
    plots    = BIOC_ATENA_TELESCOPE_QUANTIFICATION.out.plots
    objects  = BIOC_ATENA_TELESCOPE_QUANTIFICATION.out.objects
    versions = BIOC_ATENA_TELESCOPE_QUANTIFICATION.out.versions
}
