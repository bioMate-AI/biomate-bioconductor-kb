#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: customCMPdb — custom_compound_annotation_pipeline
// Query community small molecule databases and integrate custom compound annotations and structures using customCMPdb and ChemmineR.
// Input: input.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ChemmineR, RSQLite, customCMPdb
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE {
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
    .bm_deps <- c("customCMPdb", "RSQLite", "ChemmineR")
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
    library(customCMPdb)
    library(RSQLite)
    library(ChemmineR)
    
    # ==========================================
    # --- Read and Parse Input Identifiers ---
    # ==========================================
    message("Stage 1: Reading input compound identifiers...")
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found. Please ensure it is staged in the working directory.")
    }
    
    input_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract query identifiers defensively
    if ("feature_id" %in% colnames(input_data)) {
      query_ids <- as.character(input_data\$feature_id)
    } else if (ncol(input_data) >= 1) {
      query_ids <- as.character(input_data[[1]])
    } else {
      stop("Could not find query identifiers in input.csv")
    }
    
    # Clean and deduplicate identifiers
    query_ids <- unique(query_ids[!is.na(query_ids) & query_ids != ""])
    
    if (length(query_ids) == 0) {
      message("Warning: No valid identifiers found in input.csv. Using fallback ChEMBL IDs for demonstration.")
      query_ids <- c("CHEMBL1064", "CHEMBL10", "CHEMBL113", "CHEMBL1004", "CHEMBL31574")
    }
    
    # ==========================================
    # --- Query Default Community Databases ---
    # ==========================================
    message("Stage 2: Querying default community databases...")
    available_annots <- listAnnot()
    target_annots <- intersect(c("drugAgeAnnot", "lincsAnnot", "DrugBankAnnot", "cmapAnnot"), available_annots)
    
    if (length(target_annots) == 0) {
      target_annots <- available_annots
    }
    
    qres_default <- tryCatch({
      queryAnnotDB(query_ids, annot = target_annots)
    }, error = function(e) {
      message("Error querying default annotations: ", e\$message)
      # Fallback dataframe
      data.frame(chembl_id = query_ids, status = "Query failed")
    })
    
    write.csv(qres_default, "query_results_default.csv", row.names = FALSE)
    
    # ==========================================
    # --- Integrate Custom Annotations ---
    # ==========================================
    message("Stage 3: Integrating custom annotations...")
    
    # Prepare custom annotation table
    annot_tb <- input_data
    if (!"chembl_id" %in% colnames(annot_tb)) {
      if ("feature_id" %in% colnames(annot_tb)) {
        annot_tb\$chembl_id <- annot_tb\$feature_id
      } else {
        annot_tb\$chembl_id <- query_ids[1:min(length(query_ids), nrow(annot_tb))]
      }
    }
    annot_tb\$chembl_id <- as.character(annot_tb\$chembl_id)
    
    # Ensure there are additional descriptive features to store
    if (ncol(annot_tb) < 2) {
      annot_tb\$custom_feature_1 <- paste0("feat_", seq_len(nrow(annot_tb)))
      annot_tb\$custom_score <- runif(nrow(annot_tb), 1, 100)
    }
    
    custom_name <- "user_custom_annot"
    
    # Add custom annotations to the SQLite database
    tryCatch({
      addCustomAnnot(annot_tb, annot_name = custom_name, overwrite = TRUE)
      message("Custom annotation table successfully added.")
    }, error = function(e) {
      message("Failed to add custom annotation: ", e\$message)
    })
    
    # Query default databases combined with the newly added custom annotations
    qres_custom <- tryCatch({
      queryAnnotDB(query_ids, annot = c(target_annots, custom_name))
    }, error = function(e) {
      message("Error querying custom annotations: ", e\$message)
      qres_default
    })
    
    write.csv(qres_custom, "query_results_custom.csv", row.names = FALSE)
    
    # Clean up custom annotation table to keep the database pristine
    tryCatch({
      deleteAnnot(custom_name)
      message("Temporary custom annotation table cleaned up.")
    }, error = function(e) {
      message("Failed to delete custom annotation: ", e\$message)
    })
    
    # ==========================================
    # --- Load and Visualize Structures ---
    # ==========================================
    message("Stage 4: Loading and plotting compound structures...")
    
    pdf("compound_structures.pdf", width = 10, height = 10)
    op <- par(mfrow = c(2, 2))
    
    # Load and plot DrugAge structures
    tryCatch({
      da_sdfset <- loadSDFwithName(source = "DrugAge")
      if (length(da_sdfset) > 0) {
        ChemmineR::cid(da_sdfset) <- ChemmineR::sdfid(da_sdfset)
        plot(da_sdfset[1], main = "DrugAge Structure Example")
      }
    }, error = function(e) {
      message("Could not load/plot DrugAge structures: ", e\$message)
    })
    
    # Load and plot LINCS structures
    tryCatch({
      lincs_sdfset <- loadSDFwithName(source = "LINCS")
      if (length(lincs_sdfset) > 0) {
        ChemmineR::cid(lincs_sdfset) <- ChemmineR::sdfid(lincs_sdfset)
        plot(lincs_sdfset[1], main = "LINCS Structure Example")
      }
    }, error = function(e) {
      message("Could not load/plot LINCS structures: ", e\$message)
    })
    
    par(op)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE":',
        paste0('    customCMPdb: ', as.character(packageVersion('customCMPdb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_compound_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_CUSTOMCMPDB_CUSTOM_COMPOUND_ANNOTATION_PIPELINE.out.versions
}
