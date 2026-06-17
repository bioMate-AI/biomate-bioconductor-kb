#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCARE — absolute_risk_model_validation
// Validate an absolute risk model using cohort or nested case-control study data.
// Input: validation.cohort.data, validation.nested.case.control.data
// Container: quay.io/biocontainers/bioconductor-icare:1.38.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iCARE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate sampling weights for nested case-control data using logistic regression (glm)
//  * 2. [Input & Preparation] Define the risk model object as a list of parameters
//  * 3. [Core Analysis] Run model validation using ModelValidation
//  * 4. [Visualization & Output] Plot validation results using plotModelValidation

nextflow.enable.dsl = 2

process BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("iCARE")
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
    library(iCARE)
    
    # Helper function to load user input files robustly
    load_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      }
      if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      }
      if (file.exists(paste0(filename, ".csv"))) {
        return(read.csv(paste0(filename, ".csv"), stringsAsFactors = FALSE))
      }
      stop(paste("Required input file not found:", filename))
    }
    
    # Load the user-provided datasets
    validation.cohort.data <- load_input("validation.cohort.data")
    nested_input <- load_input("validation.nested.case.control.data")
    
    # Extract model parameters and study data from the inputs
    if (is.list(nested_input) && !is.data.frame(nested_input)) {
      validation.nested.case.control.data <- nested_input\$study.data
      bc_model_formula <- nested_input\$model.formula
      bc_model_cov_info <- nested_input\$model.cov.info
      bc_72_snps <- nested_input\$model.snp.info
      bc_model_log_or <- nested_input\$model.log.RR
      ref_cov_dat <- nested_input\$model.ref.dataset
      bc_inc <- nested_input\$model.disease.incidence.rates
      mort_inc <- nested_input\$model.competing.incidence.rates
    } else {
      validation.nested.case.control.data <- nested_input
      bc_model_formula <- attr(nested_input, "model.formula")
      bc_model_cov_info <- attr(nested_input, "model.cov.info")
      bc_72_snps <- attr(nested_input, "model.snp.info")
      bc_model_log_or <- attr(nested_input, "model.log.RR")
      ref_cov_dat <- attr(nested_input, "model.ref.dataset")
      bc_inc <- attr(nested_input, "model.disease.incidence.rates")
      mort_inc <- attr(nested_input, "model.competing.incidence.rates")
    }
    
    # Fallback check in validation.cohort.data if parameters are still NULL
    if (is.null(bc_model_formula)) {
      if (is.list(validation.cohort.data) && !is.data.frame(validation.cohort.data)) {
        bc_model_formula <- validation.cohort.data\$model.formula
        bc_model_cov_info <- validation.cohort.data\$model.cov.info
        bc_72_snps <- validation.cohort.data\$model.snp.info
        bc_model_log_or <- validation.cohort.data\$model.log.RR
        ref_cov_dat <- validation.cohort.data\$model.ref.dataset
        bc_inc <- validation.cohort.data\$model.disease.incidence.rates
        mort_inc <- validation.cohort.data\$model.competing.incidence.rates
        validation.cohort.data <- validation.cohort.data\$study.data
      }
    }
    
    # 1. Calculate sampling weights for nested case-control data using logistic regression (glm)
    validation.cohort.data\$inclusion = 0
    subjects_included = intersect(validation.cohort.data\$id,
                                validation.nested.case.control.data\$id)
    validation.cohort.data\$inclusion[subjects_included] = 1
    
    validation.cohort.data\$observed.followup =
                            validation.cohort.data\$study.exit.age -
                                validation.cohort.data\$study.entry.age
    
    selection.model = glm(inclusion ~ observed.outcome
                           * (study.entry.age + observed.followup),
                                  data = validation.cohort.data,
                                  family = binomial(link = "logit"))
    validation.nested.case.control.data\$sampling.weights =
            selection.model\$fitted.values[validation.cohort.data\$inclusion == 1]
    
    # 2. Define the risk model object as a list of parameters
    data = validation.nested.case.control.data
    risk.model = list(model.formula = bc_model_formula,
                       model.cov.info = bc_model_cov_info,
                       model.snp.info = bc_72_snps,
                       model.log.RR = bc_model_log_or,
                       model.ref.dataset = ref_cov_dat,
                       model.ref.dataset.weights = NULL,
                       model.disease.incidence.rates = bc_inc,
                       model.competing.incidence.rates = mort_inc,
                       model.bin.fh.name = "famhist",
                       apply.cov.profile = data[,all.vars(bc_model_formula)[-1]],
                       apply.snp.profile = data[,bc_72_snps\$snp.name],
                       n.imp = 5, use.c.code = 1, return.lp = TRUE,
                       return.refs.risk = TRUE)
    
    # 3. Run model validation using ModelValidation
    output = ModelValidation(study.data = data,
                             total.followup.validation = TRUE,
                             predicted.risk.interval = NULL,
                             iCARE.model.object = risk.model,
                             number.of.percentiles = 10)
    
    # Save validation results object
    saveRDS(output, file = "validation_results.rds")
    
    # 4. Plot validation results using plotModelValidation
    pdf("validation_plots.pdf", width = 10, height = 8)
    plotModelValidation(study.data = data,validation.results = output)
    dev.off()

    writeLines(c(
        '"BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION":',
        paste0('    iCARE: ', as.character(packageVersion('iCARE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_absolute_risk_model_validation.csv versions.yml
    """
}

workflow BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ validation.cohort.data, validation.nested.case.control.data ] ]

    main:
    BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION(ch_input)

    emit:
    tables   = BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION.out.tables
    plots    = BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION.out.plots
    objects  = BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION.out.objects
    versions = BIOC_ICARE_ABSOLUTE_RISK_MODEL_VALIDATION.out.versions
}
