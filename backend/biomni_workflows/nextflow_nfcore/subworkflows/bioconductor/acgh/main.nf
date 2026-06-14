#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: acgh — standard_acgh_pipeline
// Import generic log2 ratio, clone mapping, and phenotype text files, process and filter clones, impute missing values, fit HMM states, identify genomic events, a
// Input: clones.info.ex.txt, log2.ratios.ex.txt, pheno.type.ex.txt
// Container: quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0
// R packages: aCGH, multtest, survival
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_ACGH_STANDARD_ACGH_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0"

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
    
    library(aCGH)
    library(multtest)
    library(survival)
    
    # --- Import data and create aCGH object ---
    clones.info <- read.table(file = "clones.info.ex.txt",
                              header = TRUE, sep = "\t", quote = "", comment.char = "")
    log2.ratios <- read.table(file = "log2.ratios.ex.txt",
                              header = TRUE, sep = "\t", quote = "", comment.char = "")
    pheno.type <- read.table(file = "pheno.type.ex.txt",
                             header = TRUE, sep = "\t", quote = "", comment.char = "")
    ex.acgh <- create.aCGH(log2.ratios, clones.info, pheno.type)
    
    # --- Filter and process clones ---
    ex.acgh <- aCGH.process(ex.acgh, chrom.remove.threshold = 23, prop.missing = .25, 
                            sample.quality.threshold = .4, unmapScreen = TRUE, dupRemove = FALSE)
    
    # --- Impute missing values ---
    log2.ratios.imputed(ex.acgh) <- impute.lowess(ex.acgh, maxChrom = 24)
    
    # --- Fit HMM states ---
    hmm(ex.acgh) <- find.hmm.states(ex.acgh)
    
    # --- Merge HMM states ---
    hmm.merged(ex.acgh) <- mergeHmmStates(ex.acgh, model.use = 1, minDiff = .25)
    
    # --- Compute sample standard deviations ---
    sd.samples(ex.acgh) <- computeSD.Samples(ex.acgh)
    
    # --- Identify genomic events ---
    genomic.events(ex.acgh) <- find.genomic.events(ex.acgh)
    
    # Open PDF device for all visualizations
    pdf("acgh_pipeline_plots.pdf", width = 10, height = 8)
    
    # --- Visualize profiles and HMM states ---
    plot(ex.acgh)
    
    plotGenome(ex.acgh, samples = 2, Y = FALSE)
    
    plotHmmStates(ex.acgh, sample.ind = 1, chr = 1)
    
    plotFreqStat(ex.acgh, all = TRUE)
    
    # Save clone summary table
    clones_summary <- summarize.clones(ex.acgh)
    write.csv(clones_summary, "summarized_clones.csv", row.names = FALSE)
    
    # Thresholding and saving threshold matrix
    factor <- 3
    tbl <- threshold.func(log2.ratios(ex.acgh),
                          posThres = factor * (sd.samples(ex.acgh)\$madGenome))
    rownames(tbl) <- clone.names(ex.acgh)
    colnames(tbl) <- sample.names(ex.acgh)
    write.csv(tbl, "threshold_matrix.csv")
    
    # Fraction of genome altered (FGA)
    col.fga <- fga.func(ex.acgh, factor = 3, chrominfo = human.chrom.info.Jul03)
    write.csv(as.data.frame(col.fga), "fga_results.csv")
    
    # --- Perform association testing ---
    # Categorical outcome (Sex)
    sex <- phenotype(ex.acgh)\$sex
    sex.na <- !is.na(sex)
    index.clones.use <- which(clones.info(ex.acgh)\$Chrom < 23)
    ex.acgh.na <- ex.acgh[index.clones.use, sex.na, keep = TRUE]
    dat <- log2.ratios.imputed(ex.acgh.na)
    resT.sex <- mt.maxT(dat, sex[sex.na], test = "t.equalvar", B = 1000)
    write.csv(resT.sex, "sex_association_t_test.csv", row.names = FALSE)
    
    plotFreqStat(ex.acgh.na, resT.sex, sex[sex.na], factor = 3, titles =
                   c("Female", "Male"), X = FALSE, Y = FALSE)
    
    plotSummaryProfile(ex.acgh, response = sex,
                       titles = c("Female", "Male"),
                       X = FALSE, Y = FALSE, maxChrom = 22)
    
    # Censored outcome (Survival)
    time <- rexp(ncol(ex.acgh), rate = 1 / 12)
    events <- rbinom(ncol(ex.acgh), size = 1, prob = .5)
    surv.obj <- Surv(time, events)
    stat.coxph <- aCGH.test(ex.acgh, surv.obj, test = "coxph", p.adjust.method = "fdr")
    write.csv(stat.coxph, "survival_association_coxph.csv")
    
    # Continuous outcome (Age)
    age <- phenotype(ex.acgh)\$age
    age.na <- which(!is.na(age))
    age <- age[age.na]
    ex.acgh.na2 <- ex.acgh[, age.na]
    stat.age <- aCGH.test(ex.acgh.na2, age, test = "linear.regression", p.adjust.method = "fdr")
    write.csv(stat.age, "age_association_linear.csv")
    
    # --- Cluster samples ---
    par(mfrow = c(2, 1))
    clusterGenome(ex.acgh.na, response = sex[sex.na],
                  titles = c("Female", "Male"),
                  byclass = FALSE, showaber = TRUE, vecchrom = c(4, 8, 9),
                  dendPlot = FALSE, imp = FALSE)
    
    dev.off()
    
    # Save the final processed S4 object
    saveRDS(ex.acgh, "processed_ex_acgh.rds")

    writeLines(c(
        '"BIOC_ACGH_STANDARD_ACGH_PIPELINE":',
        paste0('        acgh: ', as.character(packageVersion("acgh")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_acgh_pipeline.csv versions.yml
    """
}

workflow BIOC_ACGH_STANDARD_ACGH_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ clones.info.ex.txt, log2.ratios.ex.txt, pheno.type.ex.txt ] ]

    main:
    BIOC_ACGH_STANDARD_ACGH_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ACGH_STANDARD_ACGH_PIPELINE.out.tables
    plots    = BIOC_ACGH_STANDARD_ACGH_PIPELINE.out.plots
    objects  = BIOC_ACGH_STANDARD_ACGH_PIPELINE.out.objects
    versions = BIOC_ACGH_STANDARD_ACGH_PIPELINE.out.versions
}
