#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missRows — mi_mfa_analysis_and_visualization
// Perform multiple imputation multiple factor analysis (MI-MFA) on multi-omics datasets with missing rows, inspect missingness, and visualize the results.
// Input: table1.csv, table2.csv, cell_line_strata.csv
// Container: quay.io/biocontainers/bioconductor-missrows:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, missRows
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Prepare the MIDTList Object (Documented Code)
//  * 3. [Visualization & Output] Perform MI-MFA (Documented Code)
//  * 4. [Visualization & Output] Extract Configurations and Metadata (Documented Code)
//  * 5. [Visualization & Output] Inspect Missingness Pattern (Documented Code)
//  * 6. [Visualization & Output] Plot Individuals and Visualize Uncertainty (Documented
//  * 7. [Visualization & Output] Plot Variables (Documented Code)

nextflow.enable.dsl = 2

process BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION {
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
    .bm_deps <- c("missRows", "MultiAssayExperiment", "SummarizedExperiment")
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
    library(missRows)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    # The pipeline reads exactly these files from the working directory:
    # - table1.csv (transcriptomic expression matrix with missing rows)
    # - table2.csv (proteomic expression matrix with missing rows)
    # - cell_line_strata.csv (data frame containing the stratum/cancer type for each individual)
    
    table1 <- read.csv("table1.csv", row.names = 1, check.names = FALSE)
    table2 <- read.csv("table2.csv", row.names = 1, check.names = FALSE)
    cell.line <- read.csv("cell_line_strata.csv", row.names = 1, check.names = FALSE)
    
    # Construct a list structure mimicking NCI60 to support the exact documented code
    NCI60 <- list()
    NCI60\$dataTables <- list(
      trans = table1,
      prote = table2,
      cell.line = cell.line
    )
    
    # Construct MultiAssayExperiment for the MAE constructor test.
    # MultiAssayExperiment expects features x samples, so we transpose the tables.
    mae_obj <- MultiAssayExperiment(
      experiments = ExperimentList(
        trans = as.matrix(t(table1)),
        prote = as.matrix(t(table2))
      ),
      colData = cell.line
    )
    NCI60\$mae <- mae_obj
    
    # ==========================================
    # --- Prepare the MIDTList Object (Documented Code) ---
    # ==========================================
    tableList <- NCI60\$dataTables[1:2]
    cell.line <- NCI60\$dataTables\$cell.line
    
    midt <- MIDTList(tableList, colData=cell.line, 
                        assayNames=c("trans", "prote"))
    
    # ==========================================
    # --- Perform MI-MFA (Documented Code) ---
    # ==========================================
    set.seed(123)
    # Dynamically determine ncomp to avoid failing on small datasets, capped at 50
    ncomp_val <- min(50, nrow(table1) - 1, ncol(table1) - 1, nrow(table2) - 1, ncol(table2) - 1)
    ncomp_val <- max(2, ncomp_val)
    
    midt <- MIMFA(midt, ncomp=ncomp_val, M=30, estimeNC=TRUE)
    
    # Save the final MIDTList object
    saveRDS(midt, "midt_mfa_results.rds")
    
    # ==========================================
    # --- Extract Configurations and Metadata (Documented Code) ---
    # ==========================================
    names(midt)
    
    cell.line <- colData(midt)
    
    conf <- configurations(midt, M=5)
    # Save configurations to CSV
    write.csv(conf, "configurations_M5.csv", row.names = TRUE)
    
    # ==========================================
    # --- Inspect Missingness Pattern (Documented Code) ---
    # ==========================================
    pdf("plot_missing_pattern.pdf")
    patt <- missPattern(midt, colMissing="grey70")
    print(patt)
    dev.off()
    
    # Save missingness pattern summary
    saveRDS(patt, "missing_pattern.rds")
    writeLines(capture.output(print(patt)), "missing_pattern_summary.txt")
    
    # ==========================================
    # --- Plot Individuals and Visualize Uncertainty (Documented ---
    # ==========================================
    pdf("plot_ind_missing_white.pdf")
    print(plotInd(midt, colMissing="white"))
    dev.off()
    
    pdf("plot_ind_ellipse.pdf")
    print(plotInd(midt, confAreas="ellipse", confLevel=0.95))
    dev.off()
    
    pdf("plot_ind_convexhull.pdf")
    print(plotInd(midt, confAreas="convex.hull"))
    dev.off()
    
    # ==========================================
    # --- Plot Variables (Documented Code) ---
    # ==========================================
    pdf("plot_var_rad0.5.pdf")
    print(plotVar(midt, radIn=0.5))
    dev.off()
    
    pdf("plot_var_cutoff.pdf")
    print(plotVar(midt, radIn=0.55, varNames=TRUE, cutoff=0.55))
    dev.off()

    writeLines(c(
        '"BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION":',
        paste0('    missRows: ', as.character(packageVersion('missRows')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mi_mfa_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ table1.csv, table2.csv, cell_line_strata.csv ] ]

    main:
    BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_MISSROWS_MI_MFA_ANALYSIS_AND_VISUALIZATION.out.versions
}
