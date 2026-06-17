#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVMetrics — cnv_profile_simulation
// Generate simulated copy number profiles from a reference sample to assess metric significance.
// Input: reference_sample.txt
// Container: quay.io/biocontainers/bioconductor-cnvmetrics:1.14.2--r45hdfd78af_0
// R packages: CNVMetrics, GenomicRanges
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVMetrics, GenomicRanges
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the reference sample as a GRanges object
//  * 2. [Core Analysis] Set the random seed to ensure reproducibility
//  * 3. [Core Analysis] Generate simulated profiles using processSim()

nextflow.enable.dsl = 2

process BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("CNVMetrics", "GenomicRanges")
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
    library(GenomicRanges)
    library(CNVMetrics)
    
    # Define input file path
    input_file <- "reference_sample.txt"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    # Read the reference sample data
    # Expected columns: chromosome/seqnames, start, end, state, log2ratio
    ref_data <- read.table(input_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Validate required columns
    required_cols <- c("chromosome", "start", "end", "state", "log2ratio")
    if (!all(required_cols %in% colnames(ref_data))) {
      # Fallback to check if 'seqnames' is used instead of 'chromosome'
      if ("seqnames" %in% colnames(ref_data)) {
        colnames(ref_data)[colnames(ref_data) == "seqnames"] <- "chromosome"
      } else {
        stop(paste("Error: Input file must contain the following columns:", paste(required_cols, collapse = ", ")))
      }
    }
    
    # 1. Define the reference sample as a GRanges object
    sampleRef <- GRanges(
      seqnames = ref_data\$chromosome,
      ranges = IRanges(start = ref_data\$start, end = ref_data\$end),
      strand = "*",
      state = ref_data\$state,
      log2ratio = ref_data\$log2ratio
    )
    
    # 2. Set the random seed to ensure reproducibility
    set.seed(121)
    
    # 3. Generate simulated profiles using processSim()
    simRes <- processSim(curSample = sampleRef, nbSim = 3)
    
    # Write the simulated profiles to a tab-delimited output file
    output_file <- "simulated_profiles.txt"
    write.table(simRes, file = output_file, sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Save the simulated profiles as an RDS object for downstream R analyses
    saveRDS(simRes, file = "simulated_profiles.rds")
    
    cat(paste("Simulation completed successfully. Results written to", output_file, "and simulated_profiles.rds\n"))

    writeLines(c(
        '"BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION":',
        paste0('    CNVMetrics: ', as.character(packageVersion('CNVMetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_profile_simulation.csv versions.yml
    """
}

workflow BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_sample.txt ] ]

    main:
    BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION(ch_input)

    emit:
    tables   = BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION.out.tables
    plots    = BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION.out.plots
    objects  = BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION.out.objects
    versions = BIOC_CNVMETRICS_CNV_PROFILE_SIMULATION.out.versions
}
