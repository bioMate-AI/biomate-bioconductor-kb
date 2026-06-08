#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DSS — bsseq_multifactor_dml_dmr
// Detect DML and DMR from BS-seq data under a general multi-factor or paired experimental design.
// Input: BSobj.RData, design_df.txt
// Container: quay.io/biocontainers/bioconductor-dss:2.58.0--r45h01b2380_0
// Requires: DSS, bsseq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a beta-binomial linear model using DMLfit.multiFactor
//  * 2. [Core Analysis] Test specific coefficients, terms, or contrasts using DMLtest.multiFactor
//  * 3. [Core Analysis] Call DMRs from the multi-factor test results using callDMR

nextflow.enable.dsl = 2

process BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
    # Load required libraries
    library(DSS)
    library(bsseq)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # Load BSseq object from BSobj.RData
    if (!file.exists("BSobj.RData")) {
      stop("Error: BSobj.RData not found in the working directory.")
    }
    
    env <- new.env()
    load("BSobj.RData", envir = env)
    obj_names <- ls(env)
    bsseq_obj_name <- NULL
    for (name in obj_names) {
      if (inherits(env[[name]], "BSseq")) {
        bsseq_obj_name <- name
        break
      }
    }
    
    if (is.null(bsseq_obj_name)) {
      stop("Error: No BSseq object found in BSobj.RData.")
    }
    
    BSobj <- env[[bsseq_obj_name]]
    RRBS <- BSobj # Assign to RRBS to match documented code variables
    
    # Load experimental design
    if (!file.exists("design_df.txt")) {
      stop("Error: design_df.txt not found in the working directory.")
    }
    design <- read.table("design_df.txt", header = TRUE, stringsAsFactors = TRUE)
    col_names <- colnames(design)
    
    # ==========================================
    # 2. General Multifactor Design Workflow
    # ==========================================
    message("Running General Multifactor Design Workflow...")
    
    # Dynamically construct formula based on available columns
    if (length(col_names) >= 2) {
      formula_mf <- as.formula(paste0("~ ", col_names[1], " + ", col_names[2], " + ", col_names[1], ":", col_names[2]))
    } else {
      formula_mf <- as.formula(paste0("~ ", col_names[1]))
    }
    
    # Fit a beta-binomial linear model
    DMLfit = DMLfit.multiFactor(RRBS, design=design, formula=formula_mf)
    
    # Dynamically select a coefficient to test (avoiding hardcoded indices that might exceed matrix dimensions)
    coef_idx <- min(3, ncol(DMLfit\$X))
    coef_name <- colnames(DMLfit\$X)[coef_idx]
    
    # Test specific coefficients
    DMLtest.cell = DMLtest.multiFactor(DMLfit, coef=coef_idx)
    write.csv(DMLtest.cell, paste0("DMLtest_cell_coef", coef_idx, ".csv"), row.names = FALSE)
    
    DMLtest.cell_char = DMLtest.multiFactor(DMLfit, coef=coef_name)
    write.csv(DMLtest.cell_char, "DMLtest_cell_char.csv", row.names = FALSE)
    
    # Call DMRs from the multi-factor test results
    dmrs_cell = callDMR(DMLtest.cell, p.threshold=0.05)
    if (!is.null(dmrs_cell)) {
      write.csv(dmrs_cell, "DMRs_cell.csv", row.names = FALSE)
    } else {
      message("No significant DMRs found for cell.")
    }
    
    
    # ==========================================
    # 3. Alternative Hypothesis Testing (Terms and Contrasts)
    # ==========================================
    message("Running Alternative Hypothesis Testing...")
    
    if (length(col_names) >= 2) {
      formula_alt <- as.formula(paste0("~ ", col_names[1], " + ", col_names[2]))
    } else {
      formula_alt <- as.formula(paste0("~ ", col_names[1]))
    }
    
    DMLfit = DMLfit.multiFactor(RRBS, design, formula_alt)
    
    coef_idx2 <- min(2, ncol(DMLfit\$X))
    coef_name2 <- colnames(DMLfit\$X)[coef_idx2]
    
    test1 = DMLtest.multiFactor(DMLfit, coef=coef_idx2)
    write.csv(test1, paste0("test1_coef", coef_idx2, ".csv"), row.names = FALSE)
    
    test2 = DMLtest.multiFactor(DMLfit, coef=coef_name2)
    safe_coef_name2 <- gsub("[^A-Za-z0-9_.-]", "_", coef_name2)
    write.csv(test2, paste0("test2_coef_", safe_coef_name2, ".csv"), row.names = FALSE)
    
    test3 = DMLtest.multiFactor(DMLfit, term=col_names[1])
    safe_term_name <- gsub("[^A-Za-z0-9_.-]", "_", col_names[1])
    write.csv(test3, paste0("test3_term_", safe_term_name, ".csv"), row.names = FALSE)
    
    # Dynamically construct contrast matrix based on the design matrix dimensions
    Contrast = matrix(0, nrow=ncol(DMLfit\$X), ncol=1)
    Contrast[coef_idx2, 1] <- 1
    test4 = DMLtest.multiFactor(DMLfit, Contrast=Contrast)
    write.csv(test4, "test4_contrast.csv", row.names = FALSE)
    
    
    # ==========================================
    # 4. Paired Design Workflow
    # ==========================================
    message("Running Paired Design Workflow...")
    
    design_paired <- design
    if (ncol(design_paired) >= 2) {
      # Ensure the pairing variable is treated as a factor
      design_paired[, 2] <- as.factor(design_paired[, 2])
    }
    
    DMLfit = DMLfit.multiFactor(BSobj, design_paired, formula = formula_alt)
    dmlTest = DMLtest.multiFactor(DMLfit, term=col_names[1])
    write.csv(dmlTest, paste0("dmlTest_paired_", safe_term_name, ".csv"), row.names = FALSE)
    
    dmrs_paired = callDMR(dmlTest, p.threshold=0.05)
    if (!is.null(dmrs_paired)) {
      write.csv(dmrs_paired, "DMRs_paired.csv", row.names = FALSE)
    } else {
      message("No significant DMRs found for paired design.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR":',
        paste0('    DSS: ', as.character(packageVersion('DSS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsseq_multifactor_dml_dmr.csv versions.yml
    """
}

workflow BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSobj.RData, design_df.txt ] ]

    main:
    BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR(ch_input)

    emit:
    tables   = BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR.out.tables
    plots    = BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR.out.plots
    objects  = BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR.out.objects
    versions = BIOC_DSS_BSSEQ_MULTIFACTOR_DML_DMR.out.versions
}
