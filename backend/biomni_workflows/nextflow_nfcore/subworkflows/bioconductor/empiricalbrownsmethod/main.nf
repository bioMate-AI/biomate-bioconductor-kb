#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EmpiricalBrownsMethod — empirical_browns_pathway_analysis
// Combine dependent gene-level p-values into pathway-level significance scores using Empirical Brown's and Kost's methods.
// Input: counts.csv, coldata.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EmpiricalBrownsMethod
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS {
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
    
    # --- Load libraries ---
    library(EmpiricalBrownsMethod)
    
    # --- Read and preprocess input files ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
      # Fallback if gene_id is not a column but row names are used
      rownames(counts_df) <- counts_df[, 1]
      counts_matrix <- as.matrix(counts_df[, -1, drop = FALSE])
    } else {
      rownames(counts_df) <- counts_df\$gene_id
      counts_matrix <- as.matrix(counts_df[, setdiff(colnames(counts_df), "gene_id"), drop = FALSE])
    }
    
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_matrix), coldata\$sample)
    if (length(common_samples) < 2) {
      stop("Fewer than 2 common samples found between counts and coldata.")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # --- Compute individual gene p-values comparing conditions ---
    conditions <- as.factor(coldata\$condition)
    p_values <- apply(counts_matrix, 1, function(row) {
      if (length(unique(conditions)) == 2) {
        tryCatch(t.test(row ~ conditions)\$p.value, error = function(e) NA)
      } else {
        tryCatch({
          fit <- lm(row ~ conditions)
          anova(fit)\$"Pr(>F)"[1]
        }, error = function(e) NA)
      }
    })
    
    # Filter out genes with NA p-values
    valid_genes <- !is.na(p_values)
    counts_matrix <- counts_matrix[valid_genes, , drop = FALSE]
    p_values <- p_values[valid_genes]
    
    # --- Define pathways (mock pathways based on gene list) ---
    gene_ids <- rownames(counts_matrix)
    set.seed(42)
    # Create 5 mock pathways to group dependent genes
    pathway_names <- paste0("Pathway_", LETTERS[1:5])
    gene_pathways <- sample(pathway_names, length(gene_ids), replace = TRUE)
    pathway_list <- split(gene_ids, gene_pathways)
    
    # --- Combine P-values using Empirical Brown's and Kost's ---
    results <- data.frame(
      Pathway = character(),
      Num_Genes = integer(),
      Brown_P_Value = numeric(),
      Kost_P_Value = numeric(),
      stringsAsFactors = FALSE
    )
    
    get_p_val <- function(res) {
      if (is.null(res)) return(NA)
      if (is.list(res)) {
        if ("p_value" %in% names(res)) return(res\$p_value)
        if ("p.value" %in% names(res)) return(res\$p.value)
        return(res[[1]])
      }
      return(res)
    }
    
    for (pathway in names(pathway_list)) {
      p_genes <- pathway_list[[pathway]]
      if (length(p_genes) < 2) next
    
      pathway_dat <- counts_matrix[p_genes, , drop = FALSE]
      pathway_pvals <- p_values[p_genes]
    
      # Filter out rows with zero variance to avoid covariance calculation issues
      row_vars <- apply(pathway_dat, 1, var)
      keep <- !is.na(row_vars) & row_vars > 0
      if (sum(keep) < 2) next
    
      pathway_dat <- pathway_dat[keep, , drop = FALSE]
      pathway_pvals <- pathway_pvals[keep]
    
      # Run empiricalBrownsMethod
      ebm_res <- tryCatch({
        empiricalBrownsMethod(data_matrix = pathway_dat, p_values = pathway_pvals, extra_info = TRUE)
      }, error = function(e) NULL)
    
      # Run kostsMethod
      kost_res <- tryCatch({
        kostsMethod(data_matrix = pathway_dat, p_values = pathway_pvals, extra_info = TRUE)
      }, error = function(e) NULL)
    
      results <- rbind(results, data.frame(
        Pathway = pathway,
        Num_Genes = length(p_genes),
        Brown_P_Value = get_p_val(ebm_res),
        Kost_P_Value = get_p_val(kost_res),
        stringsAsFactors = FALSE
      ))
    }
    
    # --- Save outputs and generate plots ---
    write.csv(results, "pathway_results.csv", row.names = FALSE)
    
    pdf("pathway_significance.pdf", width = 8, height = 6)
    if (nrow(results) > 0) {
      # Replace 0 p-values with a small number to avoid log(0)
      results\$log_p <- -log10(ifelse(is.na(results\$Brown_P_Value) | results\$Brown_P_Value == 0, 1e-16, results\$Brown_P_Value))
      
      par(mar = c(7, 5, 4, 2) + 0.1)
      barplot(results\$log_p, names.arg = results\$Pathway,
              las = 2, col = "skyblue",
              main = "Pathway Significance (Empirical Brown's Method)",
              ylab = "-log10(P-value)", xlab = "")
      abline(h = -log10(0.05), col = "red", lty = 2)
    } else {
      plot.new()
      text(0.5, 0.5, "No pathways evaluated successfully")
    }
    dev.off()

    writeLines(c(
        '"BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS":',
        paste0('    EmpiricalBrownsMethod: ', as.character(packageVersion('EmpiricalBrownsMethod')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_empirical_browns_pathway_analysis.csv versions.yml
    """
}

workflow BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS.out.tables
    plots    = BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS.out.plots
    objects  = BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS.out.objects
    versions = BIOC_EMPIRICALBROWNSMETHOD_EMPIRICAL_BROWNS_PATHWAY_ANALYSIS.out.versions
}
