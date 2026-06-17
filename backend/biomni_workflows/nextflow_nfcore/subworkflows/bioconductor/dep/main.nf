#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEP — differential_protein_expression
// Identify differentially expressed proteins from mass spectrometry intensity data using a robust filtering, normalization, imputation, and linear modeling workfl
// Input: proteinGroups.txt, experimental_design.txt
// Container: quay.io/biocontainers/bioconductor-dep:1.32.0--r45hdfd78af_0
// R packages: BiocStyle, DEP, dplyr, ggplot2, purrr, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: DEP, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate unique names for proteins using make_unique
//  * 2. [Visualization & Output] Create a SummarizedExperiment object using make_se
//  * 3. [Core Analysis] Filter out proteins with too many missing values using filter_missval
//  * 4. [Core Analysis] Normalize the data using normalize_vsn
//  * 5. [Core Analysis] Impute missing values using impute
//  * 6. [Core Analysis] Test for differential expression using test_diff
//  * 7. [Input & Preparation] Define significant proteins using add_rejections
//  * 8. [Core Analysis] Extract results table using get_results

nextflow.enable.dsl = 2

process BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION {
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
    .bm_deps <- c("BiocStyle", "DEP", "dplyr", "ggplot2", "purrr", "SummarizedExperiment")
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
        library(DEP)
        
        # Define input file paths
        protein_groups_file <- "proteinGroups.txt"
        experimental_design_file <- "experimental_design.txt"
        
        # Check if input files exist
        if (!file.exists(protein_groups_file)) {
          stop(paste("Error: Input file missing:", protein_groups_file))
        }
        if (!file.exists(experimental_design_file)) {
          stop(paste("Error: Input file missing:", experimental_design_file))
        }
        
        # Read input files
        proteins_tbl <- read.delim(protein_groups_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        experimental_design <- read.delim(experimental_design_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        
        # 1. Generate unique names for proteins
        data_unique <- make_unique(proteins_tbl, "Gene.names", "Protein.IDs", delim = ";")
        
        # Identify the column indices in data_unique that correspond to the labels in experimental_design
        columns <- match(experimental_design\$label, colnames(data_unique))
        if (any(is.na(columns))) {
          stop("Error: Some sample labels in experimental_design do not match column names in proteinGroups.txt")
        }
        
        # 2. Create a SummarizedExperiment object
        se <- make_se(data_unique, columns, experimental_design)
        
        # 3. Filter out proteins with too many missing values
        filt <- filter_missval(se, thr = 0)
        
        # 4. Normalize the data
        norm <- normalize_vsn(filt)
        
        # 5. Impute missing values
        imputed <- impute(norm, fun = "MinProb")
        
        # 6. Test for differential expression
        diff <- test_diff(imputed, type = "all")
        
        # 7. Define significant proteins
        dep <- add_rejections(diff, alpha = 0.05, lfc = 1)
        
        # 8. Extract results table
        results <- get_results(dep)
        
        # Write output files
        write.csv(results, "dep_results.csv", row.names = FALSE)
        saveRDS(dep, "dep_object.rds")
        
        # Generate diagnostic and results plots
        pdf("dep_plots.pdf", width = 10, height = 8)
        tryCatch({
          plot_pca(dep, x = 1, y = 2, n = 100, point_size = 4)
        }, error = function(e) {
          warning("Could not generate PCA plot: ", e\$message)
        })
        
        tryCatch({
          plot_cor(dep, significant = TRUE, lower = 0, upper = 1)
        }, error = function(e) {
          warning("Could not generate correlation plot: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION":',
        paste0('    DEP: ', as.character(packageVersion('DEP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_protein_expression.csv versions.yml
    """
}

workflow BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt, experimental_design.txt ] ]

    main:
    BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.tables
    plots    = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.plots
    objects  = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.objects
    versions = BIOC_DEP_DIFFERENTIAL_PROTEIN_EXPRESSION.out.versions
}
