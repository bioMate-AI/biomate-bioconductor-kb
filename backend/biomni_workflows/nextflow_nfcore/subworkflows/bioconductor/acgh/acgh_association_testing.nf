#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aCGH — acgh_association_testing
// Test association of clones with categorical, censored, or continuous outcomes and plot frequency statistics.
// Input: colorectal
// Container: quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0
// R packages: aCGH, multtest, survival
// Bioconductor: 3.20 | R: 4.4
// Requires: aCGH, multtest, survival
// Visualizations: survival plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset clones and samples
//  * 2. [Core Analysis] Run association test (mt.maxT for categorical, aCGH.test for censored/continuous)
//  * 3. [Visualization & Output] Plot frequency statistics using plotFreqStat
//  * 4. [Visualization & Output] Summarize clones using summarize.clones

nextflow.enable.dsl = 2

process BIOC_ACGH_ACGH_ASSOCIATION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("aCGH", "multtest", "survival")
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
    library(aCGH)
    library(multtest)
    library(survival)
    
    # 1. Read the pre-existing aCGH object from the working directory
    if (file.exists("colorectal")) {
      colorectal <- readRDS("colorectal")
    } else if (file.exists("colorectal.rds")) {
      colorectal <- readRDS("colorectal.rds")
    } else {
      stop("Error: Input file 'colorectal' or 'colorectal.rds' not found in the working directory.")
    }
    
    # --- Stage 1: Subset clones and samples ---
    sex <- phenotype(colorectal)\$sex
    sex.na <- !is.na(sex)
    index.clones.use <- which(clones.info(colorectal)\$Chrom < 23)
    colorectal.na <- colorectal[ index.clones.use,sex.na , keep=TRUE]
    
    # --- Stage 2: Run association test (mt.maxT for categorical) ---
    dat <- log2.ratios.imputed(colorectal.na)
    resT.sex <- mt.maxT(dat, sex[sex.na], test = "t.equalvar", B = 1000)
    
    # Save categorical test results
    write.csv(resT.sex, file = "resT_sex.csv", row.names = FALSE)
    saveRDS(resT.sex, file = "resT_sex.rds")
    
    # --- Stage 3: Plot frequency statistics using plotFreqStat (Categorical) ---
    pdf("plot_freq_stat_sex.pdf", width = 10, height = 8)
    plotFreqStat(colorectal.na, resT.sex, sex[sex.na], factor=3, titles =
                 c("Female", "Male"), X = FALSE, Y = FALSE)
    dev.off()
    
    # --- Stage 4: Summarize clones using summarize.clones ---
    sex.tbl <- summarize.clones(colorectal.na, resT.sex, sex[sex.na], titles = c("Male", "Female"))
    write.csv(sex.tbl, file = "sex_tbl.csv", row.names = FALSE)
    saveRDS(sex.tbl, file = "sex_tbl.rds")
    
    
    # --- Censored Outcome Association Testing ---
    # Simulate survival data as in the documented code
    set.seed(123)
    time <- rexp(ncol(colorectal), rate = 1 / 12)
    events <- rbinom(ncol(colorectal), size = 1, prob = .5)
    surv.obj <- Surv(time, 	events)
    
    stat.coxph <-
      aCGH.test(colorectal, surv.obj, test = "coxph",
    	p.adjust.method = "fdr")
    
    # Save censored test results
    write.csv(stat.coxph, file = "stat_coxph.csv", row.names = TRUE)
    saveRDS(stat.coxph, file = "stat_coxph.rds")
    
    # Plot censored frequency statistics
    pdf("plot_freq_stat_survival.pdf", width = 10, height = 8)
    plotFreqStat(colorectal, stat.coxph, events, titles =
                 c("Survived/Censored", "Dead"), X = FALSE, Y = FALSE)
    dev.off()
    
    
    # --- Continuous Outcome Association Testing (Age) ---
    age <- phenotype(colorectal)\$age
    age.na <- which(!is.na(age))
    age <- age[age.na]
    colorectal.na <- colorectal[, age.na]
    
    stat.age <-
      aCGH.test(colorectal.na, age, test = "linear.regression",
                p.adjust.method = "fdr")
    
    # Save continuous test results
    write.csv(stat.age, file = "stat_age.csv", row.names = TRUE)
    saveRDS(stat.age, file = "stat_age.rds")
    
    # Plot continuous frequency statistics
    pdf("plot_freq_stat_age.pdf", width = 10, height = 8)
    plotFreqStat(colorectal.na, stat.age, ifelse(age < 70, 0, 1), titles =
                 c("Young", "Old"), X = FALSE, Y = FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_ACGH_ACGH_ASSOCIATION_TESTING":',
        paste0('    aCGH: ', as.character(packageVersion('aCGH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_association_testing.csv versions.yml
    """
}

workflow BIOC_ACGH_ACGH_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ colorectal ] ]

    main:
    BIOC_ACGH_ACGH_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_ACGH_ACGH_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_ACGH_ACGH_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_ACGH_ACGH_ASSOCIATION_TESTING.out.objects
    versions = BIOC_ACGH_ACGH_ASSOCIATION_TESTING.out.versions
}
