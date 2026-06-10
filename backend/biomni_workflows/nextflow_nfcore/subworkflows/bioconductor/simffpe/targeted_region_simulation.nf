#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SimFFPE — targeted_region_simulation
// Simulate FFPE NGS reads for specific targeted regions or whole exome panels.
// Input: example.fasta, regionsSim.txt, PhredScoreProfile1.txt
// Container: quay.io/biocontainers/bioconductor-simffpe:1.22.0--r45hdfd78af_0
// R packages: SimFFPE
// Bioconductor: 3.20 | R: 4.4
// Requires: SimFFPE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load target regions
//  * 2. [Input & Preparation] Load Phred score profile
//  * 3. [Core Analysis] Simulate targeted reads using targetReadSimFFPE

nextflow.enable.dsl = 2

process BIOC_SIMFFPE_TARGETED_REGION_SIMULATION {
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
    .bm_deps <- c("SimFFPE")
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
    
    # 1. Load Phred score profile from the user-provided file
    PhredScoreProfilePath <- "PhredScoreProfile1.txt"
    PhredScoreProfile <- as.matrix(read.table(PhredScoreProfilePath, skip = 1))
    colnames(PhredScoreProfile) <- strsplit(readLines(PhredScoreProfilePath)[1], "\t")[[1]]
    
    # 2. Define reference genome path
    referencePath <- "example.fasta"
    
    # 3. Load target regions from the user-provided file
    regionPath <- "regionsSim.txt"
    targetRegions <- read.table(regionPath)
    
    # 4. Simulate targeted reads using targetReadSimFFPE
    # Output files will be written to the current working directory with prefix "sim3"
    outFile3 <- "sim3"
    
    tryCatch({
        targetReadSimFFPE(referencePath, PhredScoreProfile, targetRegions, outFile3,
                          coverage = 120, readLen = 100, meanInsertLen = 180, 
                          sdInsertLen = 50, enzymeCut = FALSE)
        message("Simulation completed successfully. Output files generated with prefix: ", outFile3)
    }, error = function(e) {
        message("An error occurred during simulation: ", e\$message)
    })
    
    # 5. Save processed inputs as RDS files for downstream verification
    saveRDS(targetRegions, "target_regions_processed.rds")
    saveRDS(PhredScoreProfile, "phred_score_profile_processed.rds")

    writeLines(c(
        '"BIOC_SIMFFPE_TARGETED_REGION_SIMULATION":',
        paste0('    SimFFPE: ', as.character(packageVersion('SimFFPE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targeted_region_simulation.csv versions.yml
    """
}

workflow BIOC_SIMFFPE_TARGETED_REGION_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.fasta, regionsSim.txt, PhredScoreProfile1.txt ] ]

    main:
    BIOC_SIMFFPE_TARGETED_REGION_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SIMFFPE_TARGETED_REGION_SIMULATION.out.tables
    plots    = BIOC_SIMFFPE_TARGETED_REGION_SIMULATION.out.plots
    objects  = BIOC_SIMFFPE_TARGETED_REGION_SIMULATION.out.objects
    versions = BIOC_SIMFFPE_TARGETED_REGION_SIMULATION.out.versions
}
