#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCFA — multi_omics_subtyping
// Identify robust disease subtypes from multi-omics data using consensus factor analysis.
// Input: dataList, survival
// Container: quay.io/biocontainers/bioconductor-scfa:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SCFA, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SCFA and survival packages
//  * 2. [Input & Preparation] Prepare the multi-omics data list
//  * 3. [Core Analysis] Run the SCFA function to generate subtype assignments
//  * 4. [Core Analysis] Perform survival analysis using coxph to evaluate the clinical significance of the subtypes

nextflow.enable.dsl = 2

process BIOC_SCFA_MULTI_OMICS_SUBTYPING {
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
    
    # 1. Load the SCFA and survival packages
    library(SCFA)
    library(survival)
    
    # 2. Prepare the multi-omics data list
    # Read the user input files from the working directory
    if (!file.exists("dataList.rds") || !file.exists("survival.rds")) {
      stop("Error: Required input files 'dataList.rds' and/or 'survival.rds' are missing from the working directory.")
    }
    
    dataList <- readRDS("dataList.rds")
    survival <- readRDS("survival.rds")
    
    # 3. Run the SCFA function to generate subtype assignments
    set.seed(1)
    subtype <- SCFA(dataList, seed = 1, ncores = 4L)
    
    # 4. Perform survival analysis using coxph to evaluate the clinical significance of the subtypes
    coxFit <- coxph(Surv(time = Survival, event = Death) ~ as.factor(subtype), data = survival, ties="exact")
    coxP <- round(summary(coxFit)\$sctest[3], digits = 20)
    print(coxP)
    
    # 5. Write named output files for the results
    # Save subtype assignments
    subtype_df <- data.frame(
      Sample = rownames(dataList[[1]]),
      Subtype = subtype,
      stringsAsFactors = FALSE
    )
    write.csv(subtype_df, "subtype_assignments.csv", row.names = FALSE)
    saveRDS(subtype, "subtype.rds")
    
    # Save Cox regression summary statistics
    cox_summary <- summary(coxFit)
    cox_results <- data.frame(
      Metric = c("Logrank_p_value", "Likelihood_ratio_test_stat", "Wald_test_stat"),
      Value = c(coxP, cox_summary\$logtest[1], cox_summary\$waldtest[1]),
      stringsAsFactors = FALSE
    )
    write.csv(cox_results, "cox_survival_analysis_results.csv", row.names = FALSE)
    
    # Generate and save Kaplan-Meier survival plot
    pdf("survival_plot.pdf", width = 7, height = 6)
    fit <- survfit(Surv(time = Survival, event = Death) ~ as.factor(subtype), data = survival)
    plot(fit, col = seq_along(unique(subtype)), lty = 1, lwd = 2,
         xlab = "Time", ylab = "Survival Probability",
         main = paste0("Kaplan-Meier Survival Curve (p = ", format(coxP, digits = 4), ")"))
    legend("bottomleft", legend = paste("Subtype", sort(unique(subtype))),
           col = seq_along(unique(subtype)), lty = 1, lwd = 2)
    dev.off()

    writeLines(c(
        '"BIOC_SCFA_MULTI_OMICS_SUBTYPING":',
        paste0('    SCFA: ', as.character(packageVersion('SCFA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omics_subtyping.csv versions.yml
    """
}

workflow BIOC_SCFA_MULTI_OMICS_SUBTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataList, survival ] ]

    main:
    BIOC_SCFA_MULTI_OMICS_SUBTYPING(ch_input)

    emit:
    tables   = BIOC_SCFA_MULTI_OMICS_SUBTYPING.out.tables
    plots    = BIOC_SCFA_MULTI_OMICS_SUBTYPING.out.plots
    objects  = BIOC_SCFA_MULTI_OMICS_SUBTYPING.out.objects
    versions = BIOC_SCFA_MULTI_OMICS_SUBTYPING.out.versions
}
