#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: atena — ervmap_quantification
// Quantify transposable element expression from RNA-seq BAM files using the ERVmap selective filtering method.
// Input: *.bam, rmskLTR
// Container: quay.io/biocontainers/bioconductor-atena:1.16.1--r45hdfd78af_0
// R packages: Rsamtools, SummarizedExperiment, atena, BiocParallel, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Rsamtools, SummarizedExperiment, atena
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Retrieve and parse TE annotations using annotaTEs() and getLTRs()
//  * 2. [Input & Preparation] Build the ERVmap parameter object using ERVmapParam()
//  * 3. [Core Analysis] Quantify expression using qtex()

nextflow.enable.dsl = 2

process BIOC_ATENA_ERVMAP_QUANTIFICATION {
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
    .bm_deps <- c("Rsamtools", "SummarizedExperiment", "atena", "BiocParallel", "RColorBrewer")
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
    library(SummarizedExperiment)
    library(BiocParallel)
    library(Rsamtools)
    
    # Read BAM files from the working directory (replacing system.file demo data)
    bamfiles <- list.files(path=".", pattern="\\\\.bam\$", full.names=TRUE)
    
    if (length(bamfiles) == 0) {
      stop("Error: No BAM files (*.bam) found in the working directory.")
    }
    
    message(paste("Found", length(bamfiles), "BAM file(s) for quantification."))
    
    # 1. Retrieve and parse TE annotations
    # The pipeline first attempts to read the user-provided rmskLTR object from the working directory.
    # If not present, it falls back to retrieving and parsing the annotations as documented.
    if (file.exists("rmskLTR.rds")) {
      message("Reading user-provided rmskLTR from rmskLTR.rds...")
      rmskLTR <- readRDS("rmskLTR.rds")
    } else {
      message("rmskLTR.rds not found in working directory. Retrieving and parsing TE annotations...")
      
      # Extract genome from the BAM file header to avoid hardcoding
      bam_seqinfo <- seqinfo(BamFile(bamfiles[1]))
      bam_genome <- unique(na.omit(genome(bam_seqinfo)))
      
      if (length(bam_genome) == 0) {
        stop("Error: rmskLTR.rds not found and genome cannot be determined from BAM file header.")
      }
      
      # Documented step to parse annotations using OneCodeToFindThemAll
      teann <- annotaTEs(genome=bam_genome[1], parsefun=OneCodeToFindThemAll, strict=FALSE,
                         insert=500, BPPARAM=SerialParam(progress=FALSE))
      
      # Documented step to filter and get LTRs
      rmskLTR <- getLTRs(teann, relLength=0.8, fullLength=TRUE, partial=TRUE,
                         otherLTR=TRUE)
      
      # Save the parsed annotations for future runs
      saveRDS(rmskLTR, file="rmskLTR.rds")
    }
    
    # 2. Build the ERVmap parameter object using ERVmapParam()
    empar <- ERVmapParam(bamfiles, 
                         teFeatures=rmskLTR, 
                         singleEnd=TRUE, 
                         ignoreStrand=TRUE, 
                         suboptimalAlignmentCutoff=NA)
    
    # 3. Quantify expression using qtex()
    message("Quantifying transposable element expression using ERVmap selective filtering...")
    emq <- qtex(empar)
    
    # Write named output files for the meaningful results
    message("Writing output files...")
    
    # Save the complete SummarizedExperiment object
    saveRDS(emq, file="ervmap_quantification_results.rds")
    
    # Save the quantified expression counts matrix as a CSV
    counts_matrix <- assay(emq)
    write.csv(counts_matrix, file="ervmap_counts.csv", row.names=TRUE)
    
    # Save the feature metadata (rowData) as a CSV
    feature_metadata <- as.data.frame(rowData(emq))
    write.csv(feature_metadata, file="ervmap_feature_metadata.csv", row.names=TRUE)
    
    message("Pipeline completed successfully. Outputs saved to 'ervmap_quantification_results.rds', 'ervmap_counts.csv', and 'ervmap_feature_metadata.csv'.")

    writeLines(c(
        '"BIOC_ATENA_ERVMAP_QUANTIFICATION":',
        paste0('    atena: ', as.character(packageVersion('atena')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ervmap_quantification.csv versions.yml
    """
}

workflow BIOC_ATENA_ERVMAP_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ *.bam, rmskLTR ] ]

    main:
    BIOC_ATENA_ERVMAP_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_ATENA_ERVMAP_QUANTIFICATION.out.tables
    plots    = BIOC_ATENA_ERVMAP_QUANTIFICATION.out.plots
    objects  = BIOC_ATENA_ERVMAP_QUANTIFICATION.out.objects
    versions = BIOC_ATENA_ERVMAP_QUANTIFICATION.out.versions
}
