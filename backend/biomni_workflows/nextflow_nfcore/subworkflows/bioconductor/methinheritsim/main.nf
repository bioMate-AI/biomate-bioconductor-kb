#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methInheritSim — multigenerational_methylation_simulation
// Simulate a multigeneration methylation case-control experiment with inheritance using a real control dataset.
// Input: samplesForChrSynthetic
// Container: quay.io/biocontainers/bioconductor-methinheritsim:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, methInheritSim, methylKit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the real control dataset
//  * 2. [Core Analysis] Run the simulation using runSim to generate synthetic chromosomes, control/case datasets, and inheritance patterns
//  * 3. [Visualization & Output] Verify the generated files in the output directory

nextflow.enable.dsl = 2

process BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("methInheritSim", "methylKit", "GenomicRanges")
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
        library(methInheritSim)
        library(methylKit)
        library(GenomicRanges)
        
        # 1. Load the real control dataset from the working directory
        # The user input file "samplesForChrSynthetic" is expected to be saved as an RDS file.
        input_file <- "samplesForChrSynthetic"
        if (!file.exists(input_file)) {
          stop(paste("Required input file missing:", input_file))
        }
        samplesForChrSynthetic <- readRDS(input_file)
        
        # Print the first few rows of the input object to verify
        print("Input dataset loaded successfully. First 3 rows:")
        print(head(samplesForChrSynthetic, n = 3))
        
        # 2. Run the simulation using runSim to generate synthetic chromosomes,
        # control/case datasets, and inheritance patterns.
        temp_dir <- "test_runSim"
        if (!dir.exists(temp_dir)) {
          dir.create(temp_dir, recursive = TRUE)
        }
        
        runSim(methData = samplesForChrSynthetic, # The dataset used to generate the synthetic chr.
               nbSynCHR = 1,                      # The number of synthetic chromosomes
               nbSimulation = 2,                  # The number of simulations for each parameter
               nbBlock = 10, nbCpG = 20,          # The number of sites in the synthetic chr is nbBlock * nbCpG
               nbGeneration = 3,                  # At least 2 generations must be present
               vNbSample = c(3, 6),               # The number of controls (= number of cases) in each simulation
               vpDiff = c(0.9),                   # Mean proportion of samples with differentially methylated values
               vpDiffsd = c(0.1),                 # Standard deviation associated to vpDiff
               vDiff = c(0.8),                    # The shift of the mean of the C/T ratio in the differentially methylated sites
               vInheritance = c(0.5),             # The proportion of cases that inherit differentially methylated sites
               propInherite = 0.3,                # The proportion of differentially methylated regions that are inherited
               rateDiff = 0.3,                    # The mean frequency of the differentially methylated regions
               minRate = 0.2,                     # The minimum rate for differentially methylated sites
               propHetero = 0.5,                  # The reduction of vDiff for the following generations
               keepDiff = FALSE,                  # When FALSE, the differentially methylated sites are the same in all simulations
               outputDir = temp_dir,              # Directory where files are saved
               fileID = "S1",
               runAnalysis = TRUE, 
               nbCores = 1, 
               vSeed = 32)                        # Fix seed for reproducible results
        
        # 3. Verify the generated files in the output directory
        generated_files <- dir(temp_dir)
        print("Simulation completed. Generated files in output directory:")
        print(generated_files)
        
        # 4. Write named output files for the meaningful results
        # We extract the differential methylation statistics for the first simulation (3 samples, Gen 1)
        target_diff_file <- file.path(temp_dir, "methDiff_S1_1_3_0.9_0.8_0.5_1.rds")
        
        if (file.exists(target_diff_file)) {
          methDiff <- readRDS(target_diff_file)
          
          # Convert the first generation's S4 methylDiff object to a standard data frame
          df_gen1 <- getData(methDiff[[1]])
          
          # Save the differential methylation table as a CSV file
          write.csv(df_gen1, "differential_methylation_generation1.csv", row.names = FALSE)
          print("Saved differential methylation results to 'differential_methylation_generation1.csv'")
          
          # Generate and save a diagnostic plot of the p-value distribution
          pdf("pvalue_distribution_generation1.pdf", width = 7, height = 5)
          hist(df_gen1\$pvalue, 
               breaks = 20, 
               col = "skyblue", 
               border = "white",
               main = "P-value Distribution (Generation 1)", 
               xlab = "p-value", 
               ylab = "Frequency")
          dev.off()
          print("Saved p-value distribution plot to 'pvalue_distribution_generation1.pdf'")
        } else {
          warning("Expected output file for analysis was not found. Skipping CSV and PDF generation.")
        }

    writeLines(c(
        '"BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION":',
        paste0('    methInheritSim: ', as.character(packageVersion('methInheritSim')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multigenerational_methylation_simulation.csv versions.yml
    """
}

workflow BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samplesForChrSynthetic ] ]

    main:
    BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION(ch_input)

    emit:
    tables   = BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION.out.tables
    plots    = BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION.out.plots
    objects  = BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION.out.objects
    versions = BIOC_METHINHERITSIM_MULTIGENERATIONAL_METHYLATION_SIMULATION.out.versions
}
