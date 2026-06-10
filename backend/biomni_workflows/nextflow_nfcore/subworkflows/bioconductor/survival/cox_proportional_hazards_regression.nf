#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survival — cox_proportional_hazards_regression
// Fit a semi-parametric Cox proportional hazards model to evaluate the effect of multiple continuous and categorical covariates on survival.
// Input: patient_clinical_data.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: survival
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the Cox proportional hazards model using coxph()
//  * 2. [Visualization & Output] Summarize hazard ratios and significance using summary()
//  * 3. [Core Analysis] Test the proportional hazards assumption using cox.zph()

nextflow.enable.dsl = 2

process BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION {
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
        
        # Load required library
        library(survival)
        
        # Read user input file
        clinical_data <- read.csv("patient_clinical_data.csv")
        
        # 1. Fit the Cox proportional hazards model using coxph()
        fit <- coxph(Surv(time, status) ~ ., data = clinical_data)
        
        # 2. Summarize hazard ratios and significance using summary()
        fit_summary <- summary(fit)
        print(fit_summary)
        
        # 3. Test the proportional hazards assumption using cox.zph()
        cz <- cox.zph(fit)
        print(cz)
        
        # Write outputs
        saveRDS(fit, "cox_fit.rds")
        
        # Extract and save coefficients and hazard ratios
        coef_df <- as.data.frame(fit_summary\$coefficients)
        write.csv(coef_df, "cox_coefficients.csv", row.names = TRUE)
        
        confint_df <- as.data.frame(fit_summary\$conf.int)
        write.csv(confint_df, "cox_hazard_ratios.csv", row.names = TRUE)
        
        # Save proportional hazards test results
        cz_df <- as.data.frame(cz\$table)
        write.csv(cz_df, "cox_zph_test.csv", row.names = TRUE)
        
        # Save diagnostic plots
        pdf("cox_zph_plots.pdf")
        plot(cz)
        dev.off()

    writeLines(c(
        '"BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION":',
        paste0('    survival: ', as.character(packageVersion('survival')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cox_proportional_hazards_regression.csv versions.yml
    """
}

workflow BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ patient_clinical_data.csv ] ]

    main:
    BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION(ch_input)

    emit:
    tables   = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.tables
    plots    = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.plots
    objects  = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.objects
    versions = BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION.out.versions
}
