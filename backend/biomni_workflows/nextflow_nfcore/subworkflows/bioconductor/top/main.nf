#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOP — transferable_survival_modeling
// Build and evaluate a transferable survival model across multiple independent gene expression datasets.
// Input: list_ovarian_eset
// Container: quay.io/biocontainers/bioconductor-top:1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, TOP, dplyr, ggbeeswarm, ggsci, purrr, survival, survminer, tibble, tidyverse
// Visualizations: density plot, survival plot, box plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify common features (genes) across all datasets
//  * 2. [Core Analysis] Extract and align survival metadata (time and event status)
//  * 3. [Core Analysis] Subset and transpose gene expression matrices to match survival samples and common genes
//  * 4. [Core Analysis] Train the transferable survival model using TOP_survival
//  * 5. [Core Analysis] Evaluate model performance (concordance index) using Surv_TOP_CI

nextflow.enable.dsl = 2

process BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING {
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
    .bm_deps <- c("tidyverse", "survival", "dplyr", "survminer", "Biobase", "ggsci", "ggbeeswarm", "TOP")
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
    suppressPackageStartupMessages({
      library(tidyverse)
      library(survival)
      library(dplyr)
      library(survminer)
      library(Biobase)
      library(ggsci)
      library(ggbeeswarm)
      library(TOP)
    })
    
    # Set theme for plotting
    theme_set(theme_bw())
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    input_file <- "list_ovarian_eset"
    if (!file.exists(input_file)) {
      if (file.exists("list_ovarian_eset.rds")) {
        input_file <- "list_ovarian_eset.rds"
      } else {
        stop("Error: Required input file 'list_ovarian_eset' or 'list_ovarian_eset.rds' not found in the working directory.")
      }
    }
    
    message("Reading input file: ", input_file)
    list_ovarian_eset <- readRDS(input_file)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Identify common features (genes) across all datasets
    # -----------------------------------------------------------------------------
    message("Identifying common genes across datasets...")
    raw_gene_list <- purrr::map(list_ovarian_eset, rownames)
    common_genes <- Reduce(f = intersect, x = raw_gene_list)
    message("Number of common genes: ", length(common_genes))
    
    # -----------------------------------------------------------------------------
    # Stage 2: Extract and align survival metadata (time and event status)
    # -----------------------------------------------------------------------------
    message("Extracting and aligning survival metadata...")
    ov_pdata <- purrr::map(list_ovarian_eset, pData)
    list_pdata <- list_ovarian_eset %>%
      purrr::map(pData) %>%
      purrr::map(tibble::rownames_to_column, var = "sample_id")
    
    ov_surv_raw <- purrr::map(
      .x = list_pdata,
      .f = ~ data.frame(
        sample_id = .x\$sample_id,
        time = .x\$days_to_death %>% as.integer(),
        dead = ifelse(.x\$vital_status == "deceased", 1, 0)
      ) %>%
        na.omit() %>%
        dplyr::filter(
          time > 0,
          !is.nan(time),
          !is.nan(dead)
        )
    )
    
    ov_surv_y <- ov_surv_raw %>%
      purrr::map(~ .x %>%
        dplyr::select(-sample_id)) %>%
      purrr::map(~ Surv(time = .x\$time, event = .x\$dead))
    
    # -----------------------------------------------------------------------------
    # Stage 3: Subset and transpose gene expression matrices
    # -----------------------------------------------------------------------------
    message("Subsetting and transposing gene expression matrices...")
    ov_surv_exprs <- purrr::map2(
      .x = list_ovarian_eset,
      .y = ov_surv_raw,
      .f = ~ exprs(.x[common_genes, .y\$sample_id])
    )
    
    ov_surv_tbl <- ov_surv_raw %>%
      bind_rows(.id = "data_source")
    
    # Save survival distribution plot
    message("Generating survival times density plot...")
    pdf("survival_times_density.pdf", width = 8, height = 6)
    p1 <- ov_surv_tbl %>%
      ggplot(aes(
        x = time,
        y = after_stat(density),
        fill = data_source
      )) +
      geom_density(alpha = 0.25) +
      scale_fill_d3() +
      labs(title = "Distribution of Survival Times Across Datasets", x = "Time (days)", y = "Density")
    print(p1)
    dev.off()
    
    surv_list <- ov_surv_tbl %>%
      split(ov_surv_tbl\$data_source)
    surv_list <- lapply(surv_list, function(x) x[, 3:4])
    
    surv_counts <- ov_surv_exprs %>% lapply(t)
    surv_list <- surv_list[names(surv_counts)]
    
    # -----------------------------------------------------------------------------
    # Stage 4: Train the transferable survival model using TOP_survival
    # -----------------------------------------------------------------------------
    message("Training the TOP survival model...")
    surv_model <- TOP_survival(
      x_list = surv_counts, y_list = surv_list, nFeatures = 10
    )
    
    # Save the trained model
    saveRDS(surv_model, "surv_model.rds")
    message("Model saved to 'surv_model.rds'")
    
    # -----------------------------------------------------------------------------
    # Stage 5: Evaluate model performance (concordance index) using Surv_TOP_CI
    # -----------------------------------------------------------------------------
    message("Evaluating model performance...")
    conf_results <- unlist(lapply(seq_along(surv_counts), function(x) {
      Surv_TOP_CI(
        surv_model,
        newx = surv_counts[[x]], newy = surv_list[[x]]
      )\$concordance
    }))
    
    # Format and save concordance results
    names(conf_results) <- names(surv_counts)
    conf_results_df <- conf_results %>%
      tibble::enframe(name = "Dataset", value = "C_Index")
    
    write.csv(conf_results_df, "concordance_results.csv", row.names = FALSE)
    message("Concordance results saved to 'concordance_results.csv'")
    
    # Save concordance boxplot
    message("Generating concordance index boxplot...")
    pdf("concordance_boxplot.pdf", width = 6, height = 6)
    p2 <- conf_results_df %>%
      mutate(Metric = "C-index") %>%
      ggplot(aes(y = C_Index, x = Metric)) +
      geom_boxplot(width = 0.5) +
      ylab("C-index") +
      geom_jitter(alpha = 0.7, width = 0.1) +
      theme(axis.text.x = element_blank()) +
      xlab("Survival Model") +
      labs(title = "Model Performance (C-index) Across Datasets")
    print(p2)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING":',
        paste0('    TOP: ', as.character(packageVersion('TOP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transferable_survival_modeling.csv versions.yml
    """
}

workflow BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_ovarian_eset ] ]

    main:
    BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING(ch_input)

    emit:
    tables   = BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING.out.tables
    plots    = BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING.out.plots
    objects  = BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING.out.objects
    versions = BIOC_TOP_TRANSFERABLE_SURVIVAL_MODELING.out.versions
}
