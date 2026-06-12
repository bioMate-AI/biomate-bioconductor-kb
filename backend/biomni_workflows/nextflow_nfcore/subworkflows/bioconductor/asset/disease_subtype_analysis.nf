#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASSET — disease_subtype_analysis
// Analyze association of SNPs with distinct disease subtypes using individual-level case-control data.
// Input: vdata.rda
// Container: quay.io/biocontainers/bioconductor-asset:2.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ASSET
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Combine individual study data frames into a single data frame
//  * 2. [Input & Preparation] Create study indicator dummy variables for covariate adjustment
//  * 3. [Input & Preparation] Define SNP variables, adjustment variables, and disease subtype labels
//  * 4. [Core Analysis] Run subtype analysis using h.types with logit=TRUE
//  * 5. [Visualization & Output] Summarize results using h.summary

nextflow.enable.dsl = 2

process BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("ASSET")
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
    library(ASSET)
    
    # 1. Load individual-level data frames from the user-provided vdata.rda
    load("vdata.rda")
    
    # Determine the number of studies dynamically from the loaded data objects (e.g., data1, data2, ...)
    data_objs <- ls(pattern = "^data[0-9]+\$")
    nStudy <- length(data_objs)
    
    # Combine individual study data frames into a single data frame
    data <- NULL
    for (i in 1:nStudy) {
      temp <- eval(parse(text=paste("data", i, sep="")))
      temp[, "STUDY"]  <- i
      data <- rbind(data, temp)
    }
    
    # 2. Create study indicator dummy variables for covariate adjustment
    for (i in 1:nStudy) {
      dvar <- paste("STUDY_", i, sep="")
      data[, dvar] <- as.numeric(data[, "STUDY"] %in% i)
    }
    
    # 3. Define SNP variables, adjustment variables, and disease subtype labels
    snp.vars <- grep("^SNP", colnames(data), value = TRUE)
    adj.vars <- "AGE"
    if (nStudy > 1) {
      adj.vars <- c(adj.vars, paste("STUDY_", 1:(nStudy - 1), sep=""))
    }
    types.lab <- sort(setdiff(as.character(unique(data\$TYPE)), c("CONTROL", NA)))
    
    # 4. Run subtype analysis using h.types with logit=TRUE
    ret <- h.types(data, "TYPE", snp.vars, adj.vars, types.lab, "CONTROL",
                   logit=TRUE)
    
    # 5. Summarize results using h.summary
    sum_ret <- h.summary(ret)
    
    # Print summary to console
    print(sum_ret)
    
    # Save the complete summary object as an RDS file
    saveRDS(sum_ret, "asset_subtype_summary.rds")
    
    # Write individual result tables to CSV files
    if (!is.null(sum_ret\$Overall.Logistic)) {
      write.csv(sum_ret\$Overall.Logistic, "overall_logistic_results.csv", row.names = FALSE)
    }
    if (!is.null(sum_ret\$Subset.Case.Control)) {
      write.csv(sum_ret\$Subset.Case.Control, "subset_case_control_results.csv", row.names = FALSE)
    }
    if (!is.null(sum_ret\$Subset.Case.Complement)) {
      write.csv(sum_ret\$Subset.Case.Complement, "subset_case_complement_results.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS":',
        paste0('    ASSET: ', as.character(packageVersion('ASSET')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_disease_subtype_analysis.csv versions.yml
    """
}

workflow BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vdata.rda ] ]

    main:
    BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS.out.tables
    plots    = BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS.out.plots
    objects  = BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS.out.objects
    versions = BIOC_ASSET_DISEASE_SUBTYPE_ANALYSIS.out.versions
}
