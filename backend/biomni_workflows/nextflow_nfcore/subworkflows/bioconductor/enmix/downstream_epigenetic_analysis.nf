#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: enmix — downstream_epigenetic_analysis
// Estimate cell type proportions, predict sex, calculate methylation age/scores, and identify differentially methylated regions (DMRs).
// Input: beta, rgSet, mdat, pheno, dat
// Container: quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0
// R packages: ENmix
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-enmix:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ENmix")
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
    library(ENmix)
    
    # Helper function to load user input files from the working directory
    load_input <- function(name) {
      rds_path <- paste0(name, ".rds")
      csv_path <- paste0(name, ".csv")
      tsv_path <- paste0(name, ".tsv")
      txt_path <- paste0(name, ".txt")
      
      if (file.exists(rds_path)) {
        message("Loading ", name, " from RDS...")
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        message("Loading ", name, " from CSV...")
        if (name == "beta") {
          df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
          return(as.matrix(df))
        } else {
          return(read.csv(csv_path, check.names = FALSE))
        }
      } else if (file.exists(tsv_path)) {
        message("Loading ", name, " from TSV...")
        if (name == "beta") {
          df <- read.delim(tsv_path, row.names = 1, check.names = FALSE)
          return(as.matrix(df))
        } else {
          return(read.delim(tsv_path, check.names = FALSE))
        }
      } else if (file.exists(txt_path)) {
        message("Loading ", name, " from TXT...")
        if (name == "beta") {
          df <- read.table(txt_path, row.names = 1, header = TRUE, check.names = FALSE)
          return(as.matrix(df))
        } else {
          return(read.table(txt_path, header = TRUE, check.names = FALSE))
        }
      } else {
        stop(paste("Required input file not found for:", name))
      }
    }
    
    # Load all user inputs
    beta <- load_input("beta")
    rgSet <- load_input("rgSet")
    mdat <- load_input("mdat")
    pheno <- load_input("pheno")
    dat <- load_input("dat")
    
    # Ensure pheno has the required columns for methscore and matches beta colnames
    if (!"SampleID" %in% colnames(pheno)) {
      if (nrow(pheno) == ncol(beta)) {
        pheno\$SampleID <- colnames(beta)
      } else {
        matching_col <- sapply(pheno, function(col) any(col %in% colnames(beta)))
        if (any(matching_col)) {
          col_name <- names(matching_col)[which(matching_col)[1]]
          pheno\$SampleID <- pheno[[col_name]]
        } else {
          pheno\$SampleID <- colnames(beta)[1:min(nrow(pheno), ncol(beta))]
        }
      }
    }
    if (!"Age" %in% colnames(pheno)) {
      age_col <- grep("age", colnames(pheno), ignore.case = TRUE, value = TRUE)
      if (length(age_col) > 0) {
        pheno\$Age <- pheno[[age_col[1]]]
      } else {
        pheno\$Age <- rep(40, nrow(pheno))
      }
    }
    if (!"Female" %in% colnames(pheno)) {
      sex_col <- grep("sex|gender|female", colnames(pheno), ignore.case = TRUE, value = TRUE)
      if (length(sex_col) > 0) {
        pheno\$Female <- ifelse(tolower(as.character(pheno[[sex_col[1]]])) %in% c("f", "female", "1"), 1, 0)
      } else {
        pheno\$Female <- rep(1, nrow(pheno))
      }
    }
    
    # 1. Estimate cell type proportions
    message("Estimating cell type proportions...")
    celltype=estimateCellProp(userdata=beta,
             refdata="FlowSorted.Blood.450k",
             nonnegative = TRUE,normalize=TRUE)
    
    # Save cell type proportions
    write.csv(as.data.frame(celltype), "cell_type_proportions.csv", row.names = TRUE)
    
    # 2. Predict sample sex
    message("Predicting sample sex...")
    sex=predSex(rgSet)
    write.csv(as.data.frame(sex), "predicted_sex_rgSet.csv", row.names = TRUE)
    
    sex=predSex(mdat)
    write.csv(as.data.frame(sex), "predicted_sex_mdat.csv", row.names = TRUE)
    
    # 3. Calculate methylation age and predictors
    message("Calculating methylation scores and age...")
    mscore=methscore(datMeth=beta,datPheno=pheno)
    
    # Save methylation scores
    if (is.list(mscore) || is.data.frame(mscore) || is.matrix(mscore)) {
      saveRDS(mscore, "methylation_scores.rds")
      if (is.data.frame(mscore) || is.matrix(mscore)) {
        write.csv(as.data.frame(mscore), "methylation_scores.csv", row.names = TRUE)
      } else if (is.list(mscore)) {
        for (n in names(mscore)) {
          tryCatch({
            write.csv(as.data.frame(mscore[[n]]), paste0("methylation_scores_", n, ".csv"), row.names = TRUE)
          }, error = function(e) NULL)
        }
      }
    }
    
    # 4. Identify differentially methylated regions (DMRs)
    message("Running ipDMR...")
    ipdmr_res <- ipdmr(data=dat,seed=0.1)
    if (!is.null(ipdmr_res)) {
      saveRDS(ipdmr_res, "ipdmr_results.rds")
      tryCatch({
        write.csv(as.data.frame(ipdmr_res), "ipdmr_results.csv", row.names = FALSE)
      }, error = function(e) NULL)
    }
    
    message("Running comb-p...")
    combp_res <- combp(data=dat,seed=0.1)
    if (!is.null(combp_res)) {
      saveRDS(combp_res, "combp_results.rds")
      tryCatch({
        write.csv(as.data.frame(combp_res), "combp_results.csv", row.names = FALSE)
      }, error = function(e) NULL)
    }
    
    message("Workflow completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS":
        enmix: \$(Rscript -e 'cat(as.character(packageVersion("enmix")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_downstream_epigenetic_analysis.csv versions.yml
    """
}

workflow BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta, rgSet, mdat, pheno, dat ] ]

    main:
    BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS.out.tables
    plots    = BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS.out.plots
    objects  = BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS.out.objects
    versions = BIOC_ENMIX_DOWNSTREAM_EPIGENETIC_ANALYSIS.out.versions
}
