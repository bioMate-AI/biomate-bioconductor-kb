#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — combat_known_batches
// Directly adjust for known batch effects in continuous high-throughput data (e.g., microarrays) using an empirical Bayesian framework.
// Input: expression_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sva
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the batch vector and model matrix for adjustment variables
//  * 2. [Core Analysis] Run ComBat to obtain a batch-adjusted expression matrix
//  * 3. [Core Analysis] Perform downstream differential expression analysis on the adjusted matrix

nextflow.enable.dsl = 2

process BIOC_SVA_COMBAT_KNOWN_BATCHES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        
        # Load required libraries
        library(sva)
        
        # Read user input files from the working directory
        edata <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
        pheno <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between expression matrix and phenotype data
        common_samples <- intersect(colnames(edata), rownames(pheno))
        if (length(common_samples) == 0) {
          stop("No matching samples found between expression_matrix.csv and phenotype_data.csv")
        }
        edata <- edata[, common_samples, drop = FALSE]
        pheno <- pheno[common_samples, , drop = FALSE]
        
        # Identify the variable of interest for downstream differential expression
        # We exclude 'batch' and look for the primary biological covariate
        covariates <- setdiff(colnames(pheno), "batch")
        if (length(covariates) > 0) {
          var_of_interest <- covariates[1]
          if (is.character(pheno[[var_of_interest]]) || is.factor(pheno[[var_of_interest]])) {
            mod = model.matrix(as.formula(paste0("~as.factor(", var_of_interest, ")")), data=pheno)
          } else {
            mod = model.matrix(as.formula(paste0("~", var_of_interest)), data=pheno)
          }
        } else {
          mod = model.matrix(~1, data=pheno)
        }
        mod0 = model.matrix(~1, data=pheno)
        
        # 1. Define the batch vector and model matrix for adjustment variables
        batch = pheno\$batch
        modcombat = mod
        
        # 2. Run ComBat to obtain a batch-adjusted expression matrix
        combat_edata = ComBat(dat=edata, batch=batch, mod=modcombat, par.prior=TRUE, prior.plots=FALSE)
        
        # 3. Perform downstream differential expression analysis on the adjusted matrix
        pValuesComBat = f.pvalue(combat_edata,mod,mod0)
        qValuesComBat = p.adjust(pValuesComBat,method="BH")
        
        # Write named output files for the meaningful results
        write.csv(combat_edata, "combat_adjusted_expression.csv", row.names = TRUE)
        
        results_df <- data.frame(
          Feature = rownames(combat_edata),
          p_value = pValuesComBat,
          q_value = qValuesComBat,
          stringsAsFactors = FALSE
        )
        write.csv(results_df, "differential_expression_results.csv", row.names = FALSE)
        saveRDS(combat_edata, "combat_adjusted_expression.rds")

    writeLines(c(
        '"BIOC_SVA_COMBAT_KNOWN_BATCHES":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combat_known_batches.csv versions.yml
    """
}

workflow BIOC_SVA_COMBAT_KNOWN_BATCHES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_SVA_COMBAT_KNOWN_BATCHES(ch_input)

    emit:
    tables   = BIOC_SVA_COMBAT_KNOWN_BATCHES.out.tables
    plots    = BIOC_SVA_COMBAT_KNOWN_BATCHES.out.plots
    objects  = BIOC_SVA_COMBAT_KNOWN_BATCHES.out.objects
    versions = BIOC_SVA_COMBAT_KNOWN_BATCHES.out.versions
}
