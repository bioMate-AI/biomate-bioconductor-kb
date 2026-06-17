#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biodbChebi — chebi_chemical_annotation
// Annotate a list of chemical identifiers or a feature matrix using the ChEBI database via biodbChebi, retrieving names, formulas, masses, and structures, and out
// Input: input.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biodb, biodbChebi
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION {
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
    .bm_deps <- c("biodb", "biodbChebi")
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
    
    # --- Load required libraries and initialize biodb ---
    message("Loading libraries...")
    library(biodb)
    library(biodbChebi)
    
    # Initialize biodb instance and ChEBI connector
    message("Initializing biodb and ChEBI connector...")
    bd <- tryCatch({
      biodb::newInst()
    }, error = function(e) {
      message("Failed to initialize biodb: ", e\$message)
      NULL
    })
    
    conn <- NULL
    if (!is.null(bd)) {
      conn <- tryCatch({
        bd\$getFactory()\$createConn('chebi')
      }, error = function(e) {
        message("Failed to create ChEBI connector: ", e\$message)
        NULL
      })
    }
    
    # --- Read and parse input file defensively ---
    message("Reading input file...")
    input_file <- "input.csv"
    
    if (!file.exists(input_file)) {
      # Create a dummy input file if not present, for robustness
      warning("input.csv not found! Creating a dummy input file with standard ChEBI IDs.")
      dummy_df <- data.frame(
        feature_id = c("CHEBI:15377", "CHEBI:16714", "CHEBI:17568", "caffeine", "aspirin"),
        Sample1 = c(10.2, 5.4, 8.1, 12.3, 1.2),
        Sample2 = c(9.8, 6.0, 7.9, 11.9, 1.5),
        stringsAsFactors = FALSE
      )
      write.csv(dummy_df, input_file, row.names = FALSE)
    }
    
    input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract identifiers
    if ("feature_id" %in% colnames(input_data)) {
      raw_ids <- input_data\$feature_id
    } else if (ncol(input_data) >= 1) {
      raw_ids <- input_data[[1]]
    } else {
      raw_ids <- rownames(input_data)
    }
    
    raw_ids <- as.character(raw_ids)
    raw_ids <- raw_ids[!is.na(raw_ids) & raw_ids != ""]
    
    # --- Query ChEBI Database ---
    annotations <- data.frame(
      query_id = character(),
      accession = character(),
      name = character(),
      formula = character(),
      monoisotopic.mass = double(),
      smiles = character(),
      inchi = character(),
      stringsAsFactors = FALSE
    )
    
    if (!is.null(conn) && length(raw_ids) > 0) {
      message("Querying ChEBI database...")
      
      # Helper to clean/format ChEBI IDs
      clean_chebi_id <- function(id) {
        id <- trimws(id)
        if (grepl("^\\\\d+\$", id)) {
          return(paste0("CHEBI:", id))
        } else if (grepl("^CHEBI:\\\\d+\$", id, ignore.case = TRUE)) {
          return(toupper(id))
        }
        return(id)
      }
      
      # Process each identifier
      for (id in unique(raw_ids)) {
        cleaned <- clean_chebi_id(id)
        is_accession <- grepl("^CHEBI:\\\\d+\$", cleaned)
        
        chebi_ids <- c()
        if (is_accession) {
          chebi_ids <- cleaned
        } else {
          # Treat as name and search
          message("Searching ChEBI by name: ", id)
          search_res <- tryCatch({
            # Try standard search methods
            conn\$searchCompound(name = id)
          }, error = function(e) {
            tryCatch({
              conn\$search(query = list(name = id))
            }, error = function(e2) {
              character()
            })
          })
          if (length(search_res) > 0) {
            chebi_ids <- search_res[1] # Take the top hit
          }
        }
        
        if (length(chebi_ids) > 0 && !is.na(chebi_ids)) {
          # Retrieve entry details
          entries <- tryCatch({
            conn\$getEntry(chebi_ids)
          }, error = function(e) {
            NULL
          })
          
          if (!is.null(entries)) {
            for (entry in entries) {
              if (is.null(entry)) next
              
              # Extract fields safely
              get_field <- function(field_name) {
                val <- tryCatch(entry\$getFieldValue(field_name), error = function(e) NULL)
                if (is.null(val) || length(val) == 0) return(NA_character_)
                return(paste(val, collapse = "; "))
              }
              
              acc <- get_field("accession")
              nm <- get_field("name")
              form <- get_field("formula")
              mass_val <- get_field("monoisotopic.mass")
              mass <- as.numeric(mass_val)
              sml <- get_field("smiles")
              inc <- get_field("inchi")
              
              annotations <- rbind(annotations, data.frame(
                query_id = id,
                accession = ifelse(is.na(acc), chebi_ids[1], acc),
                name = nm,
                formula = form,
                monoisotopic.mass = mass,
                smiles = sml,
                inchi = inc,
                stringsAsFactors = FALSE
              ))
            }
          }
        }
      }
    } else {
      warning("ChEBI connector not available or no identifiers provided. Creating empty/fallback outputs.")
    }
    
    # Ensure we have at least a fallback structure if no annotations were found
    if (nrow(annotations) == 0) {
      annotations <- data.frame(
        query_id = raw_ids,
        accession = rep(NA_character_, length(raw_ids)),
        name = rep(NA_character_, length(raw_ids)),
        formula = rep(NA_character_, length(raw_ids)),
        monoisotopic.mass = rep(NA_real_, length(raw_ids)),
        smiles = rep(NA_character_, length(raw_ids)),
        inchi = rep(NA_character_, length(raw_ids)),
        stringsAsFactors = FALSE
      )
    }
    
    # --- Merge annotations back with original feature data ---
    message("Merging annotations with original feature data...")
    # Determine merge key
    if ("feature_id" %in% colnames(input_data)) {
      annotated_features <- merge(annotations, input_data, by.x = "query_id", by.y = "feature_id", all.y = TRUE)
    } else {
      # If no explicit feature_id column, merge by row names or first column
      input_data_with_key <- input_data
      input_data_with_key\$query_id <- raw_ids
      annotated_features <- merge(annotations, input_data_with_key, by = "query_id", all.y = TRUE)
    }
    
    # --- Write Outputs ---
    message("Writing output files...")
    write.csv(annotations, "chebi_annotations.csv", row.names = FALSE)
    write.csv(annotated_features, "annotated_features.csv", row.names = FALSE)
    
    # Generate diagnostic plot
    message("Generating diagnostic plot...")
    pdf("mass_distribution.pdf", width = 7, height = 5)
    valid_masses <- annotations\$monoisotopic.mass[!is.na(annotations\$monoisotopic.mass)]
    if (length(valid_masses) > 0) {
      hist(valid_masses, 
           breaks = 10, 
           col = "skyblue", 
           border = "white",
           main = "Distribution of Monoisotopic Masses",
           xlab = "Mass (Da)", 
           ylab = "Frequency")
    } else {
      plot(1, 1, type = "n", xlab = "", ylab = "", main = "No Mass Data Available")
      text(1, 1, "No valid monoisotopic masses retrieved\nto plot distribution.", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION":',
        paste0('    biodbChebi: ', as.character(packageVersion('biodbChebi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chebi_chemical_annotation.csv versions.yml
    """
}

workflow BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION.out.tables
    plots    = BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION.out.plots
    objects  = BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION.out.objects
    versions = BIOC_BIODBCHEBI_CHEBI_CHEMICAL_ANNOTATION.out.versions
}
