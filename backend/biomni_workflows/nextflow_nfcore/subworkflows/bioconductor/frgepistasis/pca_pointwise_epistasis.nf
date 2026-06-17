#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FRGEpistasis — pca_pointwise_epistasis
// Perform epistasis testing using PCA and pointwise methods, utilizing the output of the Functional Regression Model.
// Input: list_geno.txt, list_map.txt, phenotype.csv, gene.list.csv, simGeno-chr*.raw, chr*.map
// Container: quay.io/biocontainers/bioconductor-frgepistasis:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FRGEpistasis
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the FRGEpistasis library and set the working directory
//  * 2. [Input & Preparation] Read the genotype, map, phenotype, and gene annotation files
//  * 3. [Core Analysis] Run the Functional Regression Model to obtain the initial epistasis results (out_epi)
//  * 4. [Core Analysis] Run the PCA and pointwise epistasis test using pCAPiontwiseEpistasis

nextflow.enable.dsl = 2

process BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("FRGEpistasis")
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
    
    # Load the FRGEpistasis library
    library("FRGEpistasis")
    
    # Set the working directory to the current directory
    work_dir <- paste0(getwd(), "/")
    wDir <- work_dir
    
    # Read the list of genotype files
    geno_files <- read.table("list_geno.txt", header = FALSE, stringsAsFactors = FALSE)
    gnoFiles <- geno_files
    
    # Read the list of map files
    mapFiles <- read.table("list_map.txt", header = FALSE, stringsAsFactors = FALSE)
    
    # Read the phenotype file
    phenoInfo <- read.csv("phenotype.csv", header = TRUE)
    
    # Read the gene annotation file
    gLst <- read.csv("gene.list.csv", header = TRUE)
    
    # Define the extension scope of gene region and FDR
    rng <- 0
    fdr <- 0.05
    
    # Output data structure
    out_epi <- data.frame()
    
    # Log transformation of phenotype
    phenoInfo[, 2] <- log(phenoInfo[, 2])
    
    # Test epistasis with Functional Regression Model
    message("Running Functional Regression Model...")
    out_epi <- fRGEpistasis(work_dir, phenoInfo, geno_files, mapFiles, gLst, fdr, rng)
    
    # Output the result of FRGEpistasis to physical file
    write.csv(out_epi, "Output_Pvalues_Epistasis_Test.csv", row.names = FALSE)
    
    # Test epistasis with PCA and pointwise method
    message("Running PCA and Pointwise Epistasis...")
    out_pp <- data.frame()
    out_pp <- pCAPiontwiseEpistasis(wDir, out_epi, phenoInfo, gnoFiles, mapFiles, gLst, rng)
    
    # Output the result of PCA and pointwise epistasis to physical file
    write.csv(out_pp, "Output_PCA_Pointwise_Epistasis.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS":',
        paste0('    FRGEpistasis: ', as.character(packageVersion('FRGEpistasis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_pointwise_epistasis.csv versions.yml
    """
}

workflow BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_geno.txt, list_map.txt, phenotype.csv, gene.list.csv, simGeno-chr*.raw, chr*.map ] ]

    main:
    BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS(ch_input)

    emit:
    tables   = BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS.out.tables
    plots    = BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS.out.plots
    objects  = BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS.out.objects
    versions = BIOC_FRGEPISTASIS_PCA_POINTWISE_EPISTASIS.out.versions
}
