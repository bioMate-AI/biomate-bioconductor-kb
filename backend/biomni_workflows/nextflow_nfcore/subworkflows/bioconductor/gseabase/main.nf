#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSEABase — gseabase_analysis
// Perform gene set construction, coloring based on expression response, collection grouping, and incidence analysis using GSEABase.
// Input: counts.csv, coldata.csv
// Container: 1.72.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase
// Visualizations: bar plot, image plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABASE_GSEABASE_ANALYSIS {
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
    
    # Load required libraries
    library(GSEABase)
    
    # ----------------------------------------------------------------------
    # --- Load and Preprocess Input Data ---
    # ----------------------------------------------------------------------
    
    # Read expression matrix (counts.csv)
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    
    # Identify gene identifier column and set as row names
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- as.character(counts_df\$gene_id)
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- as.character(counts_df[, 1])
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Read sample metadata (coldata.csv)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata_df)) {
        rownames(coldata_df) <- as.character(coldata_df\$sample)
    } else {
        rownames(coldata_df) <- as.character(coldata_df[, 1])
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts_df), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No common samples found between counts.csv and coldata.csv")
    }
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, drop = FALSE]
    
    # Convert expression data to matrix
    expr_matrix <- as.matrix(counts_df)
    
    # ----------------------------------------------------------------------
    # --- Identify Gene ID Type and Select Top Variable Genes ---
    # ----------------------------------------------------------------------
    
    all_gids <- rownames(expr_matrix)
    
    # Heuristic to determine Gene Identifier Type
    if (all(grepl("^ENS", all_gids))) {
        id_type <- ENSEMBLIdentifier()
    } else if (all(grepl("^[0-9]+\$", all_gids))) {
        id_type <- EntrezIdentifier()
    } else {
        id_type <- NullIdentifier()
    }
    
    # Select top variable genes
    gene_vars <- apply(expr_matrix, 1, var)
    top_n <- min(50, length(gene_vars))
    top_genes <- names(sort(gene_vars, decreasing = TRUE)[1:top_n])
    
    # Create a standard GeneSet
    gs_top <- GeneSet(
        id_type,
        geneIds = top_genes,
        setName = "TopVariableGenes",
        description = "Top most variable genes from expression profiling"
    )
    
    # ----------------------------------------------------------------------
    # --- Construct a GeneColorSet based on Phenotypic Response ---
    # ----------------------------------------------------------------------
    
    # Calculate log fold change between conditions to determine "coloring"
    conds <- coldata_df\$condition
    unique_conds <- unique(conds)
    
    if (length(unique_conds) >= 2) {
        group1_mean <- rowMeans(expr_matrix[top_genes, conds == unique_conds[1], drop = FALSE])
        group2_mean <- rowMeans(expr_matrix[top_genes, conds == unique_conds[2], drop = FALSE])
        lfc <- group2_mean - group1_mean
        
        gene_color <- ifelse(lfc > 0, "Increase", "Decrease")
        pheno_color <- ifelse(lfc > 0, "Up-regulated", "Down-regulated")
    } else {
        gene_color <- rep("NoChange", length(top_genes))
        pheno_color <- rep("Undetermined", length(top_genes))
    }
    
    # Create the GeneColorSet
    gcs <- GeneColorSet(
        id_type,
        setName = "TopVariableColorSet",
        geneIds = top_genes,
        phenotype = "ConditionContrast",
        geneColor = factor(gene_color),
        phenotypeColor = factor(pheno_color)
    )
    
    # ----------------------------------------------------------------------
    # --- Create and Manipulate a GeneSetCollection ---
    # ----------------------------------------------------------------------
    
    # Partition the top genes into 3 arbitrary functional groups to form a collection
    group_count <- 3
    split_groups <- cut(seq_along(top_genes), breaks = group_count, labels = paste0("Pathway_", LETTERS[1:group_count]))
    split_idx <- split(top_genes, split_groups)
    
    gs_list <- lapply(names(split_idx), function(nm) {
        GeneSet(
            id_type,
            geneIds = split_idx[[nm]],
            setName = nm,
            description = paste("Sub-cluster representing", nm)
        )
    })
    
    gsc <- GeneSetCollection(gs_list)
    
    # Compute the incidence matrix (genes vs gene sets)
    inc_mat <- incidence(gsc)
    
    # Write the incidence matrix to CSV
    write.csv(as.matrix(inc_mat), "gsc_incidence.csv", row.names = TRUE)
    
    # ----------------------------------------------------------------------
    # --- Generate Comprehensive Text Report ---
    # ----------------------------------------------------------------------
    
    sink("gseabase_summary.txt")
    cat("=====================================================================\n")
    cat("GSEABase Analysis Pipeline Summary Report\n")
    cat("=====================================================================\n\n")
    
    cat("--- Primary GeneSet Details ---\n")
    cat("Name:        ", setName(gs_top), "\n")
    cat("ID Type:     ", class(geneIdType(gs_top)), "\n")
    cat("Gene Count:  ", length(geneIds(gs_top)), "\n")
    cat("Description: ", description(gs_top), "\n\n")
    
    cat("--- GeneColorSet Details ---\n")
    cat("Name:            ", setName(gcs), "\n")
    cat("Phenotype:       ", phenotype(gcs), "\n")
    cat("Unique Colors:   ", paste(unique(geneColor(gcs)), collapse = ", "), "\n")
    cat("Pheno Responses: ", paste(unique(phenotypeColor(gcs)), collapse = ", "), "\n\n")
    
    cat("--- GeneSetCollection Details ---\n")
    cat("Number of Sets:  ", length(gsc), "\n")
    cat("Set Names:       ", paste(names(gsc), collapse = ", "), "\n")
    cat("Unique Genes:    ", length(unique(unlist(geneIds(gsc)))), "\n\n")
    
    cat("--- Detailed GeneSet Collection Structure ---\n")
    show(gsc)
    sink()
    
    # ----------------------------------------------------------------------
    # --- Visualizations ---
    # ----------------------------------------------------------------------
    
    pdf("gsc_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Gene set sizes in the collection
    sizes <- sapply(gsc, function(x) length(geneIds(x)))
    barplot(
        sizes,
        names.arg = names(gsc),
        col = "skyblue",
        main = "Gene Set Sizes in Collection",
        ylab = "Number of Genes",
        xlab = "Gene Sets",
        las = 1
    )
    
    # Plot 2: Heatmap of the incidence matrix
    if (nrow(inc_mat) > 0 && ncol(inc_mat) > 0) {
        # Convert logical incidence matrix to numeric for plotting
        numeric_inc <- t(as.matrix(inc_mat)) * 1
        image(
            x = 1:nrow(numeric_inc),
            y = 1:ncol(numeric_inc),
            z = numeric_inc,
            axes = FALSE,
            xlab = "Gene Sets",
            ylab = "Genes",
            main = "Gene Set Incidence Matrix",
            col = c("white", "darkblue")
        )
        axis(1, at = 1:nrow(numeric_inc), labels = rownames(numeric_inc), las = 1, cex.axis = 0.8)
        axis(2, at = 1:ncol(numeric_inc), labels = colnames(numeric_inc), las = 2, cex.axis = 0.5)
        box()
    }
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to gsc_incidence.csv, gseabase_summary.txt, and gsc_plots.pdf.\n")

    writeLines(c(
        '"BIOC_GSEABASE_GSEABASE_ANALYSIS":',
        paste0('    GSEABase: ', as.character(packageVersion('GSEABase')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseabase_analysis.csv versions.yml
    """
}

workflow BIOC_GSEABASE_GSEABASE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GSEABASE_GSEABASE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSEABASE_GSEABASE_ANALYSIS.out.tables
    plots    = BIOC_GSEABASE_GSEABASE_ANALYSIS.out.plots
    objects  = BIOC_GSEABASE_GSEABASE_ANALYSIS.out.objects
    versions = BIOC_GSEABASE_GSEABASE_ANALYSIS.out.versions
}
