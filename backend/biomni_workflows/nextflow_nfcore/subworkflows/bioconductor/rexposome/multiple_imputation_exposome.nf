#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rexposome — multiple_imputation_exposome
// Load multiple imputed exposome data, explore imputed families, extract single imputed sets, and perform ExWAS.
// Input: description.csv, exposures.csv, phenotypes.csv
// Container: quay.io/biocontainers/bioconductor-rexposome:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mice, rexposome
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw data and perform multiple imputation using mice
//  * 2. [Core Analysis] Combine imputed datasets into a single data.frame
//  * 3. [Input & Preparation] Load the combined data into an imExposomeSet
//  * 4. [Visualization & Output] Visualize exposure behavior across imputations
//  * 5. [Core Analysis] Extract a single ExposomeSet or run ExWAS directly on the imputed set

nextflow.enable.dsl = 2

process BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("rexposome", "mice")
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
        library(rexposome)
        library(mice)
        
        # 1. Load raw data from the working directory
        description_file <- "description.csv"
        exposures_file <- "exposures.csv"
        phenotypes_file <- "phenotypes.csv"
        
        dd <- read.csv(description_file, header = TRUE, stringsAsFactors = FALSE)
        ee <- read.csv(exposures_file, header = TRUE)
        pp <- read.csv(phenotypes_file, header = TRUE)
        
        # 2. Filter exposures and prepare data for imputation
        desc_cols <- colnames(dd)
        exp_col <- if ("Exposure" %in% desc_cols) "Exposure" else desc_cols[1]
        fam_col <- if ("Family" %in% desc_cols) "Family" else desc_cols[2]
        
        id_col_ee <- colnames(ee)[1]
        id_col_pp <- colnames(pp)[1]
        
        ee <- ee[ , c(id_col_ee, dd[[exp_col]])]
        
        rownames(ee) <- ee[[id_col_ee]]
        rownames(pp) <- pp[[id_col_pp]]
        
        # Align phenotypes with exposures
        pp <- pp[rownames(ee), , drop = FALSE]
        
        dta <- cbind(ee[ , -1, drop = FALSE], pp[ , -1, drop = FALSE])
        
        # Remove columns with too many categories (e.g., dates) to prevent mice from failing
        exp_cols_list <- dd[[exp_col]]
        valid_cols <- sapply(colnames(dta), function(col) {
            if (col %in% exp_cols_list) return(TRUE)
            n_unique <- length(unique(na.omit(dta[[col]])))
            is_char <- is.character(dta[[col]]) || is.factor(dta[[col]])
            if (is_char && n_unique > 20) return(FALSE)
            return(TRUE)
        })
        dta <- dta[, valid_cols, drop = FALSE]
        
        # Convert columns to numeric or factor as documented
        for(col in colnames(dta)) {
            if(length(unique(na.omit(dta[[col]]))) < 5 || is.character(dta[[col]])) {
                dta[[col]] <- as.factor(dta[[col]])
            } else {
                dta[[col]] <- as.numeric(dta[[col]])
            }
        }
        
        # 3. Perform multiple imputation using mice
        imp <- mice(dta, pred = quickpred(dta, mincor = 0.2, minpuc = 0.4), seed = 38788, m = 5, maxit = 10, printFlag = FALSE)
        
        # 4. Combine imputed datasets into a single data.frame
        me <- complete(imp, action = 0)
        me[ , ".imp"] <- 0
        me[ , ".id"] <- rownames(me)
        for(set in 1:5) {
            im <- complete(imp, action = set)
            im[ , ".imp"] <- set
            im[ , ".id"] <- rownames(im)
            me <- rbind(me, im)
        }
        me <- me[ , c(".imp", ".id", setdiff(colnames(me), c(".imp", ".id")))]
        rownames(me) <- 1:nrow(me)
        
        # 5. Load the combined data into an imExposomeSet
        ex_imp <- loadImputed(data = me, description = dd, description.famCol = fam_col, description.expCol = exp_col)
        
        # Save the imExposomeSet object
        saveRDS(ex_imp, "im_exposome_set.rds")
        
        # 6. Visualize exposure behavior across imputations and ExWAS
        pdf("exposome_imputation_plots.pdf", width = 10, height = 8)
        
        # Plot family behavior
        fam_name <- familyNames(ex_imp)[1]
        print(plotFamily(ex_imp, family = fam_name))
        
        # 7. Extract a single ExposomeSet
        ex_1 <- toES(ex_imp, rid = 1)
        saveRDS(ex_1, "exposome_set_rid1.rds")
        
        # 8. Perform ExWAS directly on the imputed set
        pheno_names <- phenotypeNames(ex_imp)
        
        is_num_outcome <- sapply(pheno_names, function(x) {
            is.numeric(pData(ex_imp)[[x]]) && length(unique(na.omit(pData(ex_imp)[[x]]))) >= 5
        })
        is_bin_outcome <- sapply(pheno_names, function(x) {
            length(unique(na.omit(pData(ex_imp)[[x]]))) == 2
        })
        
        if (any(is_num_outcome)) {
            outcome <- pheno_names[is_num_outcome][1]
            fam <- "gaussian"
        } else if (any(is_bin_outcome)) {
            outcome <- pheno_names[is_bin_outcome][1]
            fam <- "binomial"
        } else {
            outcome <- pheno_names[1]
            fam <- "gaussian"
        }
        
        valid_phenos <- Filter(function(x) {
            col_data <- pData(ex_imp)[[x]]
            is.numeric(col_data) || length(unique(na.omit(col_data))) < 10
        }, pheno_names)
        
        covariates <- setdiff(valid_phenos, outcome)
        if(length(covariates) > 2) covariates <- covariates[1:2]
        
        outcome_safe <- paste0("`", outcome, "`")
        if (length(covariates) > 0) {
            covariates_safe <- paste0("`", covariates, "`")
            form_str <- paste(outcome_safe, "~", paste(covariates_safe, collapse = " + "))
        } else {
            form_str <- paste(outcome_safe, "~ 1")
        }
        form <- as.formula(form_str)
        
        as_iew <- exwas(ex_imp, formula = form, family = fam)
        saveRDS(as_iew, "exwas_object.rds")
        
        # Plot ExWAS results
        clr <- rainbow(length(familyNames(ex_imp)))
        names(clr) <- familyNames(ex_imp)
        print(plotExwas(as_iew, color = clr))
        
        dev.off()
        
        # 9. Extract threshold and significant results
        thr <- tef(as_iew)
        tbl <- extract(as_iew)
        sig <- tbl[tbl\$pvalue <= thr, ]
        
        # Save tabular results
        write.csv(tbl, "exwas_results_all.csv", row.names = TRUE)
        write.csv(as.data.frame(sig), "exwas_results_significant.csv", row.names = TRUE)
        write(thr, "threshold_effective_tests.txt")

    writeLines(c(
        '"BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME":',
        paste0('    rexposome: ', as.character(packageVersion('rexposome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_imputation_exposome.csv versions.yml
    """
}

workflow BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ description.csv, exposures.csv, phenotypes.csv ] ]

    main:
    BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME(ch_input)

    emit:
    tables   = BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME.out.tables
    plots    = BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME.out.plots
    objects  = BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME.out.objects
    versions = BIOC_REXPOSOME_MULTIPLE_IMPUTATION_EXPOSOME.out.versions
}
