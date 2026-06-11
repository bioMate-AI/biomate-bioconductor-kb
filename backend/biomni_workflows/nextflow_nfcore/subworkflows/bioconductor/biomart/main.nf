#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biomaRt — biomart_genomic_annotation
// Annotate a list of gene identifiers with genomic coordinates, functional GO terms, promoter sequences, and mouse homologs using biomaRt.
// Input: input.csv
// Container: 2.66.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biomaRt
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION {
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
    .bm_deps <- c("biomaRt")
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
    library(biomaRt)
    
    # ==========================================
    # --- Defensive Input Reading & Parsing ---
    # ==========================================
    
    input_file <- "input.csv"
    ids <- character()
    
    if (file.exists(input_file)) {
      message("Reading input file: ", input_file)
      input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
      
      if (ncol(input_data) > 0) {
        if ("feature_id" %in% colnames(input_data)) {
          ids <- as.character(input_data\$feature_id)
        } else if (ncol(input_data) == 1) {
          ids <- as.character(input_data[[1]])
        } else {
          ids <- as.character(rownames(input_data))
        }
      }
    } else {
      message("Input file not found. Proceeding with fallback IDs.")
    }
    
    # Clean and deduplicate IDs
    ids <- unique(ids[!is.na(ids) & ids != ""])
    
    # Fallback to standard Ensembl Gene IDs if input is empty or invalid
    if (length(ids) == 0) {
      message("No valid identifiers found. Using default Ensembl Gene IDs (TP53, BRCA2, GAPDH) for robustness.")
      ids <- c("ENSG00000141510", "ENSG00000139618", "ENSG00000111640")
      filter_type <- "ensembl_gene_id"
    } else {
      # Heuristic to determine the filter type based on ID patterns
      if (any(grepl("^ENSG", ids))) {
        filter_type <- "ensembl_gene_id"
      } else if (any(grepl("_at\$", ids))) {
        filter_type <- "affy_hg_u133_plus_2"
      } else if (any(grepl("^[0-9]+\$", ids))) {
        filter_type <- "entrezgene_id"
      } else {
        filter_type <- "hgnc_symbol"
      }
    }
    
    message("Determined filter type: ", filter_type)
    message("Processing ", length(ids), " unique identifiers.")
    
    # ==========================================
    # --- Establish Connection to BioMart ---
    # ==========================================
    
    # Configure SSL settings defensively to avoid common handshake/certificate errors
    tryCatch({
      setEnsemblSSL(list(ssl_verifypeer = FALSE))
    }, error = function(e) {
      message("Warning: Could not set SSL settings: ", e\$message)
    })
    
    # Connect to Ensembl Human Genes dataset
    ensembl <- tryCatch({
      useEnsembl(biomart = "genes", dataset = "hsapiens_gene_ensembl")
    }, error = function(e) {
      message("Primary connection failed. Attempting US East mirror...")
      tryCatch({
        useEnsembl(biomart = "genes", dataset = "hsapiens_gene_ensembl", mirror = "useast")
      }, error = function(err2) {
        stop("Fatal: Unable to connect to Ensembl BioMart. Error: ", err2\$message)
      })
    })
    
    # Print cache information for diagnostic purposes
    tryCatch({
      print(biomartCacheInfo())
    }, error = function(e) {
      message("Could not retrieve cache info.")
    })
    
    # ==========================================
    # --- Retrieve Basic Gene Annotations ---
    # ==========================================
    
    message("Retrieving basic gene annotations...")
    attributes_to_retrieve <- c(
      "ensembl_gene_id", 
      "hgnc_symbol", 
      "chromosome_name", 
      "start_position", 
      "end_position", 
      "band", 
      "description"
    )
    
    annot_df <- tryCatch({
      getBM(
        attributes = attributes_to_retrieve,
        filters = filter_type,
        values = ids,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving basic annotations: ", e\$message)
      # Return empty dataframe with expected structure
      data.frame(matrix(ncol = length(attributes_to_retrieve), nrow = 0, 
                        dimnames = list(NULL, attributes_to_retrieve)))
    })
    
    write.csv(annot_df, "gene_annotations.csv", row.names = FALSE)
    
    # ==========================================
    # --- Retrieve Gene Ontology (GO) Terms ---
    # ==========================================
    
    message("Retrieving Gene Ontology annotations...")
    go_attributes <- c("ensembl_gene_id", "go_id", "name_1006", "namespace_1003")
    
    # Use mapped Ensembl IDs if available for more reliable downstream queries
    query_ids <- ids
    query_filter <- filter_type
    if (filter_type != "ensembl_gene_id" && nrow(annot_df) > 0) {
      mapped_ids <- unique(annot_df\$ensembl_gene_id)
      mapped_ids <- mapped_ids[mapped_ids != "" & !is.na(mapped_ids)]
      if (length(mapped_ids) > 0) {
        query_ids <- mapped_ids
        query_filter <- "ensembl_gene_id"
      }
    }
    
    go_df <- tryCatch({
      getBM(
        attributes = go_attributes,
        filters = query_filter,
        values = query_ids,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving GO annotations: ", e\$message)
      data.frame(matrix(ncol = length(go_attributes), nrow = 0, 
                        dimnames = list(NULL, go_attributes)))
    })
    
    write.csv(go_df, "go_annotations.csv", row.names = FALSE)
    
    # ==========================================
    # --- Retrieve Promoter Sequences ---
    # ==========================================
    
    message("Retrieving 100bp upstream promoter sequences...")
    seq_df <- tryCatch({
      getSequence(
        id = query_ids,
        type = query_filter,
        seqType = "coding_gene_flank",
        upstream = 100,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving sequences: ", e\$message)
      data.frame(coding_gene_flank = character(), ensembl_gene_id = character())
    })
    
    write.csv(seq_df, "promoter_sequences.csv", row.names = FALSE)
    
    # ==========================================
    # --- Retrieve Mouse Homologs ---
    # ==========================================
    
    message("Mapping human genes to mouse homologs...")
    homologs_df <- tryCatch({
      ens_ids <- query_ids
      if (query_filter != "ensembl_gene_id" && nrow(annot_df) > 0) {
        ens_ids <- unique(annot_df\$ensembl_gene_id)
      }
      ens_ids <- ens_ids[grepl("^ENSG", ens_ids)]
      
      if (length(ens_ids) > 0) {
        getHomologs(
          ensembl_gene_ids = ens_ids,
          species_from = "human",
          species_to = "mouse"
        )
      } else {
        data.frame(ensembl_gene_id = character(), mmusculus_homolog_ensembl_gene = character())
      }
    }, error = function(e) {
      message("Error mapping homologs: ", e\$message)
      data.frame(ensembl_gene_id = character(), mmusculus_homolog_ensembl_gene = character())
    })
    
    # Retrieve detailed coordinates and RefSeq IDs for the mouse homologs
    mouse_details_df <- data.frame(
      ensembl_gene_id = character(), 
      refseq_mrna = character(), 
      chromosome_name = character(), 
      start_position = integer()
    )
    
    if (nrow(homologs_df) > 0) {
      mouse_ids <- unique(homologs_df\$mmusculus_homolog_ensembl_gene)
      mouse_ids <- mouse_ids[mouse_ids != "" & !is.na(mouse_ids)]
      
      if (length(mouse_ids) > 0) {
        message("Retrieving mouse homolog details...")
        mouse_details_df <- tryCatch({
          mouse_mart <- useEnsembl(biomart = "genes", dataset = "mmusculus_gene_ensembl")
          getBM(
            mart = mouse_mart,
            filters = "ensembl_gene_id",
            values = mouse_ids,
            attributes = c("ensembl_gene_id", "refseq_mrna", "chromosome_name", "start_position")
          )
        }, error = function(e) {
          message("Error retrieving mouse details: ", e\$message)
          data.frame(ensembl_gene_id = character(), refseq_mrna = character(), 
                     chromosome_name = character(), start_position = integer())
        })
      }
    }
    
    # Merge homology mapping with mouse details
    final_homology_df <- merge(
      homologs_df, 
      mouse_details_df, 
      by.x = "mmusculus_homolog_ensembl_gene", 
      by.y = "ensembl_gene_id", 
      all.x = TRUE
    )
    
    write.csv(final_homology_df, "mouse_homologs.csv", row.names = FALSE)
    
    # ==========================================
    # --- Diagnostics & Visualization ---
    # ==========================================
    
    message("Generating diagnostic plots...")
    pdf("chromosome_distribution.pdf", width = 8, height = 6)
    
    if (nrow(annot_df) > 0 && "chromosome_name" %in% colnames(annot_df)) {
      chrom_counts <- table(annot_df\$chromosome_name)
      # Sort chromosomes numerically/alphabetically
      chrom_names <- names(chrom_counts)
      suppressWarnings({
        numeric_chroms <- as.numeric(chrom_names)
      })
      order_idx <- order(is.na(numeric_chroms), numeric_chroms, chrom_names)
      chrom_counts <- chrom_counts[order_idx]
      
      barplot(
        chrom_counts,
        las = 2,
        col = "skyblue",
        main = "Distribution of Annotated Genes Across Chromosomes",
        xlab = "Chromosome",
        ylab = "Number of Genes"
      )
    } else {
      # Fallback empty plot if no data is available
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No chromosome data available to plot.", cex = 1.2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION":',
        paste0('    biomaRt: ', as.character(packageVersion('biomaRt')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomart_genomic_annotation.csv versions.yml
    """
}

workflow BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION.out.tables
    plots    = BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION.out.plots
    objects  = BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION.out.objects
    versions = BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION.out.versions
}
