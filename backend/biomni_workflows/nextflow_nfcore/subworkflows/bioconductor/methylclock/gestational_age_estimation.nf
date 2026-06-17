#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylclock — gestational_age_estimation
// Estimate gestational DNAm age and gestational age acceleration from cord blood or placenta methylation data.
// Input: TestDataset, progress_vars
// Container: quay.io/biocontainers/bioconductor-methylclock:1.16.0--r45ha27e39d_0
// R packages: ggplot2, methylclock, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, methylclock, tibble
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Check missing CpGs for gestational age clocks using
//  * 2. [Visualization & Output] Identify specific missing CpGs using commonClockCpgs
//  * 3. [Visualization & Output] Estimate gestational DNAm age using DNAmGA
//  * 4. [Visualization & Output] Estimate gestational DNAm age for progress data
//  * 5. [Visualization & Output] Plot correlation between estimated gestational age and
//  * 6. [Visualization & Output] Estimate gestational DNAm age and gestational age
//  * 7. [Visualization & Output] Check clocks for progress data

nextflow.enable.dsl = 2

process BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION {
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
    .bm_deps <- c("ggplot2", "methylclock", "tibble")
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
    library(methylclock)
    library(tibble)
    library(ggplot2)
    
    # ----------------------------------------------------------------------
    # 1. Read User Inputs
    # ----------------------------------------------------------------------
    
    # Read TestDataset (methylation data)
    if (file.exists("TestDataset.rds")) {
      TestDataset <- readRDS("TestDataset.rds")
    } else if (file.exists("TestDataset.csv")) {
      TestDataset <- read.csv("TestDataset.csv", check.names = FALSE)
      TestDataset <- as_tibble(TestDataset)
    } else {
      stop("Error: TestDataset file (TestDataset.rds or TestDataset.csv) not found in the working directory.")
    }
    
    # Read progress_vars (clinical variables containing clinical gestational age 'EGA')
    if (file.exists("progress_vars.rds")) {
      progress_vars <- readRDS("progress_vars.rds")
    } else if (file.exists("progress_vars.csv")) {
      progress_vars <- read.csv("progress_vars.csv", check.names = FALSE)
      progress_vars <- as_tibble(progress_vars)
    } else {
      stop("Error: progress_vars file (progress_vars.rds or progress_vars.csv) not found in the working directory.")
    }
    
    # Read progress_data (methylation data for the PROGRESS cohort)
    # If not explicitly provided as a separate file, we fallback to TestDataset
    if (file.exists("progress_data.rds")) {
      progress_data <- readRDS("progress_data.rds")
    } else if (file.exists("progress_data.csv")) {
      progress_data <- read.csv("progress_data.csv", check.names = FALSE)
      progress_data <- as_tibble(progress_data)
    } else {
      progress_data <- TestDataset
    }
    
    # ----------------------------------------------------------------------
    # 2. Execute Workflow Stages
    # ----------------------------------------------------------------------
    
    # --- Check missing CpGs for gestational age clocks using ---
    cpgs.missing.GA <- checkClocksGA(TestDataset)
    saveRDS(cpgs.missing.GA, "cpgs_missing_GA.rds")
    
    # --- Identify specific missing CpGs using commonClockCpgs ---
    missing_bohlin <- commonClockCpgs(cpgs.missing.GA, "Bohlin")
    writeLines(as.character(missing_bohlin), "missing_Bohlin_cpgs.txt")
    
    # --- Estimate gestational DNAm age using DNAmGA ---
    ga.test <- DNAmGA(TestDataset)
    write.csv(ga.test, "ga_test_estimates.csv", row.names = FALSE)
    
    # --- Estimate gestational DNAm age for progress data ---
    ga.progress <- DNAmGA(progress_data)
    write.csv(ga.progress, "ga_progress_estimates.csv", row.names = FALSE)
    
    # --- Plot correlation between estimated gestational age and ---
    pdf("plot_GA_Knight_method.pdf")
    p <- plotDNAmAge(ga.progress\$Knight, progress_vars\$EGA, tit="GA Knight's method", clock="GA")
    if (inherits(p, "ggplot") || inherits(p, "gg")) {
      print(p)
    }
    dev.off()
    
    # --- Estimate gestational DNAm age and gestational age ---
    accga.progress <- DNAmGA(progress_data, age = progress_vars\$EGA, cell.count=FALSE)
    write.csv(accga.progress, "accga_progress_estimates.csv", row.names = FALSE)
    
    # --- Check clocks for progress data ---
    progress_clocks_check <- checkClocksGA(progress_data)
    saveRDS(progress_clocks_check, "progress_clocks_check.rds")

    writeLines(c(
        '"BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION":',
        paste0('    methylclock: ', as.character(packageVersion('methylclock')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gestational_age_estimation.csv versions.yml
    """
}

workflow BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TestDataset, progress_vars ] ]

    main:
    BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION.out.tables
    plots    = BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION.out.plots
    objects  = BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION.out.objects
    versions = BIOC_METHYLCLOCK_GESTATIONAL_AGE_ESTIMATION.out.versions
}
