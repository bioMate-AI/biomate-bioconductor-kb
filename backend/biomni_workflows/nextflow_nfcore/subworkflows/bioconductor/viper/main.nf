#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: viper — msviper_analysis
// Identify master regulators associated with a phenotypic transition by performing multi-sample msVIPER analysis with null models, leading-edge analysis, shadow a
// Input: dset, bcellaracne.adj
// Container: quay.io/biocontainers/bioconductor-viper:1.44.0--r45hdfd78af_0
// R packages: viper
// Bioconductor: 3.20 | R: 4.4
// Requires: viper
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate regulon object from ARACNe output
//  * 2. [Core Analysis] Generate gene expression signature (GES) using Student's t-test
//  * 3. [Core Analysis] Generate null model by sample permutations
//  * 4. [Core Analysis] Run msVIPER analysis
//  * 5. [Core Analysis] Perform leading-edge analysis
//  * 6. [Core Analysis] Run bootstrap msVIPER
//  * 7. [Core Analysis] Perform shadow analysis
//  * 8. [Core Analysis] Perform synergy analysis

nextflow.enable.dsl = 2

process BIOC_VIPER_MSVIPER_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("viper")
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
    library(viper)
    
    # ==========================================
    # 1. Generate regulon object from ARACNe output
    # ==========================================
    adjfile <- "bcellaracne.adj"
    
    # Robustly load the user-provided dset object
    if (file.exists("dset")) {
      dset <- readRDS("dset")
    } else if (file.exists("dset.rds")) {
      dset <- readRDS("dset.rds")
    } else {
      stop("Error: 'dset' file (ExpressionSet or matrix) not found in the working directory.")
    }
    
    # Convert to matrix to handle both ExpressionSet and matrix inputs uniformly
    if (inherits(dset, "ExpressionSet")) {
      expr_mat <- exprs(dset)
    } else {
      expr_mat <- as.matrix(dset)
    }
    
    # Split the matrix into 'test' and 'reference' sets (first half vs second half)
    # This avoids hardcoding demo-specific metadata columns or group labels
    n_samples <- ncol(expr_mat)
    half <- floor(n_samples / 2)
    mat_test <- expr_mat[, 1:half, drop = FALSE]
    mat_ref <- expr_mat[, (half + 1):n_samples, drop = FALSE]
    
    # Generate regulon
    regul <- aracne2regulon(adjfile, dset, verbose = FALSE)
    print(regul)
    
    # Assign to 'regulon' to match the documented code's variable name
    regulon <- regul
    
    # ==========================================
    # 2. Generate gene expression signature (GES)
    # ==========================================
    signature <- rowTtest(mat_test, mat_ref)
    signature <- (qnorm(signature\$p.value/2, lower.tail = FALSE) * 
                    sign(signature\$statistic))[, 1]
    
    # ==========================================
    # 3. Generate null model by sample permutations
    # ==========================================
    nullmodel <- ttestNull(mat_test, mat_ref, per = 1000,
                           repos = TRUE, verbose = FALSE)
    
    # ==========================================
    # 4. Run msVIPER analysis
    # ==========================================
    mrs <- msviper(signature, regulon, nullmodel, verbose = FALSE)
    
    # Save summary and plot
    mrs_summary <- summary(mrs)
    write.csv(mrs_summary, "msviper_summary.csv", row.names = TRUE)
    
    pdf("msviper_plot.pdf")
    plot(mrs, cex = .7)
    dev.off()
    
    # ==========================================
    # 5. Perform leading-edge analysis
    # ==========================================
    mrs <- ledge(mrs)
    
    mrs_ledge_summary <- summary(mrs)
    write.csv(mrs_ledge_summary, "msviper_ledge_summary.csv", row.names = TRUE)
    
    # ==========================================
    # 6. Run bootstrap msVIPER
    # ==========================================
    signature <- bootstrapTtest(mat_test, mat_ref, verbose = FALSE)
    mrs <- msviper(signature, regulon, nullmodel, verbose = FALSE)
    mrs <- bootstrapmsviper(mrs, "mode")
    
    pdf("bootstrap_msviper_plot.pdf")
    plot(mrs, cex = .7)
    dev.off()
    
    # ==========================================
    # 7. Perform shadow analysis
    # ==========================================
    mrshadow <- shadow(mrs, regulators = 25, verbose = FALSE)
    
    shadow_summary <- summary(mrshadow)
    if (is.list(shadow_summary)) {
      if (!is.null(shadow_summary\$msviper.results)) {
        write.csv(shadow_summary\$msviper.results, "shadow_msviper_results.csv", row.names = TRUE)
      }
      if (!is.null(shadow_summary\$Shadow.pairs)) {
        writeLines(shadow_summary\$Shadow.pairs, "shadow_pairs.txt")
      }
    }
    
    # ==========================================
    # 8. Perform synergy analysis
    # ==========================================
    mrs <- msviperCombinatorial(mrs, regulators = 25, verbose = FALSE)
    mrs <- msviperSynergy(mrs, verbose = FALSE)
    
    synergy_summary <- summary(mrs)
    write.csv(synergy_summary, "msviper_synergy_summary.csv", row.names = TRUE)
    
    pdf("synergy_msviper_plot.pdf")
    plot(mrs, 25, cex = .7)
    dev.off()
    
    # Save final R objects for downstream analysis
    saveRDS(mrs, "msviper_final_object.rds")
    saveRDS(mrshadow, "msviper_shadow_object.rds")

    writeLines(c(
        '"BIOC_VIPER_MSVIPER_ANALYSIS":',
        paste0('    viper: ', as.character(packageVersion('viper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msviper_analysis.csv versions.yml
    """
}

workflow BIOC_VIPER_MSVIPER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dset, bcellaracne.adj ] ]

    main:
    BIOC_VIPER_MSVIPER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VIPER_MSVIPER_ANALYSIS.out.tables
    plots    = BIOC_VIPER_MSVIPER_ANALYSIS.out.plots
    objects  = BIOC_VIPER_MSVIPER_ANALYSIS.out.objects
    versions = BIOC_VIPER_MSVIPER_ANALYSIS.out.versions
}
