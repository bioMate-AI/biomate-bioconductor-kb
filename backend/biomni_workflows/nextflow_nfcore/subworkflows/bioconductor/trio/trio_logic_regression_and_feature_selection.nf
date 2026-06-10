#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trio — trio_logic_regression_and_feature_selection
// Identify higher-order SNP interactions associated with disease risk using trio logic regression and bagging-based feature selection.
// Input: pedigree_data.ped, haplotype_frequencies.txt
// Container: quay.io/biocontainers/bioconductor-trio:3.48.0--r45hdfd78af_0
// R packages: trio
// Bioconductor: 3.20 | R: 4.4
// Requires: trio
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check for Mendelian errors and format data using trio.check, optionally replacing errors with NA
//  * 2. [Input & Preparation] Prepare binary data and impute missing genotypes using trio.prepare
//  * 3. [Input & Preparation] Set up logic regression control parameters using lrControl
//  * 4. [Core Analysis] Fit trio logic regression models using trioLR with simulated annealing, greedy, or MCMC search
//  * 5. [Core Analysis] Run feature selection using trioFS to identify and rank important interactions

nextflow.enable.dsl = 2

process BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION {
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
    .bm_deps <- c("trio")
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
        
        # Load the required Bioconductor package
        library(trio)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read the pedigree data file from the working directory
        ped_data <- read.pedfile("pedigree_data.ped")
        
        # Read the optional pre-estimated haplotype frequencies if available
        if (file.exists("haplotype_frequencies.txt")) {
          freq.hap <- read.table("haplotype_frequencies.txt", header = TRUE, stringsAsFactors = FALSE)
        } else {
          freq.hap <- NULL
        }
        
        # ==========================================
        # 2. Check and Prepare Data
        # ==========================================
        
        # Check for Mendelian errors and format data
        trio.tmp <- trio.check(dat=ped_data)
        
        # Prepare binary data and impute missing genotypes
        set.seed(123456)
        trio.bin <- trio.prepare(trio.dat=trio.tmp)
        
        # Check for Mendelian errors and replace them with NA
        trio.rep <- trio.check(dat=ped_data, replace=TRUE)
        
        # Prepare completed genotype data in original format (logic = FALSE)
        trio.imp3 <- trio.prepare(trio.dat=trio.tmp, freq=freq.hap, logic=FALSE)
        
        # ==========================================
        # 3. Logic Regression Control Parameters
        # ==========================================
        
        # Set up logic regression control parameters
        my.control <- lrControl(start=1, end=-3, iter=1000, output=-4)
        
        # ==========================================
        # 4. Fit Trio Logic Regression Models
        # ==========================================
        
        # Fit standard trio logic regression model
        lr.out <- trioLR(trio.bin, control=my.control, rand=9876543)
        
        # Print DNF representation of the model
        print(lr.out, asDNF=TRUE)
        
        # Fit model with specified number of leaves
        lr.out3 <- trioLR(trio.bin, nleaves=c(3,5), control=my.control, rand=9876543)
        
        # Fit model using greedy search
        lr.out4 <- trioLR(trio.bin, search="greedy", rand=9876543)
        
        # Fit model using MCMC search
        lr.out5 <- trioLR(trio.bin, search="mcmc", control=my.control, rand=9876543)
        
        # ==========================================
        # 5. Feature Selection using trioFS
        # ==========================================
        
        # Run feature selection to identify and rank important interactions
        fs.out <- trioFS(trio.bin, B=5, control=my.control, rand=1234)
        
        # ==========================================
        # 6. Save Outputs and Results
        # ==========================================
        
        # Save RDS objects of the key outputs
        saveRDS(trio.tmp, "trio_checked_temp.rds")
        saveRDS(trio.bin, "trio_binary_prepared.rds")
        saveRDS(trio.rep, "trio_checked_replaced.rds")
        saveRDS(trio.imp3, "trio_imputed_original_format.rds")
        saveRDS(lr.out, "trio_lr_model_standard.rds")
        saveRDS(lr.out3, "trio_lr_model_leaves.rds")
        saveRDS(lr.out4, "trio_lr_model_greedy.rds")
        saveRDS(lr.out5, "trio_lr_model_mcmc.rds")
        saveRDS(fs.out, "trio_fs_results.rds")
        
        # Capture printed DNF representation to a text file
        sink("trio_lr_dnf_representation.txt")
        print(lr.out, asDNF=TRUE)
        sink()
        
        # Generate diagnostic and model plots
        pdf("trio_logic_regression_plots.pdf")
        tryCatch({
          plot(lr.out)
        }, error = function(e) {
          message("Plotting lr.out failed: ", e\$message)
        })
        tryCatch({
          plot(fs.out)
        }, error = function(e) {
          message("Plotting fs.out failed: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION":',
        paste0('    trio: ', as.character(packageVersion('trio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trio_logic_regression_and_feature_selection.csv versions.yml
    """
}

workflow BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pedigree_data.ped, haplotype_frequencies.txt ] ]

    main:
    BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION(ch_input)

    emit:
    tables   = BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION.out.tables
    plots    = BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION.out.plots
    objects  = BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION.out.objects
    versions = BIOC_TRIO_TRIO_LOGIC_REGRESSION_AND_FEATURE_SELECTION.out.versions
}
