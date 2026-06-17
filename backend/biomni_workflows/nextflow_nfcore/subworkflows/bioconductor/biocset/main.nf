#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BiocSet — biocset_de_gsea_pipeline
// Integrate differential expression results with Gene Ontology enrichment analysis using BiocSet to filter, annotate, and generate reference URLs for functional g
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, BiocSet, DESeq2, GO.db, dplyr, limma, org.Hs.eg.db, tibble
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE {
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
    .bm_deps <- c("BiocSet", "DESeq2", "org.Hs.eg.db", "GO.db", "limma", "dplyr", "tibble")
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
    library(BiocSet)
    library(DESeq2)
    library(org.Hs.eg.db)
    library(GO.db)
    library(limma)
    library(dplyr)
    library(tibble)
    
    # ----------------------------------------------------------------------
    # --- Load Input Data ---
    # ----------------------------------------------------------------------
    message("Loading input expression data...")
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
        stop("Input counts.csv must contain a 'gene_id' column.")
    }
    
    # Set gene_id as row names and convert to matrix
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    # Load sample metadata
    coldata <- read.csv("coldata.csv")
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
        stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata) <- coldata\$sample
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure condition is a factor
    coldata\$condition <- as.factor(coldata\$condition)
    
    # ----------------------------------------------------------------------
    # --- Differential Expression Analysis ---
    # ----------------------------------------------------------------------
    message("Running DESeq2 differential expression analysis...")
    dds <- DESeqDataSetFromMatrix(countData = counts_matrix,
                                  colData = coldata,
                                  design = ~ condition)
    dds <- DESeq(dds)
    res <- results(dds)
    
    res_tbl <- as.data.frame(res) %>%
        rownames_to_column("ENSEMBL") %>%
        as_tibble()
    
    # ----------------------------------------------------------------------
    # --- ID Mapping and GSEA Preparation ---
    # ----------------------------------------------------------------------
    message("Mapping Ensembl IDs to Entrez IDs...")
    res_tbl <- res_tbl %>%
        mutate(ENTREZID = mapIds(org.Hs.eg.db,
                                 keys = ENSEMBL,
                                 keytype = "ENSEMBL",
                                 column = "ENTREZID",
                                 multiVals = "first") %>% unname()) %>%
        filter(!is.na(padj), !is.na(ENTREZID))
    
    # Identify significant genes
    p_adj_cutoff <- 0.05
    sig_genes <- res_tbl %>% filter(padj < p_adj_cutoff) %>% pull(ENTREZID)
    all_genes <- res_tbl\$ENTREZID
    
    # Fallback if no genes are significant
    if (length(sig_genes) == 0) {
        message("Warning: No genes met the significance threshold. Using top 100 genes by p-value.")
        sig_genes <- res_tbl %>% arrange(pvalue) %>% head(100) %>% pull(ENTREZID)
    }
    
    # ----------------------------------------------------------------------
    # --- Gene Set Enrichment Analysis (GSEA) ---
    # ----------------------------------------------------------------------
    message("Performing Gene Ontology enrichment analysis...")
    go_results <- goana(de = sig_genes, universe = all_genes, species = "Hs") %>%
        as.data.frame() %>%
        rownames_to_column("GOALL") %>%
        as_tibble()
    
    # Retrieve mapping between Entrez IDs and GO terms
    message("Retrieving gene-to-GO mappings...")
    go_mapping <- AnnotationDbi::select(org.Hs.eg.db,
                                        keys = res_tbl\$ENTREZID,
                                        columns = "GOALL",
                                        keytype = "ENTREZID") %>%
        as_tibble() %>%
        dplyr::select(-EVIDENCEALL) %>%
        distinct() %>%
        filter(ONTOLOGYALL == "BP") %>%
        dplyr::select(-ONTOLOGYALL)
    
    # ----------------------------------------------------------------------
    # --- Construct and Manipulate BiocSet ---
    # ----------------------------------------------------------------------
    message("Constructing BiocSet object...")
    # Rename columns to match BiocSet requirements (element, set)
    element_df <- res_tbl %>% dplyr::rename(element = ENTREZID)
    set_df <- go_results %>% dplyr::rename(set = GOALL)
    elementset_df <- go_mapping %>% dplyr::rename(element = ENTREZID, set = GOALL)
    
    # Create BiocSet from the elementset mapping and metadata tibbles
    es <- BiocSet_from_elementset(elementset_df, element_df, set_df)
    
    # Filter sets to keep only enriched ones (P.DE < 0.05)
    message("Filtering and annotating gene sets...")
    es_filtered <- es %>% filter_set(P.DE < 0.05)
    
    # Add GO definitions using GO.db
    map_def <- map_add_set(es_filtered, GO.db, "GOID", "DEFINITION")
    es_annotated <- es_filtered %>% mutate_set(definition = map_def)
    
    # Add reference URLs for elements and sets
    message("Generating reference URLs...")
    es_final <- url_ref(es_annotated)
    
    # ----------------------------------------------------------------------
    # --- Export Results ---
    # ----------------------------------------------------------------------
    message("Exporting final tables...")
    # Export flat elementset table
    final_flat_df <- data.frame_from_elementset(es_final)
    write.csv(final_flat_df, "biocset_results.csv", row.names = FALSE)
    
    # Export set summary table
    final_set_df <- tibble_from_set(es_final)
    write.csv(final_set_df, "biocset_sets_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE":',
        paste0('    BiocSet: ', as.character(packageVersion('BiocSet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocset_de_gsea_pipeline.csv versions.yml
    """
}

workflow BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE.out.tables
    plots    = BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE.out.plots
    objects  = BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE.out.objects
    versions = BIOC_BIOCSET_BIOCSET_DE_GSEA_PIPELINE.out.versions
}
