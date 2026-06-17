#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mygene — mygene_annotation_pipeline
// Map genomic region names to comprehensive gene annotations and build custom transcript models using the MyGene.info API.
// Input: regions.bed, coldata.csv
// Container: 1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, S4Vectors, mygene, rtracklayer
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("mygene", "rtracklayer", "GenomicRanges", "BiocGenerics", "S4Vectors")
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
    library(mygene)
    library(rtracklayer)
    library(GenomicRanges)
    library(BiocGenerics)
    library(S4Vectors)
    
    # --- Import Input Data ---
    message("Stage 1: Importing input genomic regions...")
    if (!file.exists("regions.bed")) {
      stop("Input file 'regions.bed' is missing.")
    }
    
    # Import BED file as GRanges
    gr <- rtracklayer::import("regions.bed")
    message(sprintf("Successfully imported %d genomic regions.", length(gr)))
    
    # Extract query terms from the 'name' column of the BED file
    if (!"name" %in% colnames(mcols(gr)) || all(is.na(gr\$name))) {
      warning("The 'name' column in regions.bed is missing or empty. Using sequential identifiers.")
      gr\$name <- paste0("Region_", seq_along(gr))
    }
    query_ids <- unique(gr\$name)
    query_ids <- query_ids[!is.na(query_ids) & query_ids != ""]
    
    # Read optional metadata if available
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      message("Optional metadata 'coldata.csv' loaded.")
    }
    
    # --- ID Mapping & Annotation Retrieval via MyGene.info ---
    message("Stage 2: Querying MyGene.info API...")
    annotations_df <- data.frame()
    mapping_summary <- list(matched = 0, missing = 0, duplicates = 0)
    
    if (length(query_ids) > 0) {
      # Query MyGene.info for Entrez, Ensembl, Uniprot, and gene symbols
      query_results <- tryCatch({
        queryMany(query_ids, 
                  scopes = c("symbol", "reporter", "accession"),
                  fields = c("entrezgene", "ensembl.gene", "uniprot", "name", "symbol"),
                  species = "human", 
                  returnall = TRUE)
      }, error = function(e) {
        message("API Query failed: ", e\$message)
        NULL
      })
      
      if (!is.null(query_results)) {
        # Extract response DataFrame
        annotations_df <- as.data.frame(query_results\$response)
        
        # Record mapping statistics
        mapping_summary\$matched <- sum(!is.na(annotations_df\$notfound) & annotations_df\$notfound == FALSE)
        if ("missing" %in% names(query_results)) {
          mapping_summary\$missing <- length(query_results\$missing)
        }
        if ("duplicates" %in% names(query_results)) {
          mapping_summary\$duplicates <- length(query_results\$duplicates)
        }
      }
    }
    
    # --- Merge Annotations with Original Genomic Regions ---
    message("Stage 3: Merging annotations with genomic regions...")
    if (nrow(annotations_df) > 0) {
      # Convert GRanges to data frame for merging
      gr_df <- as.data.frame(gr)
      
      # Merge based on the query term
      annotated_df <- merge(gr_df, annotations_df, by.x = "name", by.y = "query", all.x = TRUE)
      write.csv(annotated_df, "annotated_regions.csv", row.names = FALSE)
      message("Saved annotated regions to 'annotated_regions.csv'.")
    } else {
      # Fallback if query failed or returned no results
      write.csv(as.data.frame(gr), "annotated_regions.csv", row.names = FALSE)
      message("No annotations retrieved. Saved original regions to 'annotated_regions.csv'.")
    }
    
    # --- Dynamic Transcript Model Construction ---
    message("Stage 4: Building TxDb transcript models from mapped genes...")
    tx_df <- data.frame(
      seqnames = character(), 
      start = integer(), 
      end = integer(), 
      strand = character(), 
      tx_id = integer(), 
      tx_name = character()
    )
    
    if (nrow(annotations_df) > 0 && "symbol" %in% colnames(annotations_df)) {
      valid_symbols <- unique(annotations_df\$symbol)
      valid_symbols <- valid_symbols[!is.na(valid_symbols) & valid_symbols != ""]
      
      if (length(valid_symbols) > 0) {
        tryCatch({
          # Build TxDb object using mygene
          txdb <- makeTxDbFromMyGene(valid_symbols, scopes = "symbol", species = "human")
          
          # Extract transcripts
          tx <- transcripts(txdb)
          tx_df <- as.data.frame(tx)
          message(sprintf("Successfully built TxDb and extracted %d transcripts.", nrow(tx_df)))
        }, error = function(e) {
          warning("Failed to build TxDb from MyGene: ", e\$message)
        })
      }
    }
    
    write.csv(tx_df, "retrieved_transcripts.csv", row.names = FALSE)
    message("Saved transcript models to 'retrieved_transcripts.csv'.")
    
    # --- Diagnostic Visualization ---
    message("Stage 5: Generating diagnostic plots...")
    pdf("query_summary.pdf", width = 8, height = 6)
    
    # Set up plotting layout
    par(mfrow = c(1, 2), mar = c(5, 4, 4, 2) + 0.1)
    
    # Plot 1: Mapping Success Rate
    counts <- c(
      Matched = nrow(annotations_df) - mapping_summary\$missing, 
      Missing = mapping_summary\$missing,
      Duplicates = mapping_summary\$duplicates
    )
    barplot(counts, 
            col = c("skyblue", "tomato", "orange"), 
            main = "Query Mapping Status", 
            ylab = "Number of Query Terms",
            las = 1)
    
    # Plot 2: Distribution of Query Scores
    if (nrow(annotations_df) > 0 && "X_score" %in% colnames(annotations_df)) {
      scores <- annotations_df\$X_score[!is.na(annotations_df\$X_score)]
      if (length(scores) > 0) {
        hist(scores, 
             col = "lightgreen", 
             main = "Distribution of Query Scores", 
             xlab = "MyGene.info Alignment Score", 
             ylab = "Frequency",
             breaks = 10)
      } else {
        plot.new()
        text(0.5, 0.5, "No query scores available", cex = 1.2)
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No query scores available", cex = 1.2)
    }
    
    dev.off()
    message("Saved diagnostic plots to 'query_summary.pdf'.")
    message("Pipeline complete.")

    writeLines(c(
        '"BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE":',
        paste0('    mygene: ', as.character(packageVersion('mygene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mygene_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_MYGENE_MYGENE_ANNOTATION_PIPELINE.out.versions
}
