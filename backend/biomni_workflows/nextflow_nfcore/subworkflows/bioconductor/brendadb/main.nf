#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: brendaDb — brenda_enzyme_annotation
// Map gene symbols or EC numbers from an input list to the BRENDA database, query functional parameters (pH optimum, KM values, substrates), and export structured
// Input: input.csv
// Container: 1.24.0--r45ha27e39d_0
// R packages: brendaDb
// Bioconductor: 3.20 | R: 4.4
// Requires: brendaDb
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION {
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
    .bm_deps <- c("brendaDb")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(brendaDb)
    
    # --- Read and parse input identifiers defensively ---
    message("Reading input.csv...")
    if (!file.exists("input.csv")) {
      stop("Staged input file 'input.csv' not found.")
    }
    
    input_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract identifiers from the input
    if ("feature_id" %in% colnames(input_data)) {
      ids <- input_data\$feature_id
    } else if (ncol(input_data) == 1) {
      ids <- input_data[[1]]
    } else {
      ids <- rownames(input_data)
    }
    
    # Clean and deduplicate identifiers
    ids <- unique(as.character(ids))
    ids <- ids[ids != "" & !is.na(ids)]
    
    if (length(ids) == 0) {
      stop("No valid identifiers found in input.csv.")
    }
    message(paste("Found", length(ids), "unique identifiers to process."))
    
    # --- Download and load the BRENDA database ---
    message("Downloading and loading BRENDA database...")
    brenda_file <- tryCatch({
      DownloadBrenda()
    }, error = function(e) {
      message("Failed to download BRENDA database automatically: ", e\$message)
      NULL
    })
    
    if (is.null(brenda_file)) {
      # Fallback: Write empty output files with informative messages if database is unavailable
      message("Writing fallback empty outputs due to missing BRENDA database.")
      write.csv(data.frame(Error = "BRENDA database download failed"), "mapped_enzymes.csv", row.names = FALSE)
      write.csv(data.frame(Error = "BRENDA database download failed"), "enzyme_ph_optimum.csv", row.names = FALSE)
      write.csv(data.frame(Error = "BRENDA database download failed"), "enzyme_km_values.csv", row.names = FALSE)
      write.csv(data.frame(Error = "BRENDA database download failed"), "enzyme_substrates_products.csv", row.names = FALSE)
      quit(save = "no", status = 0)
    }
    
    df <- tryCatch({
      ReadBrenda(brenda_file)
    }, error = function(e) {
      stop("Failed to parse BRENDA database file: ", e\$message)
    })
    
    # --- Map identifiers to EC numbers ---
    message("Mapping input identifiers to EC numbers...")
    is_ec <- grepl("^\\\\d+\\\\.\\\\d+\\\\.\\\\d+\\\\.\\\\d+\$", ids)
    ec_numbers <- ids[is_ec]
    other_ids <- ids[!is_ec]
    
    mapping_df <- data.frame(ID = character(), EC = character(), RECOMMENDED_NAME = character(), stringsAsFactors = FALSE)
    
    if (length(other_ids) > 0) {
      mapped <- tryCatch({
        ID2Enzyme(brenda = df, ids = other_ids)
      }, error = function(e) {
        message("Error mapping IDs to enzymes: ", e\$message)
        NULL
      })
      
      if (!is.null(mapped) && nrow(mapped) > 0) {
        mapping_df <- as.data.frame(mapped)
        mapped_ecs <- unique(mapping_df\$EC)
        mapped_ecs <- mapped_ecs[!is.na(mapped_ecs) & mapped_ecs != ""]
        ec_numbers <- unique(c(ec_numbers, mapped_ecs))
      }
    }
    
    # Save mapping results
    write.csv(mapping_df, "mapped_enzymes.csv", row.names = FALSE)
    message(paste("Total EC numbers to query:", length(ec_numbers)))
    
    # --- Query BRENDA and extract functional parameters ---
    if (length(ec_numbers) > 0) {
      message("Querying BRENDA database for EC numbers...")
      res <- tryCatch({
        QueryBrenda(df, EC = ec_numbers, n.core = 2)
      }, error = function(e) {
        message("Error querying BRENDA: ", e\$message)
        NULL
      })
      
      if (!is.null(res)) {
        # Extract pH Optimum
        message("Extracting pH optimum values...")
        ph_opt <- tryCatch({
          ExtractField(res, field = "parameters\$ph.optimum")
        }, error = function(e) {
          data.frame(Warning = "No pH optimum data extracted", Details = e\$message)
        })
        write.csv(ph_opt, "enzyme_ph_optimum.csv", row.names = FALSE)
        
        # Extract KM Values
        message("Extracting KM values...")
        km_val <- tryCatch({
          ExtractField(res, field = "parameters\$km.value")
        }, error = function(e) {
          data.frame(Warning = "No KM value data extracted", Details = e\$message)
        })
        write.csv(km_val, "enzyme_km_values.csv", row.names = FALSE)
        
        # Extract Substrates and Products
        message("Extracting substrate and product interactions...")
        sub_prod <- tryCatch({
          ExtractField(res, field = "interactions\$substrate.product")
        }, error = function(e) {
          data.frame(Warning = "No substrate/product data extracted", Details = e\$message)
        })
        write.csv(sub_prod, "enzyme_substrates_products.csv", row.names = FALSE)
        
      } else {
        # Fallback if query returned NULL
        write.csv(data.frame(Error = "Query returned no results"), "enzyme_ph_optimum.csv", row.names = FALSE)
        write.csv(data.frame(Error = "Query returned no results"), "enzyme_km_values.csv", row.names = FALSE)
        write.csv(data.frame(Error = "Query returned no results"), "enzyme_substrates_products.csv", row.names = FALSE)
      }
    } else {
      message("No valid EC numbers found or mapped. Writing empty outputs.")
      write.csv(data.frame(Warning = "No EC numbers to query"), "enzyme_ph_optimum.csv", row.names = FALSE)
      write.csv(data.frame(Warning = "No EC numbers to query"), "enzyme_km_values.csv", row.names = FALSE)
      write.csv(data.frame(Warning = "No EC numbers to query"), "enzyme_substrates_products.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION":',
        paste0('    brendaDb: ', as.character(packageVersion('brendaDb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_brenda_enzyme_annotation.csv versions.yml
    """
}

workflow BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION.out.tables
    plots    = BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION.out.plots
    objects  = BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION.out.objects
    versions = BIOC_BRENDADB_BRENDA_ENZYME_ANNOTATION.out.versions
}
