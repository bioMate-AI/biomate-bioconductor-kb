#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DExMA — batch_effect_correction
// Detect and remove batch effects from individual datasets and calculate individual study effect sizes or p-values.
// Input: listMatrixEX, listPhenodatas
// Container: quay.io/biocontainers/bioconductor-dexma:1.18.0--r45hdfd78af_0
// R packages: Biobase, DExMA, swamp
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, DExMA, swamp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Detect batch effects using principal components
//  * 2. [Core Analysis] Remove batch effects
//  * 3. [Core Analysis] Calculate individual study effect sizes
//  * 4. [Core Analysis] Calculate individual study p-values

nextflow.enable.dsl = 2

process BIOC_DEXMA_BATCH_EFFECT_CORRECTION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "DExMA", "swamp")
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
        library(DExMA)
        library(swamp)
        library(Biobase)
        
        # ==========================================
        # STEP 0: Read User Input Files
        # ==========================================
        # The pipeline expects 'listMatrixEX.rds' and 'listPhenodatas.rds' in the working directory.
        if (!file.exists("listMatrixEX.rds") || !file.exists("listPhenodatas.rds")) {
          stop("Required input files 'listMatrixEX.rds' and/or 'listPhenodatas.rds' are missing from the working directory.")
        }
        
        listMatrixEX <- readRDS("listMatrixEX.rds")
        listPhenodatas <- readRDS("listPhenodatas.rds")
        
        # ==========================================
        # STEP 1: Detect Batch Effects Using Principal Components
        # ==========================================
        pdf("batch_effects_prince_plot.pdf", width = 8, height = 6)
        for (study_name in names(listMatrixEX)) {
          pheno <- listPhenodatas[[study_name]]
          
          # Filter to columns with >1 unique value for PCA detection
          pheno_filtered <- pheno[, apply(pheno, 2, function(x) length(table(x))) > 1, drop = FALSE]
          
          if (ncol(pheno_filtered) > 0) {
            pheno_factor <- data.frame(apply(pheno_filtered, 2, factor), stringsAsFactors = TRUE) 
            
            res_prince <- try(prince(listMatrixEX[[study_name]], pheno_factor, top = ncol(listMatrixEX[[study_name]])), silent = TRUE)
            if (!inherits(res_prince, "try-error")) {
              prince.plot(res_prince, note = TRUE, notecex = 0.5)
            }
          }
        }
        dev.off()
        
        # ==========================================
        # STEP 2: Remove Batch Effects
        # ==========================================
        for (study_name in names(listMatrixEX)) {
          pheno <- listPhenodatas[[study_name]]
          
          # Identify group column (preferring "condition", "state", "status", "group")
          col_idx <- which(colnames(pheno) %in% c("condition", "state", "status", "group"))
          if (length(col_idx) == 0) col_idx <- 1
          nameGroup <- colnames(pheno)[col_idx[1]]
          
          # Filter to columns with >1 unique value to find valid covariates
          valid_cols <- apply(pheno, 2, function(x) length(table(x)) > 1)
          pheno_filtered <- pheno[, valid_cols, drop = FALSE]
          
          # Covariates are any varying columns other than the main grouping variable
          covariates <- setdiff(colnames(pheno_filtered), nameGroup)
          
          if (length(covariates) > 0) {
            mainCov <- covariates[1]
            form <- as.formula(paste("~", paste(covariates, collapse = "+")))
            
            listMatrixEX[[study_name]] <- batchRemove(listMatrixEX[[study_name]], 
                                                      listPhenodatas[[study_name]], 
                                                      formula = form, 
                                                      mainCov = mainCov, 
                                                      nameGroup = nameGroup)
          }
        }
        
        # Save the corrected expression matrix list
        saveRDS(listMatrixEX, "listMatrixEX_batch_corrected.rds")
        
        # ==========================================
        # STEP 2.5: Create the Meta-Analysis Object (newObjectMA)
        # ==========================================
        # Dynamically infer comparison groups across all studies to build the objectMA
        infer_groups <- function(listPheno) {
          phenoGroups <- c()
          expGroups <- list()
          refGroups <- list()
          
          for (i in seq_along(listPheno)) {
            study_name <- names(listPheno)[i]
            df <- listPheno[[i]]
            
            # Identify group column (preferring "condition", "state", "status", "group")
            col_idx <- which(colnames(df) %in% c("condition", "state", "status", "group"))
            if (length(col_idx) == 0) col_idx <- 1
            col_name <- colnames(df)[col_idx[1]]
            phenoGroups <- c(phenoGroups, col_name)
            
            vals <- unique(as.character(df[[col_name]]))
            cases <- vals[grep("disease|ill|case|tumor|sick|diseased", vals, ignore.case = TRUE)]
            controls <- vals[grep("healthy|control|normal|ref", vals, ignore.case = TRUE)]
            
            if (length(cases) == 0) {
              cases <- vals[1]
              controls <- vals[2:length(vals)]
            }
            if (length(controls) == 0 || any(is.na(controls))) {
              controls <- setdiff(vals, cases)
            }
            
            expGroups[[study_name]] <- cases
            refGroups[[study_name]] <- controls
          }
          list(phenoGroups = phenoGroups, expGroups = expGroups, refGroups = refGroups)
        }
        
        inferred <- infer_groups(listPhenodatas)
        
        newObjectMA <- createObjectMA(listEX = listMatrixEX,
                                      listPheno = listPhenodatas,
                                      namePheno = inferred\$phenoGroups,
                                      expGroups = inferred\$expGroups, 
                                      refGroups = inferred\$refGroups)
        
        # Standardize gene annotations and log-transform expression values
        newObjectMA <- allSameID(newObjectMA, finalID = "GeneSymbol", organism = "Homo sapiens")
        newObjectMA <- dataLog(newObjectMA)
        
        # ==========================================
        # STEP 3: Calculate Individual Study Effect Sizes
        # ==========================================
        effects <- calculateES(newObjectMA)
        
        # Save effect size results
        saveRDS(effects, "individual_study_effects.rds")
        if (!is.null(effects\$ES)) {
          write.csv(effects\$ES, "effects_ES.csv", row.names = TRUE)
          write.csv(effects\$Var, "effects_Var.csv", row.names = TRUE)
          write.csv(effects\$logFC, "effects_logFC.csv", row.names = TRUE)
        }
        
        # ==========================================
        # STEP 4: Calculate Individual Study P-values
        # ==========================================
        pvalues <- pvalueIndAnalysis(newObjectMA)
        
        # Save individual p-value analysis results
        saveRDS(pvalues, "individual_study_pvalues.rds")
        if (!is.null(pvalues\$p)) {
          write.csv(pvalues\$p, "pvalues_p.csv", row.names = TRUE)
          write.csv(pvalues\$logFC, "pvalues_logFC.csv", row.names = TRUE)
        }
        
        # Save the final meta-analysis object
        saveRDS(newObjectMA, "newObjectMA_final.rds")
        
        cat("Pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_DEXMA_BATCH_EFFECT_CORRECTION":',
        paste0('    DExMA: ', as.character(packageVersion('DExMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_effect_correction.csv versions.yml
    """
}

workflow BIOC_DEXMA_BATCH_EFFECT_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ listMatrixEX, listPhenodatas ] ]

    main:
    BIOC_DEXMA_BATCH_EFFECT_CORRECTION(ch_input)

    emit:
    tables   = BIOC_DEXMA_BATCH_EFFECT_CORRECTION.out.tables
    plots    = BIOC_DEXMA_BATCH_EFFECT_CORRECTION.out.plots
    objects  = BIOC_DEXMA_BATCH_EFFECT_CORRECTION.out.objects
    versions = BIOC_DEXMA_BATCH_EFFECT_CORRECTION.out.versions
}
