#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lea — population_structure_and_imputation
// Analyze population genetic structure, identify genetic clusters, perform population differentiation tests, and impute missing genotypes.
// Input: genotypes.lfmm, genotypes.geno, genoM.lfmm
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: knitr, LEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: PCA plot, scree plot
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0"

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
    .bm_deps <- c("knitr", "LEA")
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
    
    # Load required library
    library(LEA)
    
    # Verify that the required input files exist in the working directory
    required_files <- c("genotypes.lfmm", "genotypes.geno", "genoM.lfmm")
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing in the working directory:", f))
      }
    }
    
    # Define colors for ancestry plotting
    my.colors <- c("tomato", "lightblue", "olivedrab", "gold")
    
    # ==========================================
    # --- Principal Component Analysis (PCA) ---
    # ==========================================
    message("Running PCA...")
    pc = pca("genotypes.lfmm", scale = TRUE)
    tw = tracy.widom(pc)
    
    # Save PCA results
    saveRDS(pc, "pca_object.rds")
    saveRDS(tw, "tracy_widom_results.rds")
    
    # Plot the percentage of variance explained
    pdf("pca_screeplot.pdf", width = 6, height = 6)
    plot(tw\$percentage, pch = 19, col = "darkblue", cex = .8)
    dev.off()
    
    # ==========================================
    # Stage 2 & 3: sNMF and Cross-Entropy Evaluation
    # ==========================================
    message("Running sNMF for K = 1 to 10...")
    project = snmf("genotypes.geno", K = 1:10, entropy = TRUE, repetitions = 10, project = "new")
    
    # Save sNMF project object
    saveRDS(project, "snmf_project.rds")
    
    # Plot cross-entropy criterion
    pdf("snmf_cross_entropy.pdf", width = 6, height = 6)
    plot(project, col = "blue", pch = 19, cex = 1.2)
    dev.off()
    
    # ==========================================
    # --- Visualize Ancestry Proportions (Q-matrix) ---
    # ==========================================
    message("Visualizing ancestry proportions for K = 4...")
    best = which.min(cross.entropy(project, K = 4))
    
    pdf("ancestry_barchart.pdf", width = 10, height = 6)
    barchart(project, K = 4, run = best, border = NA, space = 0, col = my.colors, xlab = "Individuals", ylab = "Ancestry proportions", main = "Ancestry matrix") -> bp
    axis(1, at = 1:length(bp\$order), labels = bp\$order, las=1, cex.axis = .4)
    dev.off()
    
    # Export Q-matrix to CSV
    q_matrix <- Q(project, K = 4, run = best)
    write.csv(q_matrix, "ancestry_proportions_K4.csv", row.names = FALSE)
    
    # ==========================================
    # --- Population Differentiation Tests ---
    # ==========================================
    message("Conducting population differentiation tests...")
    p = snmf.pvalues(project, entropy = TRUE, ploidy = 2, K = 4)
    pvalues = p\$pvalues
    
    # Save p-values to CSV
    write.csv(data.frame(Locus = 1:length(pvalues), Pvalue = pvalues), "snmf_pvalues.csv", row.names = FALSE)
    
    # Plot p-values histogram and Manhattan-style plot
    pdf("pvalues_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2,1))
    hist(pvalues, col = "orange")
    plot(-log10(pvalues), pch = 19, col = "blue", cex = .5)
    dev.off()
    
    # ==========================================
    # --- Missing Genotype Imputation ---
    # ==========================================
    message("Running sNMF on dataset with missing values...")
    project.missing = snmf("genoM.lfmm", K = 4, entropy = TRUE, repetitions = 10, project = "new")
    
    # Save missing project object
    saveRDS(project.missing, "snmf_project_missing.rds")
    
    # Select the best run and impute missing genotypes
    best = which.min(cross.entropy(project.missing, K = 4))
    impute(project.missing, "genoM.lfmm", method = 'mode', K = 4, run = best)
    
    # Read and save the imputed genotype matrix
    dat.imp = read.lfmm("genoM.lfmm_imputed.lfmm")
    saveRDS(dat.imp, "imputed_genotypes_matrix.rds")
    
    message("Pipeline completed successfully. All outputs saved to the working directory.")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION":',
        paste0('        lea: ', as.character(packageVersion("lea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_population_structure_and_imputation.csv versions.yml
    """
}

workflow BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.lfmm, genotypes.geno, genoM.lfmm ] ]

    main:
    BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.tables
    plots    = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.plots
    objects  = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.objects
    versions = BIOC_LEA_POPULATION_STRUCTURE_AND_IMPUTATION.out.versions
}
