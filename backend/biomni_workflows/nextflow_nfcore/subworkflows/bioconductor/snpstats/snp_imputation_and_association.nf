#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpStats — snp_imputation_and_association
// Perform SNP imputation using a training set, generate imputation rules, and run association tests on imputed or observed genotypes.
// Input: snps.10, snp.support$position, subject.support
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: snpStats
// Bioconductor: 3.20 | R: 4.4
// Requires: snpStats
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Split data into training and target sets
//  * 2. [Core Analysis] Generate imputation rules using snp.imputation
//  * 3. [Core Analysis] Run single SNP association tests on target data using rules with single.snp.tests
//  * 4. [Core Analysis] Run multi-SNP association tests using snp.rhs.tests
//  * 5. [Core Analysis] Impute posterior genotype probabilities using impute.snps
//  * 6. [Core Analysis] Run association tests on imputed genotypes with uncertainty using single.snp.tests with uncertain=TRUE
//  * 7. [Core Analysis] Pool association test statistics using pool
//  * 8. [Core Analysis] Resolve allele strand/coding issues using switch.alleles

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
        
        # Load required libraries
        library(snpStats)
        
        # 1. Read user input files from the working directory
        snps.10 <- readRDS("snps.10.rds")
        snp.support.position <- readRDS("snp.support.position.rds")
        snp.support <- list(position = snp.support.position)
        subject.support <- readRDS("subject.support.rds")
        
        # 2. Split data into training and target sets
        n_samples <- nrow(snps.10)
        n_train <- min(200, max(1, floor(n_samples * 0.8)))
        training <- sample(n_samples, n_train)
        
        select <- seq(1, ncol(snps.10), 2) 
        missing <- snps.10[training, select]
        present <- snps.10[training, -select] 
        target <- snps.10[-training, -select]
        lost <- snps.10[-training, select]
        pos.miss <- snp.support\$position[select]
        pos.pres <- snp.support\$position[-select]
        
        # 3. Generate imputation rules using snp.imputation
        rules <- snp.imputation(present, missing, pos.pres, pos.miss)
        saveRDS(rules, "imputation_rules.rds")
        
        # 4. Run single SNP association tests on target data using rules
        imp <- single.snp.tests(cc, stratum, data=subject.support,
                                snp.data=target, rules=rules)
        saveRDS(imp, "association_imp.rds")
        
        obs <- single.snp.tests(cc, stratum, data=subject.support, snp.data=lost)
        saveRDS(obs, "association_obs.rds")
        
        use <- imputation.r2(rules)>0.9
        
        # 5. Run multi-SNP association tests using snp.rhs.tests
        imp2 <- snp.rhs.tests(cc~strata(stratum), family="binomial", 
                              data=subject.support, snp.data=target, rules=rules)
        saveRDS(imp2, "association_imp2.rds")
        
        # 6. Impute posterior genotype probabilities using impute.snps
        imputed <- impute.snps(rules, target, as.numeric=FALSE)
        saveRDS(imputed, "imputed_genotypes.rds")
        
        # Plot uncertainty
        pdf("uncertainty_plot.pdf")
        tryCatch({
          plotUncertainty(imputed[, "rs4880568"])
        }, error = function(e) {
          warning("plotUncertainty failed for rs4880568: ", e\$message)
          if (ncol(imputed) > 0) {
            plotUncertainty(imputed[, 1])
          }
        })
        dev.off()
        
        # 7. Run association tests on imputed genotypes with uncertainty
        imp3 <- single.snp.tests(cc, stratum, data=subject.support,
                                snp.data=imputed, uncertain=TRUE)
        saveRDS(imp3, "association_imp3.rds")
        
        # 8. Score tests and pooling
        obs <- single.snp.tests(cc, stratum, data=subject.support, snp.data=missing, 
                                score=TRUE)
        imp <- single.snp.tests(cc, stratum, data=subject.support,
                                snp.data=target, rules=rules, score=TRUE)
        
        both <- pool(obs, imp)
        saveRDS(both, "pooled_results.rds")
        
        both <- pool(obs, imp, score=TRUE)
        saveRDS(both, "pooled_results_score.rds")
        
        # 9. Resolve allele strand/coding issues using switch.alleles
        tryCatch({
          sw.obs <- switch.alleles(obs, 1:3)
          saveRDS(sw.obs, "sw_obs.rds")
        }, error = function(e) {
          warning("switch.alleles failed: ", e\$message)
        })
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION":',
        paste0('    snpStats: ', as.character(packageVersion('snpStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_imputation_and_association.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snps.10, snp.support$position, subject.support ] ]

    main:
    BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION.out.tables
    plots    = BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION.out.plots
    objects  = BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION.out.objects
    versions = BIOC_SNPSTATS_SNP_IMPUTATION_AND_ASSOCIATION.out.versions
}
