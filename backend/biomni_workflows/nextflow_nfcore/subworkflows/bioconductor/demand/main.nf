#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DeMAND — drug_moa_prediction
// Predict drug mechanism of action and target genes by analyzing network dysregulation between drug-treated and control expression profiles.
// Input: exp.ext, anno.ext, network.ext
// Container: quay.io/biocontainers/bioconductor-demand:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DeMAND
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a demand class object using demandClass()
//  * 2. [Core Analysis] Run the network dysregulation analysis using runDeMAND()
//  * 3. [Core Analysis] Print and inspect the predicted MoA genes and dysregulated edges using printDeMAND()

nextflow.enable.dsl = 2

process BIOC_DEMAND_DRUG_MOA_PREDICTION {
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
    .bm_deps <- c("DeMAND")
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
        library(DeMAND)
        
        # Helper function to locate and read input files with various extensions
        load_input_file <- function(base_name, is_exp = FALSE) {
          extensions <- c("ext", "csv", "tsv", "txt", "rds")
          found_file <- NULL
          
          for (ext in extensions) {
            test_path <- paste0(base_name, ".", ext)
            if (file.exists(test_path)) {
              found_file <- test_path
              break
            }
          }
          
          if (is.null(found_file)) {
            if (file.exists(base_name)) {
              found_file <- base_name
            } else {
              stop(paste("Error: Could not find input file for", base_name))
            }
          }
          
          message("Reading file: ", found_file)
          
          # Handle RDS files directly
          if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
            return(readRDS(found_file))
          }
          
          # Detect separator
          first_line <- readLines(found_file, n = 1)
          sep <- ""
          if (grepl("\t", first_line)) {
            sep <- "\t"
          } else if (grepl(",", first_line)) {
            sep <- ","
          } else if (grepl(";", first_line)) {
            sep <- ";"
          }
          
          if (is_exp) {
            # Expression matrix: expect row names (probes/genes) and column names (samples)
            df <- read.table(found_file, header = TRUE, sep = sep, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            return(as.matrix(df))
          } else {
            # Annotation or Network matrix
            df_no_header <- read.table(found_file, header = FALSE, sep = sep, stringsAsFactors = FALSE)
            first_row <- as.character(df_no_header[1, ])
            
            # Heuristic to detect header
            header_words <- c("gene", "probe", "symbol", "id", "interaction", "weight", "pvalue", "kld", "gene1", "gene2")
            has_header <- any(tolower(first_row) %in% header_words)
            
            if (has_header) {
              df <- read.table(found_file, header = TRUE, sep = sep, stringsAsFactors = FALSE)
            } else {
              df <- df_no_header
            }
            return(as.matrix(df))
          }
        }
        
        # 1. Load the user input files
        message("Loading input datasets...")
        exp_matrix <- load_input_file("exp", is_exp = TRUE)
        anno_matrix <- load_input_file("anno", is_exp = FALSE)
        network_matrix <- load_input_file("network", is_exp = FALSE)
        
        # Ensure correct data types and structures
        exp_matrix <- as.matrix(exp_matrix)
        mode(exp_matrix) <- "numeric"
        
        anno_matrix <- as.matrix(anno_matrix)
        mode(anno_matrix) <- "character"
        
        network_matrix <- as.matrix(network_matrix)
        mode(network_matrix) <- "character"
        
        # 2. Determine fgIndex (case/treated) and bgIndex (control)
        col_names <- colnames(exp_matrix)
        if (is.null(col_names)) {
          stop("Error: Expression matrix must have column names to identify samples.")
        }
        
        message("Sample columns found: ", paste(col_names, collapse = ", "))
        
        # Heuristic search for case and control indices
        fgIndex <- grep("case|treated|drug|fg|geldanamycin|treatment|stim|cond|tumor|disease", col_names, ignore.case = TRUE)
        bgIndex <- grep("control|untreated|bg|dmso|mock|ctrl|normal|ref|healthy", col_names, ignore.case = TRUE)
        
        # Fallback if heuristics fail to find at least 4 samples per group
        if (length(fgIndex) < 4 || length(bgIndex) < 4 || length(intersect(fgIndex, bgIndex)) > 0) {
          message("Could not automatically resolve fgIndex and bgIndex with >= 4 samples using column names.")
          message("Defaulting to splitting the samples: first half as control (bgIndex), second half as treated (fgIndex).")
          
          n_cols <- ncol(exp_matrix)
          if (n_cols < 8) {
            stop("Error: DeMAND requires at least 4 samples per group (minimum 8 samples total). Your expression matrix only has ", n_cols, " columns.")
          }
          half <- floor(n_cols / 2)
          bgIndex <- 1:half
          fgIndex <- (half + 1):n_cols
        }
        
        message("Using bgIndex (control): ", paste(bgIndex, collapse = ", "), " (Columns: ", paste(col_names[bgIndex], collapse = ", "), ")")
        message("Using fgIndex (case): ", paste(fgIndex, collapse = ", "), " (Columns: ", paste(col_names[fgIndex], collapse = ", "), ")")
        
        # 3. Create a demand class object using demandClass()
        message("Initializing DeMAND object...")
        dobj <- demandClass(exp=exp_matrix, anno=anno_matrix, network=network_matrix)
        printDeMAND(dobj)
        
        # 4. Run the network dysregulation analysis using runDeMAND()
        message("Running DeMAND analysis...")
        dobj <- runDeMAND(dobj, fgIndex=fgIndex, bgIndex=bgIndex)
        printDeMAND(dobj)
        
        # 5. Save the results to output files
        message("Saving results...")
        saveRDS(dobj, "demand_object.rds")
        
        # Extract and save MoA genes and dysregulated edges if slots are populated
        if ("moaData" %in% slotNames(dobj)) {
          write.csv(dobj@moaData, "moa_genes.csv", row.names = FALSE)
          message("Saved predicted MoA genes to 'moa_genes.csv'")
        }
        
        if ("KLD" %in% slotNames(dobj)) {
          write.csv(dobj@KLD, "dysregulated_edges.csv", row.names = FALSE)
          message("Saved dysregulated edges to 'dysregulated_edges.csv'")
        }
        
        message("DeMAND pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DEMAND_DRUG_MOA_PREDICTION":',
        paste0('    DeMAND: ', as.character(packageVersion('DeMAND')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drug_moa_prediction.csv versions.yml
    """
}

workflow BIOC_DEMAND_DRUG_MOA_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exp.ext, anno.ext, network.ext ] ]

    main:
    BIOC_DEMAND_DRUG_MOA_PREDICTION(ch_input)

    emit:
    tables   = BIOC_DEMAND_DRUG_MOA_PREDICTION.out.tables
    plots    = BIOC_DEMAND_DRUG_MOA_PREDICTION.out.plots
    objects  = BIOC_DEMAND_DRUG_MOA_PREDICTION.out.objects
    versions = BIOC_DEMAND_DRUG_MOA_PREDICTION.out.versions
}
