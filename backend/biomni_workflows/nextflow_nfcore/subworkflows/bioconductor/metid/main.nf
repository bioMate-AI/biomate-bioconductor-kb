#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetID — lc_ms_metabolite_id_scoring
// Score and prioritize putative metabolite identifications from LC-MS data using a network-based probabilistic framework.
// Input: metabolomics_data.csv
// Container: quay.io/biocontainers/bioconductor-metid:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetID
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MetID package and the input dataset
//  * 2. [Core Analysis] Format the column names of the dataset to meet the package's strict requirements
//  * 3. [Input & Preparation] Run get_scores_for_LC_MS to build the network, perform random sampling, and calculate identification scores

nextflow.enable.dsl = 2

process BIOC_METID_LC_MS_METABOLITE_ID_SCORING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
    .bm_deps <- c("MetID")
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
    
    # Load MetID package
    library(MetID)
    
    # Read the user input file
    input_file <- "metabolomics_data.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Helper to find column by name (case-insensitive, ignoring punctuation)
    find_col <- function(names_list, patterns) {
      for (pat in patterns) {
        idx <- grep(pat, names_list, ignore.case = TRUE)
        if (length(idx) > 0) return(idx[1])
      }
      return(NULL)
    }
    
    q_idx <- find_col(colnames(raw_data), c("query_m.z", "query.mass", "query", "m.z", "mz"))
    name_idx <- find_col(colnames(raw_data), c("name"))
    form_idx <- find_col(colnames(raw_data), c("formula"))
    e_idx <- find_col(colnames(raw_data), c("exact_m.z", "exact.mass", "exact"))
    pub_idx <- find_col(colnames(raw_data), c("pubchem_cid", "pubchem", "cid"))
    kegg_idx <- find_col(colnames(raw_data), c("kegg_id", "kegg"))
    metid_idx <- find_col(colnames(raw_data), c("metid", "peak", "id"))
    
    # Construct demo1 with exactly 6 columns to match the documented code's renaming step
    demo1 <- data.frame(
      Query.Mass = if (!is.null(q_idx)) as.numeric(raw_data[[q_idx]]) else rep(NA, nrow(raw_data)),
      Name = if (!is.null(name_idx)) as.character(raw_data[[name_idx]]) else rep("", nrow(raw_data)),
      Formula = if (!is.null(form_idx)) as.character(raw_data[[form_idx]]) else rep("", nrow(raw_data)),
      Exact.Mass = if (!is.null(e_idx)) as.numeric(raw_data[[e_idx]]) else rep(NA, nrow(raw_data)),
      PubChem.CID = if (!is.null(pub_idx)) as.character(raw_data[[pub_idx]]) else rep("-", nrow(raw_data)),
      KEGG.ID = if (!is.null(kegg_idx)) as.character(raw_data[[kegg_idx]]) else rep("-", nrow(raw_data)),
      stringsAsFactors = FALSE
    )
    
    # Handle missing values for PubChem and KEGG IDs to match the na='-' parameter
    demo1\$PubChem.CID[is.na(demo1\$PubChem.CID) | demo1\$PubChem.CID == "" | demo1\$PubChem.CID == "NA"] <- "-"
    demo1\$KEGG.ID[is.na(demo1\$KEGG.ID) | demo1\$KEGG.ID == "" | demo1\$KEGG.ID == "NA"] <- "-"
    
    # Format the column names of the dataset to meet the package's strict requirements
    colnames(demo1) <- c('query_m.z','name','formula','exact_m.z','pubchem_cid','kegg_id')
    
    # If peak IDs (metid) were provided, add them to the formatted data frame
    if (!is.null(metid_idx)) {
      demo1\$metid <- as.character(raw_data[[metid_idx]])
    }
    
    # Run get_scores_for_LC_MS to build the network, perform random sampling, and calculate identification scores
    out <- get_scores_for_LC_MS(demo1, type = 'data.frame', na='-', mode='POS')
    
    # Print head of the output to console
    head(out)
    
    # Save the results to output files
    write.csv(out, "metabolite_scores.csv", row.names = FALSE)
    saveRDS(out, "metabolite_scores.rds")

    writeLines(c(
        '"BIOC_METID_LC_MS_METABOLITE_ID_SCORING":',
        paste0('    MetID: ', as.character(packageVersion('MetID')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_metabolite_id_scoring.csv versions.yml
    """
}

workflow BIOC_METID_LC_MS_METABOLITE_ID_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolomics_data.csv ] ]

    main:
    BIOC_METID_LC_MS_METABOLITE_ID_SCORING(ch_input)

    emit:
    tables   = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.tables
    plots    = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.plots
    objects  = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.objects
    versions = BIOC_METID_LC_MS_METABOLITE_ID_SCORING.out.versions
}
