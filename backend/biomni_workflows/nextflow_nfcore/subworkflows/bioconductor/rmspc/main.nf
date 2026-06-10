#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmspc — peak_calling_from_bed_files
// Run MSPC peak calling using paths to BED files as input.
// Input: rep1.bed, rep2.bed
// Container: quay.io/biocontainers/bioconductor-rmspc:1.16.0--r45hdfd78af_0
// R packages: biocmanager, GenomicRanges, rmspc, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmspc:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("biocmanager", "GenomicRanges", "rmspc", "rtracklayer")
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
    library(rmspc)
    library(GenomicRanges)
    
    # 1. Define paths to input BED files (from the working directory)
    input1 <- "rep1.bed"
    input2 <- "rep2.bed"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(input1) || !file.exists(input2)) {
      stop("Required input files 'rep1.bed' and/or 'rep2.bed' are missing from the working directory.")
    }
    
    input <- c(input1, input2)
    
    # 2. Run the mspc function with BED file paths and threshold parameters
    results <- mspc(
        input = input, replicateType = "Technical",
        stringencyThreshold = 1e-8,
        weakThreshold = 1e-4, gamma = 1e-8,
        keep = FALSE, GRanges = TRUE,
        multipleIntersections = "Lowest",
        c = 2, alpha = 0.05)
    
    # 3. Retrieve status and GRanges output objects
    status <- results\$status
    gr_objects <- results\$GRangesObjects
    
    # Print status and head of GRangesObjects to console
    cat("MSPC Execution Status:", status, "\n")
    print(head(gr_objects, 3))
    
    # Access specific GRanges objects as documented
    consensus_peaks <- results\$GRangesObjects\$ConsensusPeaks
    rep1_background <- results\$GRangesObjects\$`rep1/Background`
    
    # 4. Write named output files for the meaningful results
    # Save the complete results object as an RDS file
    saveRDS(results, file = "mspc_results.rds")
    
    # Export Consensus Peaks to a CSV file
    if (!is.null(consensus_peaks)) {
      consensus_df <- as.data.frame(consensus_peaks)
      write.csv(consensus_df, file = "consensus_peaks.csv", row.names = FALSE)
    }
    
    # Export Replicate 1 Background Peaks to a CSV file
    if (!is.null(rep1_background)) {
      rep1_bg_df <- as.data.frame(rep1_background)
      write.csv(rep1_bg_df, file = "rep1_background_peaks.csv", row.names = FALSE)
    }
    
    # Export other available GRanges objects to CSV files
    for (name in names(gr_objects)) {
      # Replace slashes in names to avoid directory path issues when saving files
      safe_name <- gsub("/", "_", name)
      gr_df <- as.data.frame(gr_objects[[name]])
      write.csv(gr_df, file = paste0("mspc_", safe_name, ".csv"), row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES":
        rmspc: \$(Rscript -e 'cat(as.character(packageVersion("rmspc")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_calling_from_bed_files.csv versions.yml
    """
}

workflow BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rep1.bed, rep2.bed ] ]

    main:
    BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES(ch_input)

    emit:
    tables   = BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES.out.tables
    plots    = BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES.out.plots
    objects  = BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES.out.objects
    versions = BIOC_RMSPC_PEAK_CALLING_FROM_BED_FILES.out.versions
}
