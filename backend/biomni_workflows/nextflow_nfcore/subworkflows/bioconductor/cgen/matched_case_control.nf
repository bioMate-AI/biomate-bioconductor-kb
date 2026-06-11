#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CGEN — matched_case_control
// Perform matched case-control analysis by creating matched sets and fitting conditional models.
// Input: Xdata
// Container: quay.io/biocontainers/bioconductor-cgen:3.46.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CGEN, cluster
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute a distance matrix using daisy
//  * 2. [Core Analysis] Generate matched sets using getMatchedSets
//  * 3. [Core Analysis] Append matched strata to the dataset
//  * 4. [Core Analysis] Fit matched models using snp.matched
//  * 5. [Visualization & Output] Summarize the CLR and CCL models using getSummary
//  * 6. [Core Analysis] Perform Wald tests on the HCL model using getWaldTest

nextflow.enable.dsl = 2

process BIOC_CGEN_MATCHED_CASE_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("CGEN", "cluster")
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
    library(CGEN)
    library(cluster)
    
    # 1. Read the user input file 'Xdata' from the working directory
    # Supports CSV, RDS, or TXT formats
    if (file.exists("Xdata.csv")) {
      Xdata <- read.csv("Xdata.csv", stringsAsFactors = FALSE)
    } else if (file.exists("Xdata.rds")) {
      Xdata <- readRDS("Xdata.rds")
    } else if (file.exists("Xdata.txt")) {
      Xdata <- read.table("Xdata.txt", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Error: Required input file 'Xdata' (Xdata.csv, Xdata.rds, or Xdata.txt) not found in the working directory.")
    }
    
    # Ensure dummy variables for age.group exist if they are not pre-computed in the input
    if (!"age.group_1" %in% colnames(Xdata) && "age.group" %in% colnames(Xdata)) {
      for (a in unique(Xdata[, "age.group"])) {
        dummyVar <- paste("age.group_", a, sep="")
        Xdata[, dummyVar] <- 0
        temp <- Xdata[, "age.group"] == a
        if (any(temp)) Xdata[temp, dummyVar] <- 1
      }
    }
    
    # 2. Compute a distance matrix using daisy
    size <- ifelse(Xdata\$ethnic.group == 3, 3, 4)
    d <- daisy(Xdata[,c("age.group_1","gynSurgery.history","BRCA.history")])
    
    # 3. Generate matched sets using getMatchedSets
    mx <- getMatchedSets(d, CC=TRUE, NN=TRUE, ccs.var = Xdata\$case.control, 
    	  strata.var = Xdata\$ethnic.group, size = size, fixed = TRUE)
    
    # 4. Append matched strata to the dataset
    Xdata <- cbind(Xdata, CCStrat = mx\$CC, NNStrat = mx\$NN)
    
    # Save the updated dataset with matched strata
    write.csv(Xdata, "Xdata_matched.csv", row.names = FALSE)
    
    # 5. Fit matched models using snp.matched
    intVars <- ~ oral.years + n.children
    snpVars <- ~ BRCA.status
    fit <- snp.matched(Xdata, "case.control", snp.vars=snpVars,
                         main.vars=intVars, int.vars=intVars, 
                         cc.var="CCStrat", nn.var="NNStrat") 
    
    # Save the fit object
    saveRDS(fit, "snp_matched_fit.rds")
    
    # 6. Summarize the CLR and CCL models using getSummary
    fit_summary <- getSummary(fit, method = c("CLR", "CCL"))
    saveRDS(fit_summary, "fit_summary.rds")
    
    if (!is.null(fit_summary\$CLR)) {
      write.csv(as.data.frame(fit_summary\$CLR), "summary_CLR.csv", row.names = TRUE)
    }
    if (!is.null(fit_summary\$CCL)) {
      write.csv(as.data.frame(fit_summary\$CCL), "summary_CCL.csv", row.names = TRUE)
    }
    
    # 7. Perform Wald tests on the HCL model using getWaldTest
    wald_test <- getWaldTest(fit\$HCL, c( "BRCA.status" , "BRCA.status:oral.years" , "BRCA.status:n.children"))
    saveRDS(wald_test, "wald_test.rds")
    
    # Write Wald test results to a text file
    sink("wald_test_results.txt")
    print(wald_test)
    sink()

    writeLines(c(
        '"BIOC_CGEN_MATCHED_CASE_CONTROL":',
        paste0('    CGEN: ', as.character(packageVersion('CGEN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matched_case_control.csv versions.yml
    """
}

workflow BIOC_CGEN_MATCHED_CASE_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Xdata ] ]

    main:
    BIOC_CGEN_MATCHED_CASE_CONTROL(ch_input)

    emit:
    tables   = BIOC_CGEN_MATCHED_CASE_CONTROL.out.tables
    plots    = BIOC_CGEN_MATCHED_CASE_CONTROL.out.plots
    objects  = BIOC_CGEN_MATCHED_CASE_CONTROL.out.objects
    versions = BIOC_CGEN_MATCHED_CASE_CONTROL.out.versions
}
