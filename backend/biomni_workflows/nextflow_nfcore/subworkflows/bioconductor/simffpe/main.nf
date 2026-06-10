#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SimFFPE — genome_wide_simulation
// Simulate FFPE NGS reads across whole genomes, chromosomes, or large genomic regions.
// Input: example.bam, regionsBam.txt, example.fasta
// Container: quay.io/biocontainers/bioconductor-simffpe:1.22.0--r45hdfd78af_0
// R packages: Biostrings, SimFFPE
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, SimFFPE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate Phred score profile from a BAM file
//  * 2. [Input & Preparation] Load reference genome sequences
//  * 3. [Core Analysis] Simulate reads using readSimFFPE

nextflow.enable.dsl = 2

process BIOC_SIMFFPE_GENOME_WIDE_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("Biostrings", "SimFFPE")
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
    library(SimFFPE)
    library(Biostrings)
    
    # Define input file paths (reading EXACTLY the declared user input files from the working directory)
    bamFilePath <- "example.bam"
    regionPath <- "regionsBam.txt"
    referencePath <- "example.fasta"
    
    # Verify input files exist
    if (!file.exists(bamFilePath)) {
      stop(paste("Required input BAM file is missing:", bamFilePath))
    }
    if (!file.exists(regionPath)) {
      stop(paste("Required input regions file is missing:", regionPath))
    }
    if (!file.exists(referencePath)) {
      stop(paste("Required input reference FASTA file is missing:", referencePath))
    }
    
    # 1. Estimate Phred score profile from the user's BAM file
    message("Reading target regions...")
    regions <- read.table(regionPath)
    
    message("Estimating Phred score profile...")
    # We store the result in PhredScoreProfile2 to match the variable name used in the documented readSimFFPE call
    PhredScoreProfile2 <- calcPhredScoreProfile(bamFilePath, targetRegions = regions)
    
    # Save the estimated Phred profile matrix as an RDS file for downstream analysis/inspection
    saveRDS(PhredScoreProfile2, file = "estimated_PhredScoreProfile.rds")
    message("Saved estimated Phred score profile to 'estimated_PhredScoreProfile.rds'")
    
    # 2. Load reference genome sequences
    message("Loading reference genome...")
    reference <- readDNAStringSet(referencePath)
    
    # Select the source sequences (first 3 sequences, or fewer if the reference contains fewer)
    numSeqs <- min(3, length(reference))
    sourceSeq <- reference[1:numSeqs]
    
    # 3. Simulate reads using readSimFFPE
    # Define output file prefix in the current working directory
    outFile1 <- "./sim1"
    
    message("Running genome-wide FFPE read simulation...")
    readSimFFPE(sourceSeq, referencePath, PhredScoreProfile2, outFile1,
                overWrite = TRUE, coverage = 80, readLen = 150,
                enzymeCut = TRUE, threads = 2)
    
    message("Simulation completed successfully. Output files generated with prefix: ", outFile1)

    writeLines(c(
        '"BIOC_SIMFFPE_GENOME_WIDE_SIMULATION":',
        paste0('    SimFFPE: ', as.character(packageVersion('SimFFPE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genome_wide_simulation.csv versions.yml
    """
}

workflow BIOC_SIMFFPE_GENOME_WIDE_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.bam, regionsBam.txt, example.fasta ] ]

    main:
    BIOC_SIMFFPE_GENOME_WIDE_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SIMFFPE_GENOME_WIDE_SIMULATION.out.tables
    plots    = BIOC_SIMFFPE_GENOME_WIDE_SIMULATION.out.plots
    objects  = BIOC_SIMFFPE_GENOME_WIDE_SIMULATION.out.objects
    versions = BIOC_SIMFFPE_GENOME_WIDE_SIMULATION.out.versions
}
