#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_regression_cohorts
// Identify miRNA-mRNA target interactions in a cohort using various GLM regression models integrated with miRanda predictions.
// Input: EBV_mRNA.txt.gz, EBV_miRNA.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mirTarRnaSeq, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mirTarRnaSeq, reshape2
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load mRNA and miRNA expression data
//  * 2. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 3. [Core Analysis] Filter mRNA data to keep only predicted targets using miRanComp
//  * 4. [Core Analysis] Combine mRNA and miRNA data for selected miRNAs using combiner and geneVari
//  * 5. [Core Analysis] Run univariate or multivariate GLM models using runModel or runModels with specified families (e.g., glm_gaussian(), glm_poisson()
//  * 6. [Core Analysis] Evaluate model performance using AIC values and select the best-fitting model
//  * 7. [Core Analysis] Run all-to-all combinations using runAllMirnaModels

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ggplot2", "mirTarRnaSeq", "reshape2")
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
    library(mirTarRnaSeq)
    library(ggplot2)
    library(reshape2)
    
    # 1. Load mRNA and miRNA expression data from the working directory
    DiffExp <- read.table("EBV_mRNA.txt.gz", as.is = TRUE, header = TRUE, row.names = 1)
    miRNAExp <- read.table("EBV_miRNA.txt.gz", as.is = TRUE, header = TRUE, row.names = 1)
    
    # 2. Retrieve species-specific miRanda target predictions using getInputSpecies
    miRanda <- getInputSpecies("Epstein_Barr", threshold = 140)
    
    # 3. Filter mRNA data to keep only predicted targets using miRanComp
    DiffExpmRNASub <- miRanComp(DiffExp, miRanda)
    
    # 4. Combine mRNA and miRNA data for selected miRNAs using combiner and geneVari
    miRNA_select <- c("ebv-mir-BART9-5p")
    Combine <- combiner(DiffExp, miRNAExp, miRNA_select)
    geneVariant <- geneVari(Combine, miRNA_select)
    
    # 5. Run univariate GLM models using runModel or runModels with specified families
    # Run a single Poisson model
    j <- runModel(`LMP-1` ~ `ebv-mir-BART9-5p`,
                  Combine, model = glm_poisson(),
                  scale = 100)
    p_val_j <- modelTermPvalues(j)
    print(p_val_j)
    write.csv(as.data.frame(p_val_j), "LMP1_BART9_poisson_pvalue.csv")
    
    # Run Gaussian models
    blaGaus <- runModels(Combine,
                         geneVariant, miRNA_select,
                         family = glm_gaussian(),
                         scale = 100)
    
    pdf("gaussian_models_plots.pdf", width = 10, height = 7)
    par(oma = c(2, 2, 2, 2))
    par(mfrow = c(2, 3), mar = c(4, 3, 3, 2))
    plot(blaGaus[["all_models"]][["BHLF1"]])
    plot(modelData(blaGaus[["all_models"]][["BHLF1"]]))
    G <- do.call(rbind.data.frame, blaGaus[["AICvalues"]])
    names(G) <- c("AIC_G")
    plot(density(G\$AIC_G))
    dev.off()
    
    GM <- melt(G)
    
    # Run Poisson models
    blaPois <- runModels(Combine,
                         geneVariant, miRNA_select,
                         family = glm_poisson(),
                         scale = 100)
    
    pdf("poisson_models_plots.pdf", width = 10, height = 7)
    par(oma = c(2, 2, 2, 2))
    par(mfrow = c(2, 3), mar = c(4, 3, 3, 2))
    plot(blaPois[["all_models"]][["LMP-2A"]])
    plot(modelData(blaPois[["all_models"]][["LMP-2A"]]))
    P <- do.call(rbind.data.frame, blaPois[["AICvalues"]])
    names(P) <- c("AIC_Po")
    dev.off()
    
    PM <- melt(P)
    
    # Run Negative Binomial models
    blaNB <- runModels(Combine,
                       geneVariant, miRNA_select,
                       family = glm_nb(), scale = 100)
    
    pdf("nb_models_plots.pdf", width = 8, height = 6)
    par(mar = c(4, 3, 3, 2))
    plot(modelData(blaNB[["all_models"]][["BALF1"]]))
    dev.off()
    
    B <- do.call(rbind.data.frame, blaNB[["AICvalues"]])
    names(B) <- c("AIC_NB")
    BM <- melt(B)
    
    # Run Zero-Inflated Negative Binomial models
    blazeroinflNB <- runModels(Combine, geneVariant,
                                miRNA_select,
                                family = glm_zeroinfl(dist = "negbin"),
                                scale = 100)
    ZNB <- do.call(rbind.data.frame, blazeroinflNB[["AICvalues"]])
    names(ZNB) <- c("AIC_ZNB")
    
    pdf("zeroinfl_nb_density.pdf", width = 6, height = 5)
    par(mar = c(4, 3, 3, 2))
    plot(density(ZNB\$AIC_ZNB))
    dev.off()
    
    ZNBM <- melt(ZNB)
    
    # Run Zero-Inflated Poisson models
    blazeroinfl <- runModels(Combine, geneVariant,
                             miRNA_select,
                             family = glm_zeroinfl(),
                             scale = 100)
    Zp <- do.call(rbind.data.frame, blazeroinfl[["AICvalues"]])
    names(Zp) <- c("AIC_Zp")
    
    pdf("zeroinfl_poisson_density.pdf", width = 6, height = 5)
    par(mar = c(4, 3, 3, 2))
    plot(density(Zp\$AIC_Zp))
    dev.off()
    
    ZpM <- melt(Zp)
    
    # 6. Evaluate model performance using AIC values and select the best-fitting model
    bindM <- rbind(PM, BM, GM, ZpM, ZNBM)
    p2 <- ggplot(data = bindM, aes(x = value, group = variable,
                                   fill = variable)) +
      geom_density(adjust = 1.5, alpha = .3) +
      xlim(-400, 2000) +
      ggtitle("Plot of of AIC for ebv-mir-BART9-5p regressed all mRNAs ") +
      ylab("Density") + xlab("AIC Value")
    
    ggsave("combined_AIC_density_plot.pdf", plot = p2, width = 7, height = 5)
    
    # Run Multivariate Models
    miRNA_select <- c("ebv-mir-BART9-5p", "ebv-mir-BART6-3p")
    Combine <- combiner(DiffExp, miRNAExp, miRNA_select)
    geneVariant <- geneVari(Combine, miRNA_select)
    
    MultiModel <- runModels(Combine, geneVariant,
                            miRNA_select, family = glm_multi(),
                            mode = "multi", scale = 10)
    multi_model_names <- table(unlist(lapply(MultiModel\$all_models, modelModelName)))
    print(multi_model_names)
    write.csv(as.data.frame(multi_model_names), "multimodel_selected_names.csv")
    
    # Run Interaction Models
    InterModel <- runModels(Combine,
                            geneVariant, miRNA_select,
                            family = glm_multi(
                              models = list(glm_gaussian,
                              glm_poisson())), mode = "inter", scale = 10)
    inter_model_names <- table(unlist(lapply(InterModel\$all_models, modelModelName)))
    print(inter_model_names)
    write.csv(as.data.frame(inter_model_names), "intermodel_selected_names.csv")
    
    # 7. Run all-to-all combinations using runAllMirnaModels
    vMiRNA <- rownames(miRNAExp)
    All_miRNAs_run <- runAllMirnaModels(mirnas = vMiRNA[1:5],
                                      DiffExpmRNA = DiffExpmRNASub,
                                      DiffExpmiRNA = miRNAExp,
                                      miranda_data = miRanda, prob = 0.75,
                                      cutoff = 0.05, fdr_cutoff = 0.1, method = "fdr",
                                      family = glm_multi(), scale = 2, mode = "multi")
    
    hasgenes <- lapply(All_miRNAs_run, function(x) nrow(x\$SigFDRGenes)) > 0
    All_miRNAs_run <- All_miRNAs_run[hasgenes]
    
    # Print specific model summaries
    if (length(All_miRNAs_run) > 0) {
      print(table(unlist(lapply(All_miRNAs_run[[1]][["FDRModel"]][["all_models"]], modelModelName))))
    }
    
    target_name <- "ebv-mir-BART1-5p and ebv-mir-BART11-3p"
    if (target_name %in% names(All_miRNAs_run)) {
      print(table(unlist(lapply(All_miRNAs_run[[target_name]][["FDRModel"]][["all_models"]], modelModelName))))
    }
    
    # Save the all-miRNA run results
    saveRDS(All_miRNAs_run, "All_miRNAs_run.rds")
    
    # Optional SPONGE integration
    try({
      sponge_mir_input <- miranda_sponge_predict(miRNAExp, DiffExp, miRanda)
      one2many_output <- one2manySponge(miRNAExp, DiffExp, sponge_mir_input)
      saveRDS(one2many_output, "one2many_sponge_output.rds")
    })
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "count normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_regression_cohorts.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EBV_mRNA.txt.gz, EBV_miRNA.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.versions
}
