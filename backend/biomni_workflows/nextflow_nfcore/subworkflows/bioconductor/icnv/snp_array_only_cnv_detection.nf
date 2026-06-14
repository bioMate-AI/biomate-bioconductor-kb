#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCNV — snp_array_only_cnv_detection
// Detect CNVs using only SNP array data.
// Input: snp_lrr, snp_lrr.pos, snp_baf, snp_baf.pos
// Container: quay.io/biocontainers/bioconductor-icnv:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iCNV
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run SNP array-only CNV detection using iCNV_detection with CN=1
//  * 2. [Visualization & Output] Format output using output_list
//  * 3. [Visualization & Output] Plot results using plotHMMscore

nextflow.enable.dsl = 2

process BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("iCNV")
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
    library(iCNV)
    
    # Define input file paths (expecting RDS format in the working directory)
    snp_lrr_file <- "snp_lrr.rds"
    snp_lrr_pos_file <- "snp_lrr.pos.rds"
    snp_baf_file <- "snp_baf.rds"
    snp_baf_pos_file <- "snp_baf.pos.rds"
    
    # Check for existence of required files
    required_files <- c(snp_lrr_file, snp_lrr_pos_file, snp_baf_file, snp_baf_pos_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", paste(missing_files, collapse = ", ")))
    }
    
    # Read user input files
    message("Reading input files...")
    snp_lrr <- readRDS(snp_lrr_file)
    snp_lrr.pos <- readRDS(snp_lrr_pos_file)
    snp_baf <- readRDS(snp_baf_file)
    snp_baf.pos <- readRDS(snp_baf_pos_file)
    
    # Determine or construct sample names (sampname_qc)
    sampname_qc <- NULL
    if (file.exists("sampname_qc.rds")) {
      sampname_qc <- readRDS("sampname_qc.rds")
    } else if (file.exists("sampname_qc.txt")) {
      sampname_qc <- readLines("sampname_qc.txt")
    } else {
      sampname_qc <- names(snp_lrr)
      if (is.null(sampname_qc)) {
        sampname_qc <- paste0("Sample_", seq_along(snp_lrr))
      }
    }
    
    # 1. Run SNP array-only CNV detection using iCNV_detection with CN=1
    message("Running iCNV detection...")
    projectname <- 'icnv.demo.snp'
    icnv_res0_snp <- iCNV_detection(snp_lrr=snp_lrr, snp_baf = snp_baf, 
                                 snp_lrr.pos = snp_lrr.pos,snp_baf.pos = snp_baf.pos,
                                 projname=projectname,CN=1,mu=c(-3,0,2),cap=TRUE,visual = 2)
    
    # Save the raw HMM detection results
    saveRDS(icnv_res0_snp, file = paste0(projectname, "_res0_snp.rds"))
    
    # 2. Format output using output_list
    message("Formatting output list...")
    icnv.output <- output_list(icnv_res0_snp,sampname_qc,CN=1)
    print(head(icnv.output))
    
    # Save the formatted output table
    write.csv(icnv.output, file = paste0(projectname, "_output.csv"), row.names = FALSE)
    
    # 3. Plot results using plotHMMscore
    message("Plotting HMM scores...")
    pdf(file = paste0(projectname, "_HMMscore_plot.pdf"), width = 10, height = 8)
    plotHMMscore(icnv_res0_snp,title=projectname)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION":',
        paste0('    iCNV: ', as.character(packageVersion('iCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_array_only_cnv_detection.csv versions.yml
    """
}

workflow BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snp_lrr, snp_lrr.pos, snp_baf, snp_baf.pos ] ]

    main:
    BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION(ch_input)

    emit:
    tables   = BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION.out.tables
    plots    = BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION.out.plots
    objects  = BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION.out.objects
    versions = BIOC_ICNV_SNP_ARRAY_ONLY_CNV_DETECTION.out.versions
}
