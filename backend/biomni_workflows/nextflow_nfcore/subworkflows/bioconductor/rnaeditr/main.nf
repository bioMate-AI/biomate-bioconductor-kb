#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnaEditr — site_specific_analysis
// Test the association between individual RNA editing sites and a phenotype of interest, followed by gene annotation.
// Input: rnaedit_df, pheno_df
// Container: quay.io/biocontainers/bioconductor-rnaeditr:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rnaEditr
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the RNA editing matrix into an rnaEdit_df class object using CreateEditingTable()
//  * 2. [Core Analysis] Test associations between individual sites and the phenotype using TestAssociations()
//  * 3. [Core Analysis] Annotate the site-specific results with gene symbols using AnnotateResults()

nextflow.enable.dsl = 2

process BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("rnaEditr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(rnaEditr)
    
    # Read input files from the working directory
    if (file.exists("rnaedit_df.rds")) {
      rnaedit_df <- readRDS("rnaedit_df.rds")
    } else if (file.exists("rnaedit_df.csv")) {
      rnaedit_df <- as.matrix(read.csv("rnaedit_df.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("rnaedit_df.tsv")) {
      rnaedit_df <- as.matrix(read.delim("rnaedit_df.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: rnaedit_df (RDS, CSV, or TSV) not found in the working directory.")
    }
    
    if (file.exists("pheno_df.rds")) {
      pheno_df <- readRDS("pheno_df.rds")
    } else if (file.exists("pheno_df.csv")) {
      pheno_df <- read.csv("pheno_df.csv", check.names = FALSE)
    } else if (file.exists("pheno_df.tsv")) {
      pheno_df <- read.delim("pheno_df.tsv", check.names = FALSE)
    } else {
      stop("Error: pheno_df (RDS, CSV, or TSV) not found in the working directory.")
    }
    
    # Ensure rnaedit_df is a matrix as required by CreateEditingTable
    if (!is.matrix(rnaedit_df)) {
      rnaedit_df <- as.matrix(rnaedit_df)
    }
    
    # Step 1: Convert the RNA editing matrix into an rnaEdit_df class object
    rnaedit2_df <- CreateEditingTable(
      rnaEditMatrix = rnaedit_df
    )
    
    # Determine response variable and type dynamically
    potential_responses <- setdiff(colnames(pheno_df), "sample")
    
    if (length(potential_responses) == 0) {
      stop("Error: No response variable found in pheno_df.")
    }
    
    if (length(potential_responses) == 2 && is.numeric(pheno_df[[potential_responses[1]]]) && is.numeric(pheno_df[[potential_responses[2]]])) {
      responses_char <- potential_responses
      respType <- "survival"
    } else {
      responses_char <- potential_responses[1]
      if (length(unique(na.omit(pheno_df[[responses_char]]))) == 2) {
        respType <- "binary"
      } else {
        respType <- "continuous"
      }
    }
    
    # Step 2: Test associations between individual sites and the phenotype
    tumor_single_df <- TestAssociations(
      # an RNA editing dataframe with special class "rnaEdit_df" from function
      #   CreateEditingTable() if site-specific analysis, from function 
      #   SummarizeAllRegions() if region-based analysis.
      rnaEdit_df = rnaedit2_df,
      # a phenotype dataset that must have variable "sample" whose values are a 
      #   exact match to the colnames of "rnaEdit_df".
      pheno_df = pheno_df,
      # name of outcome variable in phenotype dataset "pheno_df" that you want to 
      #   test.
      responses_char = responses_char,
      # names of covariate variables in phenotype dataset "pheno_df" that you want
      #   to add into the model.
      covariates_char = NULL,
      # type of outcome variable that you input in argument "responses_char".
      respType = respType,
      # order the final results by p-values or not.
      orderByPval = TRUE
    )
    
    # Step 3: Annotate the site-specific results with gene symbols
    tumor_annot_df <- AnnotateResults(
      # the output dataset from function TestAssociations().
      results_df = tumor_single_df,
      # close-by regions, since this is site-specific analysis, set to NULL.
      closeByRegions_gr = NULL,
      # input regions, since this is site-specific analysis, set to NULL.
      inputRegions_gr = NULL,
      genome = "hg19",
      # the type of analysis result from function TestAssociations(), since we are 
      #   running site-specific analysis, set to "site-specific".
      analysis = "site-specific"
    )
    
    # Write outputs to the working directory
    write.csv(tumor_single_df, file = "tumor_single_df.csv", row.names = TRUE)
    write.csv(tumor_annot_df, file = "tumor_annot_df.csv", row.names = TRUE)
    saveRDS(tumor_annot_df, file = "tumor_annot_df.rds")

    writeLines(c(
        '"BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS":',
        paste0('    rnaEditr: ', as.character(packageVersion('rnaEditr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_site_specific_analysis.csv versions.yml
    """
}

workflow BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rnaedit_df, pheno_df ] ]

    main:
    BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS.out.tables
    plots    = BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS.out.plots
    objects  = BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS.out.objects
    versions = BIOC_RNAEDITR_SITE_SPECIFIC_ANALYSIS.out.versions
}
