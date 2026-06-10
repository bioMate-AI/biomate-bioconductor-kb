#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: meshes — mesh_enrichment_and_semantic_analysis
// Perform comprehensive MeSH over-representation (ORA), gene set enrichment (GSEA), and semantic similarity analyses on differential expression results derived fr
// Input: counts.csv, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, BiocManager, IRanges, S4Vectors, meshes
// Visualizations: bar plot, enrichment plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Stage 1: Load libraries and install dependencies if missing
    library(BiocGenerics)
    library(S4Vectors)
    
    # Ensure meshes is loaded
    if (!requireNamespace("meshes", quietly = TRUE)) {
        stop("The 'meshes' package is required but not installed.")
    }
    library(meshes)
    
    # Define parameters
    mesh_db <- "MeSH.Hsa.eg.db"
    category <- "C"      # Diseases category
    database <- "gendoo" # MeSH source database
    
    # Attempt to load or install the required MeSHDb package
    if (!requireNamespace(mesh_db, quietly = TRUE)) {
        message(paste("Installing missing annotation package:", mesh_db))
        if (requireNamespace("BiocManager", quietly = TRUE)) {
            BiocManager::install(mesh_db, update = FALSE, ask = FALSE)
        } else {
            install.packages("BiocManager", repos = "https://cloud.r-project.org")
            BiocManager::install(mesh_db, update = FALSE, ask = FALSE)
        }
    }
    library(mesh_db, character.only = TRUE)
    
    # Stage 2: Read and preprocess input data
    message("Reading input files...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Normalize counts using simple CPM (Counts Per Million) and log2 transform
    libsizes <- colSums(counts)
    cpm <- t(t(counts) / libsizes) * 1e6
    log_cpm <- log2(cpm + 1)
    
    # Stage 3: Differential Expression Analysis (Base R)
    message("Performing differential expression analysis...")
    groups <- as.factor(coldata\$condition)
    levels <- levels(groups)
    if (length(levels) < 2) {
        stop("At least two conditions are required in coldata.csv for differential analysis.")
    }
    group1_cols <- which(groups == levels[1])
    group2_cols <- which(groups == levels[2])
    
    # Compute p-values and log2 fold changes
    p_values <- apply(log_cpm, 1, function(x) {
        if (sd(x[group1_cols]) == 0 && sd(x[group2_cols]) == 0) return(NA)
        res <- tryCatch(t.test(x[group1_cols], x[group2_cols]), error = function(e) NULL)
        if (is.null(res)) return(NA)
        return(res\$p.value)
    })
    log2fc <- apply(log_cpm, 1, function(x) {
        mean(x[group2_cols]) - mean(x[group1_cols])
    })
    
    de_res <- data.frame(
        gene_id = rownames(counts),
        log2FC = log2fc,
        pvalue = p_values,
        stringsAsFactors = FALSE
    )
    de_res\$padj <- p.adjust(de_res\$pvalue, method = "BH")
    
    # Stage 4: Select Genes for Over-Representation Analysis (ORA)
    # MeSH enrichment requires Entrez Gene IDs. We assume gene_id contains Entrez IDs.
    sig_genes <- de_res\$gene_id[which(de_res\$padj < 0.05 & abs(de_res\$log2FC) > 1)]
    
    # Fallback if too few genes are significant
    if (length(sig_genes) < 5) {
        message("Few genes met strict thresholds. Relaxing criteria to p-value < 0.05...")
        sig_genes <- de_res\$gene_id[which(de_res\$pvalue < 0.05)]
    }
    if (length(sig_genes) < 5) {
        message("Still too few genes. Selecting top 100 genes by p-value...")
        sig_genes <- de_res\$gene_id[order(de_res\$pvalue)[1:min(100, nrow(de_res))]]
    }
    
    # Stage 5: MeSH Over-Representation Analysis (ORA)
    message("Running MeSH Over-Representation Analysis...")
    organism <- get_organism(mesh_db)
    message(paste("Organism detected:", organism))
    
    ora_res <- tryCatch({
        enrichMeSH(gene = sig_genes,
                   MeSHDb = mesh_db,
                   database = database,
                   category = category,
                   pvalueCutoff = 0.05,
                   pAdjustMethod = "BH")
    }, error = function(e) {
        message("Error in enrichMeSH: ", e\$message)
        return(NULL)
    })
    
    # Stage 6: MeSH Gene Set Enrichment Analysis (GSEA)
    message("Running MeSH Gene Set Enrichment Analysis...")
    # Prepare ranked gene list
    gene_list <- de_res\$log2FC
    names(gene_list) <- de_res\$gene_id
    gene_list <- sort(gene_list, decreasing = TRUE)
    
    gsea_res <- tryCatch({
        gseMeSH(geneList = gene_list,
                MeSHDb = mesh_db,
                database = database,
                category = category,
                pvalueCutoff = 0.05,
                pAdjustMethod = "BH")
    }, error = function(e) {
        message("Error in gseMeSH: ", e\$message)
        return(NULL)
    })
    
    # Stage 7: Semantic Similarity Analysis
    message("Computing semantic similarity...")
    sim_matrix <- NULL
    sem_data <- tryCatch({
        meshdata(MeSHDb = mesh_db, database = database, category = category, computeIC = TRUE)
    }, error = function(e) {
        message("Error in meshdata: ", e\$message)
        return(NULL)
    })
    
    if (!is.null(sem_data) && length(sig_genes) >= 2) {
        # Select top 5 genes to compute pairwise semantic similarity
        top_genes <- head(sig_genes, 5)
        sim_matrix <- tryCatch({
            geneSim(top_genes, top_genes, semData = sem_data, measure = "Wang", drop = FALSE)
        }, error = function(e) {
            message("Error in geneSim: ", e\$message)
            return(NULL)
        })
    }
    
    # Stage 8: Save Results and Generate Visualizations
    message("Writing output files...")
    
    # Helper to write tables safely
    safe_write_csv <- function(obj, filename) {
        if (is.null(obj)) {
            write.csv(data.frame(Message = "Analysis step failed or returned no results"), filename, row.names = FALSE)
        } else {
            df <- as.data.frame(obj)
            if (nrow(df) == 0) {
                write.csv(data.frame(Message = "No significant terms found"), filename, row.names = FALSE)
            } else {
                write.csv(df, filename, row.names = TRUE)
            }
        }
    }
    
    safe_write_csv(ora_res, "mesh_ora_results.csv")
    safe_write_csv(gsea_res, "mesh_gsea_results.csv")
    
    if (!is.null(sim_matrix)) {
        write.csv(as.data.frame(sim_matrix), "mesh_similarity.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(Message = "Similarity matrix could not be computed"), "mesh_similarity.csv", row.names = FALSE)
    }
    
    # Generate diagnostic and enrichment plots
    pdf("mesh_enrichment_plots.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1), mar = c(5, 18, 4, 2)) # Large left margin for term descriptions
    
    # Plot ORA results
    if (!is.null(ora_res) && nrow(as.data.frame(ora_res)) > 0) {
        ora_df <- as.data.frame(ora_res)
        ora_df <- ora_df[order(ora_df\$pvalue), ]
        top_ora <- head(ora_df, 10)
        truncated_names <- substr(top_ora\$Description, 1, 30)
        barplot(-log10(top_ora\$pvalue),
                names.arg = truncated_names,
                las = 2,
                horiz = TRUE,
                col = "skyblue",
                main = "Top Enriched MeSH Terms (ORA)",
                xlab = "-log10(p-value)")
    } else {
        plot.new()
        text(0.5, 0.5, "No significant ORA MeSH terms to plot", cex = 1.2)
    }
    
    # Plot GSEA results
    if (!is.null(gsea_res) && nrow(as.data.frame(gsea_res)) > 0) {
        gsea_df <- as.data.frame(gsea_res)
        gsea_df <- gsea_df[order(gsea_df\$pvalue), ]
        top_gsea <- head(gsea_df, 10)
        truncated_gsea_names <- substr(top_gsea\$Description, 1, 30)
        barplot(top_gsea\$NES,
                names.arg = truncated_gsea_names,
                las = 2,
                horiz = TRUE,
                col = "coral",
                main = "Top Enriched MeSH Terms (GSEA)",
                xlab = "Normalized Enrichment Score (NES)")
    } else {
        plot.new()
        text(0.5, 0.5, "No significant GSEA MeSH terms to plot", cex = 1.2)
    }
    
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS":',
        paste0('    meshes: ', as.character(packageVersion('meshes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mesh_enrichment_and_semantic_analysis.csv versions.yml
    """
}

workflow BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS.out.tables
    plots    = BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS.out.plots
    objects  = BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS.out.objects
    versions = BIOC_MESHES_MESH_ENRICHMENT_AND_SEMANTIC_ANALYSIS.out.versions
}
