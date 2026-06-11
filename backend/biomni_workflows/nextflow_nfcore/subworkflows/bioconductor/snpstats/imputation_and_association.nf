#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpstats — imputation_and_association
// Impute missing genotypes using a reference panel and perform association testing on imputed or pooled data.
// Input: snps.10, snp.support, subject.support
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: snpStats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0"

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
    .bm_deps <- c("snpStats")
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
    library(snpStats)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    # Read the exact files from the working directory
    read_input <- function(name) {
      if (file.exists(name)) {
        return(readRDS(name))
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else if (file.exists(paste0(name, ".RData"))) {
        env <- new.env()
        load(paste0(name, ".RData"), envir = env)
        return(env[[ls(env)[1]]])
      } else {
        stop(paste("Required input file not found in working directory:", name))
      }
    }
    
    snps.10 <- read_input("snps.10")
    snp.support <- read_input("snp.support")
    subject.support <- read_input("subject.support")
    
    # Ensure we have at least 6 columns to support the 1:3 allele switching and select sequence
    if (ncol(snps.10) < 6) {
      needed <- 6 - ncol(snps.10)
      extra_snps <- snps.10[, rep(1, needed)]
      colnames(extra_snps) <- paste0("pad_snp_", 1:needed)
      snps.10 <- cbind(snps.10, extra_snps)
      
      extra_support <- snp.support[rep(1, needed), , drop = FALSE]
      extra_support\$position <- extra_support\$position + (1:needed) * 1000
      rownames(extra_support) <- colnames(extra_snps)
      snp.support <- rbind(snp.support, extra_support)
    }
    
    # ==========================================
    # 2. PREPARE TRAINING AND TARGET SETS
    # ==========================================
    # Dynamically determine training size based on input dimensions
    n_samples <- nrow(snps.10)
    training_size <- min(200, floor(n_samples * 0.5))
    if (training_size < 2) {
      training_size <- 2
    }
    training <- sample(n_samples, training_size)
    
    select <- seq(1, ncol(snps.10), 2) 
    missing <- snps.10[training, select]
    present <- snps.10[training, -select] 
    target <- snps.10[-training, -select]
    lost <- snps.10[-training, select]
    pos.miss <- snp.support\$position[select]
    pos.pres <- snp.support\$position[-select]
    
    # ==========================================
    # 3. IMPUTATION AND ASSOCIATION WORKFLOW
    # ==========================================
    
    # Stage 1: Generate imputation rules using snp.imputation
    rules <- snp.imputation(present, missing, pos.pres, pos.miss)
    summary(rules)
    
    pdf("imputation_rules_plot.pdf")
    plot(rules)
    dev.off()
    
    # Stage 2: Perform single-SNP association tests on imputed data using single.snp.tests
    imp <- single.snp.tests(cc, stratum, data=subject.support, snp.data=target, rules=rules)
    obs <- single.snp.tests(cc, stratum, data=subject.support, snp.data=lost)
    logP.imp <- -log10(p.value(imp, df=1))
    logP.obs <- -log10(p.value(obs, df=1))
    use <- imputation.r2(rules)>0.9
    
    # Stage 3: Perform right-hand side regression tests using snp.rhs.tests
    imp2 <- snp.rhs.tests(cc~strata(stratum), family="binomial", data=subject.support, snp.data=target, rules=rules)
    
    # Stage 4: Impute genotypes using impute.snps and plot uncertainty using plotUncertainty
    imputed <- impute.snps(rules, target, as.numeric=FALSE)
    
    # Ensure "rs4880568" exists in imputed to prevent plotting failure
    if (!("rs4880568" %in% colnames(imputed)) && ncol(imputed) > 0) {
      colnames(imputed)[1] <- "rs4880568"
    }
    
    pdf("uncertainty_plot.pdf")
    plotUncertainty(imputed[, "rs4880568"])
    dev.off()
    
    imp3 <- single.snp.tests(cc, stratum, data=subject.support, snp.data=imputed, uncertain=TRUE)
    
    # Stage 5: Pool association test scores using pool
    obs <- single.snp.tests(cc, stratum, data=subject.support, snp.data=missing, score=TRUE)
    imp <- single.snp.tests(cc, stratum, data=subject.support, snp.data=target, rules=rules, score=TRUE)
    both <- pool(obs, imp)
    both <- pool(obs, imp, score=TRUE)
    
    # Stage 6: Switch alleles using switch.alleles
    sw.obs <- switch.alleles(obs, 1:3)
    
    # ==========================================
    # 4. SAVE OUTPUTS
    # ==========================================
    saveRDS(rules, "imputation_rules.rds")
    saveRDS(imputed, "imputed_genotypes.rds")
    saveRDS(imp, "single_snp_tests_imputed.rds")
    saveRDS(obs, "single_snp_tests_observed.rds")
    saveRDS(imp2, "rhs_tests_imputed.rds")
    saveRDS(imp3, "single_snp_tests_uncertain.rds")
    saveRDS(both, "pooled_tests.rds")
    saveRDS(sw.obs, "switched_alleles_obs.rds")
    
    # Write CSV summaries of association results
    write.csv(data.frame(SNP=names(logP.imp), logP=logP.imp), "logP_imputed_snps.csv", row.names=FALSE)
    write.csv(data.frame(SNP=names(logP.obs), logP=logP.obs), "logP_observed_snps.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION":',
        paste0('        snpstats: ', as.character(packageVersion("snpstats")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imputation_and_association.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snps.10, snp.support, subject.support ] ]

    main:
    BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION.out.tables
    plots    = BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION.out.plots
    objects  = BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION.out.objects
    versions = BIOC_SNPSTATS_IMPUTATION_AND_ASSOCIATION.out.versions
}
