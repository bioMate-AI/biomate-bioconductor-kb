#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylclock — chronological_and_biological_age_estimation
// Estimate chronological and biological DNAm age and age acceleration from methylation data.
// Input: MethylationData, covariates
// Container: quay.io/biocontainers/bioconductor-methylclock:1.16.0--r45ha27e39d_0
// R packages: Biobase, ggplot2, ggpmisc, impute, methylclock, methylclockData, readr, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, ggplot2, ggpmisc, impute, methylclock, methylclockData, readr, tibble
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Check missing CpGs for chronological clocks using
//  * 2. [Visualization & Output] Identify specific missing CpGs using commonClockCpgs
//  * 3. [Visualization & Output] Estimate DNAm age using DNAmAge
//  * 4. [Visualization & Output] Estimate DNAm age and age acceleration adjusted for cell
//  * 5. [Visualization & Output] Plot correlation between estimated DNAm age and
//  * 6. [Visualization & Output] Plot correlation among different clocks using

nextflow.enable.dsl = 2

process BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION {
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
    .bm_deps <- c("Biobase", "ggplot2", "ggpmisc", "impute", "methylclock", "methylclockData", "readr", "tibble")
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
    
    # Load required libraries
    library(methylclockData)
    library(methylclock)
    library(Biobase)
    library(tibble)
    library(impute)
    library(ggplot2)
    library(ggpmisc)
    library(readr)
    
    # Helper function to find files in the working directory
    find_file <- function(base_name) {
      files <- list.files(pattern = paste0("^", base_name, "(\\\\..+)?\$"), ignore.case = TRUE)
      if (length(files) == 0) {
        stop(paste("Required file not found:", base_name))
      }
      return(files[1])
    }
    
    # Read user input files
    meth_file <- find_file("MethylationData")
    cov_file <- find_file("covariates")
    
    # Load MethylationData
    ext <- tolower(tools::file_ext(meth_file))
    if (ext == "rds") {
      MethylationData <- readRDS(meth_file)
    } else if (ext == "csv") {
      MethylationData <- readr::read_csv(meth_file)
    } else if (ext %in% c("tsv", "txt")) {
      MethylationData <- readr::read_tsv(meth_file)
    } else {
      MethylationData <- tryCatch(readRDS(meth_file), error = function(e) readr::read_csv(meth_file))
    }
    
    # Ensure first column contains CpG names if it's a data frame/tibble
    if (is.data.frame(MethylationData) || tibble::is_tibble(MethylationData)) {
      MethylationData[[1]] <- as.character(MethylationData[[1]])
    }
    
    # Load covariates
    covariates <- readr::read_csv(cov_file)
    
    # Extract chronological age
    age_col <- grep("^age\$", colnames(covariates), ignore.case = TRUE, value = TRUE)
    if (length(age_col) == 0) {
      age_col <- grep("age", colnames(covariates), ignore.case = TRUE, value = TRUE)[1]
    }
    if (is.na(age_col) || length(age_col) == 0) {
      stop("Could not find an 'age' column in covariates.")
    }
    age <- as.numeric(covariates[[age_col]])
    
    # Map variables for exact documented code execution
    TestDataset <- MethylationData
    
    # --- Check missing CpGs for chronological clocks using ---
    cpgs.missing <- checkClocks(TestDataset)
    saveRDS(cpgs.missing, "cpgs_missing.rds")
    
    # --- Identify specific missing CpGs using commonClockCpgs ---
    hannum_missing <- commonClockCpgs(cpgs.missing, "Hannum" )
    writeLines(hannum_missing, "hannum_missing_cpgs.txt")
    
    # --- Estimate DNAm age using DNAmAge ---
    age.example55 <- DNAmAge(MethylationData)
    readr::write_csv(age.example55, "age_example55_basic.csv")
    
    age.example55.2 <- DNAmAge(MethylationData, min.perc = 0.25)
    readr::write_csv(age.example55.2, "age_example55_min_perc_0.25.csv")
    
    age.example55.sel <- DNAmAge(MethylationData, clocks=c("Horvath", "BNN"))
    readr::write_csv(age.example55.sel, "age_example55_selected_clocks.csv")
    
    # --- Estimate DNAm age and age acceleration adjusted for cell ---
    age.example55 <- DNAmAge(MethylationData, age=age, cell.count=TRUE)
    readr::write_csv(age.example55, "age_example55_with_age_and_cell_counts.csv")
    
    # Map variables for plotting
    age.gse58045 <- age.example55
    age.gse <- age.example55
    
    # --- Plot correlation between estimated DNAm age and ---
    # --- Plot correlation among different clocks using ---
    pdf("plots_combined.pdf")
    print(plotDNAmAge(age.gse58045\$Horvath, age))
    print(plotDNAmAge(age.gse58045\$BNN, age, tit="Bayesian Neural Network"))
    print(plotCorClocks(age.gse))
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION":',
        paste0('    methylclock: ', as.character(packageVersion('methylclock')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chronological_and_biological_age_estimation.csv versions.yml
    """
}

workflow BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MethylationData, covariates ] ]

    main:
    BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION.out.tables
    plots    = BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION.out.plots
    objects  = BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION.out.objects
    versions = BIOC_METHYLCLOCK_CHRONOLOGICAL_AND_BIOLOGICAL_AGE_ESTIMATION.out.versions
}
