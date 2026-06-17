#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — surrogate_variable_analysis
// Identify and adjust for latent, unknown sources of variation in continuous high-throughput data (e.g., microarrays) during differential expression analysis.
// Input: expression_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: limma, sva
// Visualizations: plot (ggplot/base)
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract phenotype and expression data
//  * 2. [Input & Preparation] Create full and null model matrices
//  * 3. [Core Analysis] Estimate the number of surrogate variables using num.sv
//  * 4. [Core Analysis] Estimate surrogate variables using sva
//  * 5. [Core Analysis] Perform differential expression analysis adjusting for surrogate variables using f.pvalue or limma

nextflow.enable.dsl = 2

process BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS {
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
    .bm_deps <- c("sva", "limma")
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
    library(sva)
    library(limma)
    
    # 1. Extract phenotype and expression data from user input files
    edata <- as.matrix(read.csv("expression_matrix.csv", row.names=1, check.names=FALSE))
    pheno <- read.csv("phenotype_data.csv", row.names=1, check.names=FALSE)
    
    # Align samples between expression matrix and phenotype data
    common_samples <- intersect(colnames(edata), rownames(pheno))
    if (length(common_samples) == 0) {
      stop("No common samples found between expression_matrix.csv and phenotype_data.csv")
    }
    edata <- edata[, common_samples, drop=FALSE]
    pheno <- pheno[common_samples, , drop=FALSE]
    
    # 2. Create full and null model matrices
    # Dynamically assign the first column as the variable of interest and the rest as adjustment variables
    var_of_interest <- colnames(pheno)[1]
    adj_vars <- colnames(pheno)[-1]
    
    if (length(adj_vars) > 0) {
      formula_full <- as.formula(paste0("~ as.factor(`", var_of_interest, "`) + ", paste0("`", adj_vars, "`", collapse=" + ")))
      formula_null <- as.formula(paste0("~ ", paste0("`", adj_vars, "`", collapse=" + ")))
    } else {
      formula_full <- as.formula(paste0("~ as.factor(`", var_of_interest, "`)"))
      formula_null <- as.formula("~ 1")
    }
    
    mod = model.matrix(formula_full, data=pheno)
    mod0 = model.matrix(formula_null, data=pheno)
    
    # 3. Estimate the number of surrogate variables using num.sv
    n.sv = num.sv(edata,mod,method="leek")
    
    # 4. Estimate surrogate variables using sva
    svobj = sva(edata,mod,mod0,n.sv=n.sv)
    
    # 5. Perform differential expression analysis adjusting for surrogate variables
    # Calculate p-values and q-values without SVA adjustment
    pValues = f.pvalue(edata,mod,mod0)
    qValues = p.adjust(pValues,method="BH")
    
    # Calculate p-values and q-values with SVA adjustment
    modSv = cbind(mod,svobj\$sv)
    mod0Sv = cbind(mod0,svobj\$sv)
    pValuesSv = f.pvalue(edata,modSv,mod0Sv)
    qValuesSv = p.adjust(pValuesSv,method="BH")
    
    # Save SVA and p-value results
    results_df <- data.frame(
      Feature = rownames(edata),
      pValues_unadjusted = pValues,
      qValues_unadjusted = qValues,
      pValues_SVA_adjusted = pValuesSv,
      qValues_SVA_adjusted = qValuesSv,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "sva_pvalues_results.csv", row.names=FALSE)
    write.csv(svobj\$sv, "estimated_surrogate_variables.csv", row.names=FALSE)
    saveRDS(svobj, "sva_object.rds")
    
    # Plot surrogate variables
    pdf("surrogate_variables_plot.pdf")
    if (svobj\$n.sv >= 2) {
      plot(svobj\$sv[,1], svobj\$sv[,2], col="blue", pch=19,
           xlab="SV1", ylab="SV2", main="Surrogate Variables 1 vs 2")
    } else if (svobj\$n.sv == 1) {
      plot(svobj\$sv[,1], col="blue", pch=19,
           ylab="SV1", main="Surrogate Variable 1")
    } else {
      plot(1, type="n", axes=FALSE, xlab="", ylab="", main="No Surrogate Variables Estimated")
    }
    dev.off()
    
    # Perform differential expression using limma
    tryCatch({
      fit = lmFit(edata,modSv)
      # Dynamically identify the coefficients corresponding to the variable of interest
      coefs_to_test <- setdiff(colnames(mod), colnames(mod0))
      
      eb = eBayes(fit)
      # Test the identified coefficients (performs an F-test if >1 coefficient, or a t-test if 1)
      top_tab <- topTable(eb, coef=coefs_to_test, number=Inf, adjust.method="BH")
      write.csv(top_tab, "limma_contrasts_topTable.csv", row.names=TRUE)
    }, error = function(e) {
      message("Limma step skipped or failed: ", e\$message)
    })

    writeLines(c(
        '"BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_surrogate_variable_analysis.csv versions.yml
    """
}

workflow BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS.out.tables
    plots    = BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS.out.plots
    objects  = BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS.out.objects
    versions = BIOC_SVA_SURROGATE_VARIABLE_ANALYSIS.out.versions
}
