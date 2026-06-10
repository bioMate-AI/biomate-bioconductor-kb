#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FRGEpistasis — functional_regression_epistasis
// Detect epistasis between genomic regions using the Functional Regression Model (FRG).
// Input: list_geno.txt, list_map.txt, phenotype.csv, gene.list.csv, simGeno-chr*.raw, chr*.map
// Container: quay.io/biocontainers/bioconductor-frgepistasis:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FRGEpistasis
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the FRGEpistasis library and set the working directory
//  * 2. [Input & Preparation] Read the genotype and map file index lists
//  * 3. [Input & Preparation] Read the phenotype and gene annotation files
//  * 4. [Core Analysis] Transform the phenotype data (e.g., log transformation or rank transformation using rankTransPheno)
//  * 5. [Core Analysis] Run the functional regression epistasis test using fRGEpistasis
//  * 6. [Visualization & Output] Save the output p-values to a CSV file

nextflow.enable.dsl = 2

process BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library("FRGEpistasis")
    
    # Set the working directory path (using current working directory)
    work_dir <- paste0(getwd(), "/")
    
    # Read the list of genotype files
    geno_files <- read.table("list_geno.txt")
    
    # Read the list of map files
    mapFiles <- read.table("list_map.txt")
    
    # Read the phenotype file
    phenoInfo <- read.csv("phenotype.csv", header=TRUE)
    
    # Read the gene annotation file
    gLst <- read.csv("gene.list.csv")
    
    # Define the extension scope of gene region and FDR threshold
    rng <- 0
    fdr <- 0.05
    
    # Output data structure
    out_epi <- data.frame()
    
    # Log transformation of the phenotype
    phenoInfo[, 2] <- log(phenoInfo[, 2])
    
    # Test epistasis with Functional Regression Model
    out_epi <- fRGEpistasis(work_dir, phenoInfo, geno_files, mapFiles, gLst, fdr, rng)
    
    # Output the result to physical file
    write.csv(out_epi, "Output_Pvalues_Epistasis_Test.csv")

    writeLines(c(
        '"BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS":',
        paste0('    FRGEpistasis: ', as.character(packageVersion('FRGEpistasis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_functional_regression_epistasis.csv versions.yml
    """
}

workflow BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_geno.txt, list_map.txt, phenotype.csv, gene.list.csv, simGeno-chr*.raw, chr*.map ] ]

    main:
    BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS(ch_input)

    emit:
    tables   = BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS.out.tables
    plots    = BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS.out.plots
    objects  = BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS.out.objects
    versions = BIOC_FRGEPISTASIS_FUNCTIONAL_REGRESSION_EPISTASIS.out.versions
}
