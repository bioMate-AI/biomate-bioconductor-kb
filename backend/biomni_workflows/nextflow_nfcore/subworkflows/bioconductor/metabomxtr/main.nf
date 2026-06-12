#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metabomxtr — mixture_model_association_analysis
// Run mixture model association analysis on metabolites with missing values to test for significant differences between phenotype groups while controlling for cov
// Input: experimental_metabolite_data.csv
// Container: quay.io/biocontainers/bioconductor-metabomxtr:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metabomxtr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define target metabolite names and set the reference level for categorical predictors. 2. Specify the full and reduced mixture mod

nextflow.enable.dsl = 2

process BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("metabomxtr")
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
    library(metabomxtr)
    
    # Read the user input file
    metabdata <- read.csv("experimental_metabolite_data.csv", header = TRUE, stringsAsFactors = FALSE)
    
    # Ensure PHENO is a factor for releveling
    metabdata\$PHENO <- as.factor(metabdata\$PHENO)
    
    # Define target metabolite names (identifying metabolites as columns containing missing values)
    yvars <- colnames(metabdata)[colSums(is.na(metabdata)) > 0]
    
    # Define covariates (all other columns except PHENO and the identified metabolites)
    covariates <- setdiff(colnames(metabdata), c("PHENO", yvars))
    
    # Set the reference level for categorical predictors dynamically
    ref_level <- levels(metabdata\$PHENO)[1]
    alt_level <- levels(metabdata\$PHENO)[2]
    metabdata\$PHENO <- relevel(metabdata\$PHENO, ref = ref_level)
    
    # Specify the full and reduced mixture model formulas dynamically
    if (length(covariates) > 0) {
      cov_form <- paste(covariates, collapse = "+")
      fullModel <- as.formula(paste("~PHENO|PHENO+", cov_form, sep = ""))
      reducedModel <- as.formula(paste("~1|", cov_form, sep = ""))
    } else {
      fullModel <- as.formula("~PHENO|PHENO")
      reducedModel <- as.formula("~1|1")
    }
    
    # Fit the full mixture model using mxtrmod
    fullModelResults <- mxtrmod(ynames = yvars, mxtrModel = fullModel, data = metabdata)
    
    # Fit the reduced mixture model using mxtrmod, specifying the fullModel parameter
    reducedModelResults <- mxtrmod(ynames = yvars, mxtrModel = reducedModel, data = metabdata, fullModel = fullModel)
    
    # Perform nested likelihood ratio tests using mxtrmodLRT
    finalResult <- mxtrmodLRT(fullmod = fullModelResults, redmod = reducedModelResults, adj = "BH")
    
    # Calculate estimated presence proportions and mean differences for reporting dynamically
    x_col <- paste0("x_PHENO", alt_level)
    z_col <- paste0("z_PHENO", alt_level)
    
    # Fallback if exact column name differs (e.g., due to special characters in factor levels)
    if (!(x_col %in% colnames(fullModelResults))) {
      x_col <- grep("^x_PHENO", colnames(fullModelResults), value = TRUE)[1]
      z_col <- grep("^z_PHENO", colnames(fullModelResults), value = TRUE)[1]
      alt_level <- sub("^x_PHENO", "", x_col)
    }
    
    Alt.Prop <- round(exp(fullModelResults\$xInt + fullModelResults[[x_col]]) /
    (1 + exp(fullModelResults\$xInt + fullModelResults[[x_col]])), digits = 2)
    
    Ref.Prop <- round(exp(fullModelResults\$xInt) / (1 + exp(fullModelResults\$xInt)), digits = 2)
    
    Alt.Mean <- round(fullModelResults\$zInt + fullModelResults[[z_col]], digits = 2)
    
    Ref.Mean <- round(fullModelResults\$zInt, digits = 2)
    
    MeanDiff <- round(fullModelResults[[z_col]], digits = 2)
    
    # Combine into final results table
    finalResultTable <- data.frame(
      Metabolite = fullModelResults\$.id,
      Alt.Prop = Alt.Prop,
      Ref.Prop = Ref.Prop,
      Alt.Mean = Alt.Mean,
      Ref.Mean = Ref.Mean,
      Mean.Difference = MeanDiff,
      FDR.Adj.P = round(finalResult\$adjP, digits = 4)
    )
    
    # Rename columns to reflect actual level names
    colnames(finalResultTable)[2:5] <- c(
      paste0(alt_level, ".Prop"),
      paste0(ref_level, ".Prop"),
      paste0(alt_level, ".Mean"),
      paste0(ref_level, ".Mean")
    )
    
    # Write outputs to CSV files
    write.csv(finalResultTable, "final_result_table.csv", row.names = FALSE)
    write.csv(fullModelResults, "full_model_results.csv", row.names = FALSE)
    write.csv(reducedModelResults, "reduced_model_results.csv", row.names = FALSE)
    write.csv(finalResult, "lrt_results.csv", row.names = FALSE)
    
    # Save RDS objects for downstream analysis
    saveRDS(fullModelResults, "full_model_results.rds")
    saveRDS(reducedModelResults, "reduced_model_results.rds")
    saveRDS(finalResult, "lrt_results.rds")

    writeLines(c(
        '"BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS":',
        paste0('    metabomxtr: ', as.character(packageVersion('metabomxtr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixture_model_association_analysis.csv versions.yml
    """
}

workflow BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experimental_metabolite_data.csv ] ]

    main:
    BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS.out.tables
    plots    = BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS.out.plots
    objects  = BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS.out.objects
    versions = BIOC_METABOMXTR_MIXTURE_MODEL_ASSOCIATION_ANALYSIS.out.versions
}
