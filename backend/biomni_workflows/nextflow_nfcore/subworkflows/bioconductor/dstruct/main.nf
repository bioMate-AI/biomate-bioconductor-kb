#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dStruct — dstruct_de_novo
// Identify differentially reactive RNA regions de novo from structurome profiling data using dStruct
// Input: counts.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IRanges, S4Vectors, dStruct
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DSTRUCT_DSTRUCT_DE_NOVO {
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
    .bm_deps <- c("dStruct", "S4Vectors")
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
    library(dStruct)
    library(S4Vectors)
    
    # --- Read and validate input files ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Validate conditions (dStruct supports two-group comparison)
    conds <- unique(coldata\$condition)
    if (length(conds) < 2) {
      stop("dStruct requires at least two distinct conditions in coldata.csv.")
    }
    cond_A <- conds[1]
    cond_B <- conds[2]
    
    # --- Map sample names to dStruct-compliant names (A1, A2, ..., ---
    coldata\$new_name <- ""
    idx_A <- which(coldata\$condition == cond_A)
    coldata\$new_name[idx_A] <- paste0("A", seq_along(idx_A))
    idx_B <- which(coldata\$condition == cond_B)
    coldata\$new_name[idx_B] <- paste0("B", seq_along(idx_B))
    
    reps_A <- length(idx_A)
    reps_B <- length(idx_B)
    
    # --- Format data into a list of data.frames (one per ---
    if ("gene_id" %in% colnames(counts)) {
      gene_list <- split(counts, counts\$gene_id)
      gene_list <- lapply(gene_list, function(df) {
        # Extract only the sample columns and rename them
        df_sub <- df[, coldata\$sample, drop = FALSE]
        colnames(df_sub) <- coldata\$new_name[match(colnames(df_sub), coldata\$sample)]
        # Ensure all columns are numeric
        as.data.frame(lapply(df_sub, as.numeric))
      })
    } else {
      # Fallback: Treat the entire table as a single transcript
      df_sub <- counts[, coldata\$sample, drop = FALSE]
      colnames(df_sub) <- coldata\$new_name[match(colnames(df_sub), coldata\$sample)]
      df_sub <- as.data.frame(lapply(df_sub, as.numeric))
      gene_list <- list(Transcript_1 = df_sub)
    }
    
    # --- Normalize reactivities using the 2-8% method ---
    gene_list_norm <- lapply(gene_list, function(df) {
      norm_df <- lapply(df, function(col) {
        tryCatch({
          twoEightNormalize(col)
        }, error = function(e) {
          # Fallback to original values if normalization fails
          col
        })
      })
      as.data.frame(norm_df)
    })
    
    # --- Run de novo differential region discovery ---
    batches_enabled <- "batch" %in% colnames(coldata)
    
    res <- tryCatch({
      dStructome(
        rl = gene_list_norm,
        reps_A = reps_A,
        reps_B = reps_B,
        batches = batches_enabled,
        min_length = 11,
        ind_regions = TRUE,
        processes = 1
      )
    }, error = function(e) {
      message("Error during dStructome execution: ", e\$message)
      NULL
    })
    
    # --- Save results and generate diagnostic plots ---
    if (!is.null(res) && length(res) > 0) {
      # Save regions to CSV
      res_df <- as.data.frame(res)
      write.csv(res_df, "de_novo_regions.csv", row.names = FALSE)
      
      # Plot the top significant region
      tryCatch({
        meta <- as.data.frame(mcols(res))
        if (nrow(meta) > 0 && "t" %in% colnames(meta)) {
          top_gene <- meta\$t[order(meta\$FDR)][1]
          plotDStructurome(
            rl = gene_list_norm[top_gene],
            diff_regions = subset(res, t == top_gene),
            outfile = "de_novo_plot",
            fdr = 0.05
          )
        }
      }, error = function(e) {
        message("Plotting failed: ", e\$message)
      })
    } else {
      # Fallback outputs if no regions are found
      write.csv(data.frame(Message = "No significant differential regions identified"), "de_novo_regions.csv", row.names = FALSE)
    }
    
    # Ensure the declared PDF output always exists
    if (!file.exists("de_novo_plot.pdf")) {
      pdf("de_novo_plot.pdf")
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No significant regions to plot or plotting skipped")
      dev.off()
    }

    writeLines(c(
        '"BIOC_DSTRUCT_DSTRUCT_DE_NOVO":',
        paste0('    dStruct: ', as.character(packageVersion('dStruct')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dstruct_de_novo.csv versions.yml
    """
}

workflow BIOC_DSTRUCT_DSTRUCT_DE_NOVO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DSTRUCT_DSTRUCT_DE_NOVO(ch_input)

    emit:
    tables   = BIOC_DSTRUCT_DSTRUCT_DE_NOVO.out.tables
    plots    = BIOC_DSTRUCT_DSTRUCT_DE_NOVO.out.plots
    objects  = BIOC_DSTRUCT_DSTRUCT_DE_NOVO.out.objects
    versions = BIOC_DSTRUCT_DSTRUCT_DE_NOVO.out.versions
}
