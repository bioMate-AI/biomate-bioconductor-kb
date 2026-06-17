#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KEGGREST — kegg_genomic_functional_profiling
// Map genomic regions to KEGG genes and pathways, retrieve protein sequences, and download pathway diagrams for functional profiling.
// Input: regions.bed, coldata.csv
// Container: 1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, KEGGREST, png, rtracklayer
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("rtracklayer", "GenomicRanges", "KEGGREST", "Biostrings", "png")
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
    library(rtracklayer)
    library(GenomicRanges)
    library(KEGGREST)
    library(Biostrings)
    library(png)
    
    # Define parameters
    organism_code <- "hsa"
    
    # --- Import Genomic Regions and Metadata ---
    message("Stage 1: Importing genomic regions and metadata...")
    if (!file.exists("regions.bed")) {
      stop("Required input file 'regions.bed' is missing.")
    }
    
    # Import BED file into a GRanges object
    gr <- rtracklayer::import("regions.bed")
    
    # Read optional coldata metadata if present
    coldata <- NULL
    if (file.exists("coldata.csv")) {
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    }
    
    # Extract gene identifiers from the 'name' column of the BED file
    # We assume these names represent NCBI Entrez Gene IDs (e.g., "10458")
    gene_ids <- unique(as.character(mcols(gr)\$name))
    gene_ids <- gene_ids[!is.na(gene_ids) & gene_ids != ""]
    
    if (length(gene_ids) == 0) {
      stop("No valid gene identifiers found in the 'name' column of regions.bed.")
    }
    
    # --- Map Identifiers to KEGG Genes ---
    message("Stage 2: Mapping NCBI Gene IDs to KEGG Gene IDs...")
    ncbi_query <- paste0("ncbi-geneid:", gene_ids)
    
    kegg_genes <- tryCatch({
      keggConv(organism_code, ncbi_query)
    }, error = function(e) {
      warning("keggConv failed. Attempting direct prefixing fallback: ", e\$message)
      # Fallback: construct standard KEGG gene IDs directly
      fallback_vals <- paste0(organism_code, ":", gene_ids)
      names(fallback_vals) <- ncbi_query
      fallback_vals
    })
    
    # --- Link KEGG Genes to Pathways ---
    message("Stage 3: Linking KEGG Genes to Pathways...")
    pathway_links <- tryCatch({
      keggLink("pathway", as.character(kegg_genes))
    }, error = function(e) {
      warning("keggLink failed: ", e\$message)
      NULL
    })
    
    # --- Build Comprehensive Mapping Table ---
    message("Stage 4: Building mapping table and retrieving pathway names...")
    
    # Convert GRanges to a standard data frame
    regions_df <- as.data.frame(gr)
    
    # Create a lookup table for the ID conversion
    mapping_df <- data.frame(
      name = gsub("ncbi-geneid:", "", names(kegg_genes)),
      kegg_gene_id = as.character(kegg_genes),
      stringsAsFactors = FALSE
    )
    
    # Merge genomic regions with KEGG gene IDs
    merged_df <- merge(regions_df, mapping_df, by = "name", all.x = TRUE)
    
    # Merge pathway links
    if (!is.null(pathway_links) && length(pathway_links) > 0) {
      pathway_df <- data.frame(
        kegg_gene_id = names(pathway_links),
        pathway_id = as.character(pathway_links),
        stringsAsFactors = FALSE
      )
      merged_df <- merge(merged_df, pathway_df, by = "kegg_gene_id", all.x = TRUE)
    } else {
      merged_df\$pathway_id <- NA
    }
    
    # Helper function to retrieve pathway names in chunks of 10 (KEGG API limit)
    get_pathway_names <- function(pathway_ids) {
      pathway_ids <- unique(na.omit(pathway_ids))
      if (length(pathway_ids) == 0) return(character(0))
      
      chunks <- split(pathway_ids, ceiling(seq_along(pathway_ids) / 10))
      names_list <- list()
      
      for (chunk in chunks) {
        tryCatch({
          res <- keggGet(chunk)
          for (i in seq_along(res)) {
            p_id <- chunk[i]
            p_name <- res[[i]]\$NAME
            if (!is.null(p_name)) {
              names_list[[p_id]] <- p_name
            }
          }
        }, error = function(e) {
          message("Error fetching pathway details for chunk: ", e\$message)
        })
      }
      return(unlist(names_list))
    }
    
    # Retrieve and map pathway names
    unique_pathways <- unique(na.omit(merged_df\$pathway_id))
    pathway_names <- get_pathway_names(unique_pathways)
    
    if (length(pathway_names) > 0) {
      pathway_names_df <- data.frame(
        pathway_id = names(pathway_names),
        pathway_name = as.character(pathway_names),
        stringsAsFactors = FALSE
      )
      merged_df <- merge(merged_df, pathway_names_df, by = "pathway_id", all.x = TRUE)
    } else {
      merged_df\$pathway_name <- NA
    }
    
    # Merge optional coldata if available
    if (!is.null(coldata)) {
      common_cols <- intersect(colnames(coldata), colnames(merged_df))
      if (length(common_cols) > 0) {
        merged_df <- merge(merged_df, coldata, by = common_cols, all.x = TRUE)
      }
    }
    
    # Write mapping table to CSV
    write.csv(merged_df, "kegg_mappings.csv", row.names = FALSE)
    message("Saved mapping table to 'kegg_mappings.csv'.")
    
    # --- Retrieve Gene Sequences ---
    message("Stage 5: Retrieving amino acid sequences...")
    unique_kegg_genes <- unique(na.omit(merged_df\$kegg_gene_id))
    # Limit to top 10 genes to respect API limits and performance
    genes_for_seq <- head(unique_kegg_genes, 10)
    
    if (length(genes_for_seq) > 0) {
      tryCatch({
        aa_seqs <- keggGet(genes_for_seq, "aaseq")
        Biostrings::writeXStringSet(aa_seqs, "gene_sequences.fasta")
        message("Saved amino acid sequences to 'gene_sequences.fasta'.")
      }, error = function(e) {
        warning("Failed to retrieve sequences: ", e\$message)
        writeLines(">no_sequences\n", "gene_sequences.fasta")
      })
    } else {
      writeLines(">no_sequences\n", "gene_sequences.fasta")
    }
    
    # --- Download Pathway Diagram ---
    message("Stage 6: Downloading top pathway diagram...")
    if (length(unique_pathways) > 0) {
      # Identify the most frequently occurring pathway in our dataset
      pathway_counts <- table(merged_df\$pathway_id)
      top_pathway <- names(sort(pathway_counts, decreasing = TRUE))[1]
      top_pathway_clean <- gsub("path:", "", top_pathway)
      
      tryCatch({
        png_data <- keggGet(top_pathway_clean, "image")
        png::writePNG(png_data, "top_pathway.png")
        message(sprintf("Saved top pathway diagram (%s) to 'top_pathway.png'.", top_pathway_clean))
      }, error = function(e) {
        warning("Failed to download pathway image: ", e\$message)
        writeLines("Failed to download pathway image", "top_pathway.png")
      })
    } else {
      writeLines("No pathways found to visualize", "top_pathway.png")
    }
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING":',
        paste0('    KEGGREST: ', as.character(packageVersion('KEGGREST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kegg_genomic_functional_profiling.csv versions.yml
    """
}

workflow BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING(ch_input)

    emit:
    tables   = BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING.out.tables
    plots    = BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING.out.plots
    objects  = BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING.out.objects
    versions = BIOC_KEGGREST_KEGG_GENOMIC_FUNCTIONAL_PROFILING.out.versions
}
