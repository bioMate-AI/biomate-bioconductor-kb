#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCseq — time_course_sequencing_analysis
// Perform differential analysis and temporal pattern clustering on time-course sequencing data (RNA-seq, ATAC-seq, or ChIP-seq).
// Input: experiment_design.txt, genomic_intervals.bed, counts_table.txt
// Container: quay.io/biocontainers/bioconductor-tcseq:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, TCseq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate reference genomic regions from peak files (optional)
//  * 2. [Input & Preparation] Create a TCA object
//  * 3. [Core Analysis] Count reads from BAM files (optional)
//  * 4. [Core Analysis] Perform differential analysis
//  * 5. [Core Analysis] Extract differential analysis results
//  * 6. [Input & Preparation] Construct a time course table
//  * 7. [Core Analysis] Perform temporal clustering
//  * 8. [Visualization & Output] Visualize temporal patterns

nextflow.enable.dsl = 2

process BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS {
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
    .bm_deps <- c("TCseq", "SummarizedExperiment")
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
    library(TCseq)
    suppressWarnings(library(SummarizedExperiment))
    
    # Check for required input files
    if (!file.exists("experiment_design.txt")) {
      stop("Error: 'experiment_design.txt' not found in the working directory.")
    }
    if (!file.exists("genomic_intervals.bed")) {
      stop("Error: 'genomic_intervals.bed' not found in the working directory.")
    }
    
    # Read experiment design
    experiment <- read.delim("experiment_design.txt", header = TRUE, stringsAsFactors = FALSE)
    # Fix for Bug 2: Set rownames to match sample IDs (colnames of countsTable)
    rownames(experiment) <- experiment[, 1]
    
    # Read genomic intervals (BED format) and format to match TCseq expectations: chr, start, end, id
    genomicIntervals_raw <- read.delim("genomic_intervals.bed", header = FALSE, stringsAsFactors = FALSE)
    genomicIntervals <- data.frame(
      chr = genomicIntervals_raw[, 1],
      start = as.integer(genomicIntervals_raw[, 2]),
      end = as.integer(genomicIntervals_raw[, 3]),
      stringsAsFactors = FALSE
    )
    if (ncol(genomicIntervals_raw) >= 4) {
      genomicIntervals\$id <- as.character(genomicIntervals_raw[, 4])
    } else {
      genomicIntervals\$id <- paste0("peak", 1:nrow(genomicIntervals))
    }
    
    # 1. Generate reference genomic regions from peak files (optional)
    if (dir.exists("peaks")) {
      dir.peaks <- "peaks"
      gf <- peakreference(dir = dir.peaks, pattern = "narrowpeaks")
      write.csv(gf, "peak_reference.csv", row.names = FALSE)
    }
    
    # Determine counts source and create TCA object
    # Fix for Bug 1: Create the TCA object exactly once, removing redundant methods copied from the vignette
    if (file.exists("counts_table.txt")) {
      countsTable <- as.matrix(read.delim("counts_table.txt", row.names = 1, header = TRUE, check.names = FALSE))
      tca <- TCA(design = experiment, genomicFeature = genomicIntervals, counts = countsTable)
    } else if ("bamfile" %in% colnames(experiment)) {
      # 2. Create a TCA object using BAM files
      tca <- TCA(design = experiment, genomicFeature = genomicIntervals)
      
      # 3. Count reads from BAM files (optional)
      dir.BAM <- "."
      tca <- countReads(tca, dir = dir.BAM)
    } else {
      stop("Error: 'counts_table.txt' is missing, and no 'bamfile' column is present in 'experiment_design.txt' to count reads.")
    }
    
    # 4. Perform differential analysis
    # Fix for Bug 3: Remove redundant DBanalysis call
    tca <- DBanalysis(tca, filter.type = "raw", filter.value = 10, samplePassfilter = 2)
    
    # Extract differential analysis results dynamically based on design
    timepoints <- unique(as.character(experiment\$timepoint))
    if (length(timepoints) < 2) {
      stop("Error: At least two timepoints are required in 'experiment_design.txt' for differential analysis.")
    }
    g1 <- timepoints[1]
    g2 <- timepoints[-1]
    
    # 5. Extract differential analysis results
    DBres <- DBresult(tca, group1 = g1, group2 = g2)
    DBres.sig <- DBresult(tca, group1 = g1, group2 = g2, top.sig = TRUE)
    
    # Save differential analysis results
    saveRDS(DBres, "DBres.rds")
    saveRDS(DBres.sig, "DBres_sig.rds")
    
    for (comparison in names(DBres)) {
      write.csv(as.data.frame(DBres[[comparison]]), paste0("DBres_", comparison, ".csv"))
    }
    for (comparison in names(DBres.sig)) {
      write.csv(as.data.frame(DBres.sig[[comparison]]), paste0("DBres_sig_", comparison, ".csv"))
    }
    
    # 6. Construct a time course table
    # Fix for Bug 3: Remove redundant timecourseTable call
    tca <- timecourseTable(tca, value = "expression", norm.method = "rpkm", filter = TRUE)
    t <- tcTable(tca)
    
    # Save time course table
    write.csv(t, "timecourse_table.csv")
    
    # 7. Perform temporal clustering
    # Ensure k is appropriate for the number of rows in the time course table
    k_val <- min(6, nrow(t) - 1)
    if (k_val < 2) {
      warning("Too few rows in time course table to perform clustering with k=6. Setting k=2.")
      k_val <- 2
    }
    
    if (nrow(t) >= 2) {
      tca <- timeclust(tca, algo = "cm", k = k_val, standardize = TRUE)
      saveRDS(tca, "tca_clustered.rds")
      
      # 8. Visualize temporal patterns
      pdf("temporal_patterns_plots.pdf", width = 10, height = 8)
      p <- timeclustplot(tca, value = "z-score(PRKM)", cols = min(3, k_val))
      if (length(p) > 0) {
        print(p[[1]])
      }
      dev.off()
    } else {
      warning("Skipping clustering and plotting because the time course table has fewer than 2 rows after filtering.")
    }
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS":',
        paste0('    TCseq: ', as.character(packageVersion('TCseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_sequencing_analysis.csv versions.yml
    """
}

workflow BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experiment_design.txt, genomic_intervals.bed, counts_table.txt ] ]

    main:
    BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.tables
    plots    = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.plots
    objects  = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.objects
    versions = BIOC_TCSEQ_TIME_COURSE_SEQUENCING_ANALYSIS.out.versions
}
