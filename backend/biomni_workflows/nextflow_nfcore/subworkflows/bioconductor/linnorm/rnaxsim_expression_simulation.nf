#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — rnaxsim_expression_simulation
// Simulate RNA-seq expression data with known differentially expressed genes for method evaluation.
// Input: SEQC
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: Linnorm
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RnaXSim with default Negative Binomial distribution parameters
//  * 2. [Core Analysis] Run RnaXSim with advanced parameters (e.g., Gamma distribution, custom replicates, and feature counts)
//  * 3. [Core Analysis] Extract simulated expression matrices and true DE gene indices

nextflow.enable.dsl = 2

process BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION {
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
    .bm_deps <- c("Linnorm")
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
    
    # Load required library
    library(Linnorm)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input: SEQC (reference expression matrix)
    # ----------------------------------------------------------------------
    if (file.exists("SEQC")) {
      SampleA <- as.matrix(read.table("SEQC", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    } else if (file.exists("SEQC.csv")) {
      SampleA <- as.matrix(read.csv("SEQC.csv", header=TRUE, row.names=1, check.names=FALSE))
    } else if (file.exists("SEQC.tsv")) {
      SampleA <- as.matrix(read.table("SEQC.tsv", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    } else if (file.exists("SEQC.txt")) {
      SampleA <- as.matrix(read.table("SEQC.txt", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    } else if (file.exists("SEQC.rds")) {
      SampleA <- readRDS("SEQC.rds")
      if (!is.matrix(SampleA)) {
        SampleA <- as.matrix(SampleA)
      }
    } else {
      stop("Error: SEQC reference expression matrix file not found in the working directory.")
    }
    
    # ----------------------------------------------------------------------
    # 2. Run RnaXSim with default Negative Binomial distribution parameters
    # ----------------------------------------------------------------------
    # This will generate two sets of RNA-seq data with 5 replicates each. 
    # It will have 20000 genes totally with 2000 genes being differentially 
    # expressed. It has the Negative Binomial distribution.
    SimulatedData <- RnaXSim(SampleA)
    
    # Index of differentially expressed genes.
    DE_Index <- SimulatedData[[2]]
    
    # Expression Matrix
    ExpMatrix <- SimulatedData[[1]]
    
    # Sample Set 1
    Sample1 <- ExpMatrix[,1:3]
    
    # Sample Set 2
    Sample2 <- ExpMatrix[,4:6]
    
    # Save Stage 1 Outputs
    write.csv(ExpMatrix, "Simulated_ExpMatrix_NB.csv", row.names=TRUE)
    write.table(DE_Index, "Simulated_DE_Index_NB.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
    write.csv(Sample1, "Simulated_Sample1_NB.csv", row.names=TRUE)
    write.csv(Sample2, "Simulated_Sample2_NB.csv", row.names=TRUE)
    
    # Generate diagnostic plot for NB simulation
    pdf("Simulation_NB_Density.pdf")
    plot(density(log1p(ExpMatrix)), main="NB Simulated Expression Density", xlab="log1p(Counts)", col="blue", lwd=2)
    dev.off()
    
    # ----------------------------------------------------------------------
    # 3. Run RnaXSim with advanced parameters (Gamma distribution)
    # ----------------------------------------------------------------------
    SimulatedData <- RnaXSim(SampleA,
    distribution="Gamma", # Distribution in the simulated dataset.
    # Put "NB" for Negative Binomial, "Gamma" for Gamma,
    # "Poisson" for Poisson and "LogNorm" for Log Normal distribution.
    NumRep=5, # Number of replicates in each sample set. 
    # 5 will generate 10 samples in total.
    NumDiff = 1000, # Number of differentially expressed genes.
    NumFea = 5000 # Total number of genes in the dataset
    )
    
    # Index of differentially expressed genes.
    DE_Index <- SimulatedData[[2]]
    
    # Expression Matrix
    ExpMatrix <- SimulatedData[[1]]
    
    # Simulated Sample Set 1
    Sample1 <- ExpMatrix[,1:3]
    
    # Simulated Sample Set 2
    Sample2 <- ExpMatrix[,4:6]
    
    # Save Stage 2 Outputs
    write.csv(ExpMatrix, "Simulated_ExpMatrix_Gamma.csv", row.names=TRUE)
    write.table(DE_Index, "Simulated_DE_Index_Gamma.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
    write.csv(Sample1, "Simulated_Sample1_Gamma.csv", row.names=TRUE)
    write.csv(Sample2, "Simulated_Sample2_Gamma.csv", row.names=TRUE)
    
    # Generate diagnostic plot for Gamma simulation
    pdf("Simulation_Gamma_Density.pdf")
    plot(density(log1p(ExpMatrix)), main="Gamma Simulated Expression Density", xlab="log1p(Counts)", col="red", lwd=2)
    dev.off()

    writeLines(c(
        '"BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaxsim_expression_simulation.csv versions.yml
    """
}

workflow BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SEQC ] ]

    main:
    BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION(ch_input)

    emit:
    tables   = BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION.out.tables
    plots    = BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION.out.plots
    objects  = BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION.out.objects
    versions = BIOC_LINNORM_RNAXSIM_EXPRESSION_SIMULATION.out.versions
}
