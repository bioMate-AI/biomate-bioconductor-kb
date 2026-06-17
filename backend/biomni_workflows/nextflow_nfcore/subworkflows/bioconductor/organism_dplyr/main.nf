#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: organism_dplyr — organism_annotation_pipeline
// Annotate gene identifiers with genomic coordinates, transcript structures, and functional GO terms using a unified Organism.dplyr database.
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Organism.dplyr, TxDb.Hsapiens.UCSC.hg38.knownGene, dplyr, ggplot2, org.Hs.eg.db, organism_dplyr
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE {
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
    .bm_deps <- c("Organism.dplyr", "TxDb.Hsapiens.UCSC.hg38.knownGene", "org.Hs.eg.db", "dplyr", "ggplot2", "GenomicRanges")
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
    library(Organism.dplyr)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(org.Hs.eg.db)
    library(dplyr)
    library(ggplot2)
    library(GenomicRanges)
    
    # ==========================================
    # --- Read and Parse Input Defensively ---
    # ==========================================
    
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read input safely
    input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract identifiers (Entrez IDs or Gene Symbols)
    ids <- NULL
    if ("feature_id" %in% colnames(input_data)) {
      ids <- as.character(input_data\$feature_id)
    } else if (ncol(input_data) >= 1) {
      # If row names are non-trivial, use them; otherwise use the first column
      if (!is.null(rownames(input_data)) && any(rownames(input_data) != as.character(1:nrow(input_data)))) {
        ids <- rownames(input_data)
      } else {
        ids <- as.character(input_data[[1]])
      }
    }
    
    if (is.null(ids) || length(ids) == 0) {
      stop("Could not extract valid feature identifiers from input.csv")
    }
    
    # Clean identifiers
    ids <- unique(na.omit(trimws(ids)))
    ids <- ids[ids != ""]
    
    # ==========================================
    # --- Initialize Organism.dplyr Source ---
    # ==========================================
    
    # Create a temporary SQLite database combining TxDb and OrgDb
    db_path <- tempfile(fileext = ".sqlite")
    src <- src_organism(dbpath = db_path,
                        txdb = TxDb.Hsapiens.UCSC.hg38.knownGene,
                        orgdb = org.Hs.eg.db)
    
    # ==========================================
    # --- Query and Annotate Features ---
    # ==========================================
    
    # Extract tables from the organism source
    gene_tbl <- tbl(src, "gene")
    tx_tbl <- tbl(src, "transcript")
    
    # Query matching genes (supporting both Symbol and Entrez ID matching)
    matched_genes <- gene_tbl %>%
      filter(symbol %in% ids | gene_id %in% ids) %>%
      collect()
    
    if (nrow(matched_genes) == 0) {
      warning("No matching genes found in the database. Writing empty outputs.")
      
      # Write empty fallback outputs
      write.csv(data.frame(Message = "No matching genes found"), "annotated_features.csv", row.names = FALSE)
      write.csv(data.frame(Message = "No GO annotations found"), "go_annotations.csv", row.names = FALSE)
      
      pdf("feature_distribution.pdf")
      plot(0, 0, type = "n", xlab = "", ylab = "", main = "No Data to Plot")
      text(0, 0, "No matching genes found in database", col = "red")
      dev.off()
      
      q(save = "no", status = 0)
    }
    
    # Join genes with transcripts to get structural details
    gene_tx_joined <- inner_join(tbl(src, "gene"), tbl(src, "transcript"), by = "gene_id") %>%
      filter(symbol %in% ids | gene_id %in% ids) %>%
      collect()
    
    # Extract genomic coordinates using GenomicRanges integration
    # We extract all genes and subset to our matched set
    all_ranges <- tryCatch({
      genes(src)
    }, error = function(e) {
      warning("Direct GRanges extraction failed, falling back to manual coordinates.")
      NULL
    })
    
    # Build final annotation table
    annotated_df <- gene_tx_joined %>%
      group_by(gene_id, symbol, gene_name) %>%
      summarise(
        tx_count = n_distinct(tx_id),
        tx_ids = paste(unique(tx_id), collapse = ";"),
        .groups = "drop"
      )
    
    if (!is.null(all_ranges)) {
      coords_df <- as.data.frame(all_ranges)
      coords_df\$gene_id <- rownames(coords_df)
      annotated_df <- left_join(annotated_df, coords_df, by = "gene_id")
    }
    
    # Write annotated features
    write.csv(annotated_df, "annotated_features.csv", row.names = FALSE)
    
    # ==========================================
    # --- Functional Annotation (GO Terms) ---
    # ==========================================
    
    if ("go" %in% src_tbls(src)) {
      go_tbl <- tbl(src, "go")
      gene_go <- inner_join(tbl(src, "gene"), go_tbl, by = "gene_id") %>%
        filter(symbol %in% ids | gene_id %in% ids) %>%
        select(gene_id, symbol, go, evidence, ontology) %>%
        collect()
      
      write.csv(gene_go, "go_annotations.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "GO table not available"), "go_annotations.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    
    # Plot top 30 genes by transcript count
    plot_data <- head(annotated_df %>% arrange(desc(tx_count)), 30)
    
    pdf("feature_distribution.pdf", width = 10, height = 8)
    p <- ggplot(plot_data, aes(x = reorder(symbol, tx_count), y = tx_count)) +
      geom_bar(stat = "identity", fill = "steelblue", width = 0.7) +
      coord_flip() +
      theme_minimal(base_size = 12) +
      labs(
        title = "Top Annotated Genes by Transcript Count",
        subtitle = "Extracted via Organism.dplyr",
        x = "Gene Symbol",
        y = "Number of Transcripts"
      ) +
      theme(
        plot.title = element_text(face = "bold", hjust = 0.5),
        plot.subtitle = element_text(face = "italic", hjust = 0.5)
      )
    print(p)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE":',
        paste0('    organism_dplyr: ', as.character(packageVersion('organism_dplyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_organism_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_ORGANISM_DPLYR_ORGANISM_ANNOTATION_PIPELINE.out.versions
}
