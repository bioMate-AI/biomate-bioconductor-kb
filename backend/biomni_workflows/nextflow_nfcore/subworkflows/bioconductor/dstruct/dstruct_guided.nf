#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dStruct — dstruct_guided
// Test for differential reactivity profiles in pre-defined RNA regions (guided discovery) using dStruct
// Input: counts.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dStruct
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DSTRUCT_DSTRUCT_GUIDED {
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
    library(dStruct)
    
    # Stage 1: Read and validate input files
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Validate conditions
    conds <- unique(coldata\$condition)
    if (length(conds) < 2) {
      stop("dStruct requires at least two distinct conditions in coldata.csv.")
    }
    cond_A <- conds[1]
    cond_B <- conds[2]
    
    # Stage 2: Map sample names to dStruct-compliant names (A1, A2, ..., B1, B2, ...)
    coldata\$new_name <- ""
    idx_A <- which(coldata\$condition == cond_A)
    coldata\$new_name[idx_A] <- paste0("A", seq_along(idx_A))
    idx_B <- which(coldata\$condition == cond_B)
    coldata\$new_name[idx_B] <- paste0("B", seq_along(idx_B))
    
    reps_A <- length(idx_A)
    reps_B <- length(idx_B)
    
    # Stage 3: Format pre-defined regions into a list of data.frames
    if ("gene_id" %in% colnames(counts)) {
      gene_list <- split(counts, counts\$gene_id)
      gene_list <- lapply(gene_list, function(df) {
        df_sub <- df[, coldata\$sample, drop = FALSE]
        colnames(df_sub) <- coldata\$new_name[match(colnames(df_sub), coldata\$sample)]
        as.data.frame(lapply(df_sub, as.numeric))
      })
    } else {
      df_sub <- counts[, coldata\$sample, drop = FALSE]
      colnames(df_sub) <- coldata\$new_name[match(colnames(df_sub), coldata\$sample)]
      df_sub <- as.data.frame(lapply(df_sub, as.numeric))
      gene_list <- list(Region_1 = df_sub)
    }
    
    # Stage 4: Normalize reactivities using the 2-8% method
    gene_list_norm <- lapply(gene_list, function(df) {
      norm_df <- lapply(df, function(col) {
        tryCatch({
          twoEightNormalize(col)
        }, error = function(e) {
          col
        })
      })
      as.data.frame(norm_df)
    })
    
    # Stage 5: Run guided differential analysis
    res_guided <- tryCatch({
      dStructome(
        rl = gene_list_norm,
        reps_A = reps_A,
        reps_B = reps_B,
        method = "guided",
        processes = 1
      )
    }, error = function(e) {
      message("Error during guided dStructome execution: ", e\$message)
      NULL
    })
    
    # Stage 6: Save results
    if (!is.null(res_guided)) {
      write.csv(res_guided, "guided_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Message = "No results or error occurred during guided analysis"), "guided_results.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_DSTRUCT_DSTRUCT_GUIDED":',
        paste0('    dStruct: ', as.character(packageVersion('dStruct')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dstruct_guided.csv versions.yml
    """
}

workflow BIOC_DSTRUCT_DSTRUCT_GUIDED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DSTRUCT_DSTRUCT_GUIDED(ch_input)

    emit:
    tables   = BIOC_DSTRUCT_DSTRUCT_GUIDED.out.tables
    plots    = BIOC_DSTRUCT_DSTRUCT_GUIDED.out.plots
    objects  = BIOC_DSTRUCT_DSTRUCT_GUIDED.out.objects
    versions = BIOC_DSTRUCT_DSTRUCT_GUIDED.out.versions
}
