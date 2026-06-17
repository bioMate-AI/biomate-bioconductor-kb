#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — sva_sequencing
// Estimate latent variables in count-based sequencing data using svaseq, optionally incorporating negative control probes (supervised SVA).
// Input: raw_counts.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sva
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-count genes
//  * 2. [Input & Preparation] Define null and alternative model matrices
//  * 3. [Core Analysis] Run svaseq to estimate surrogate variables
//  * 4. [Core Analysis] Optionally run supervised svaseq by providing control probes

nextflow.enable.dsl = 2

process BIOC_SVA_SVA_SEQUENCING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("sva")
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
        
        library(sva)
        
        # Read user input files
        zfGenes <- read.csv("raw_counts.csv", row.names = 1, check.names = FALSE)
        metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
        
        # Extract group variable from metadata
        if ("group" %in% colnames(metadata)) {
          group = as.factor(metadata\$group)
        } else {
          group = as.factor(metadata[, 1])
        }
        
        # 1. Filter low-count genes
        filter = apply(zfGenes, 1, function(x) length(x[x>5])>=2)
        filtered = zfGenes[filter,]
        dat0 = as.matrix(filtered)
        
        # 2. Define null and alternative model matrices
        mod1 = model.matrix(~group)
        mod0 = cbind(mod1[,1])
        
        # Estimate the number of surrogate variables dynamically
        n.sv = num.sv(dat0, mod1, method="leek")
        
        # 3. Run svaseq to estimate surrogate variables (unsupervised)
        svseq_obj = svaseq(dat0, mod1, mod0, n.sv=n.sv)
        svseq = svseq_obj\$sv
        
        # 4. Run supervised svaseq by providing empirical control probes
        # Using the posterior probability that a gene is NOT affected by the group variable
        controls = 1 - svseq_obj\$pprob.b
        sup_svseq = svaseq(dat0, mod1, mod0, controls=controls, n.sv=n.sv)\$sv
        
        # Write outputs
        write.csv(svseq, "unsupervised_svaseq.csv", row.names = FALSE)
        write.csv(sup_svseq, "supervised_svaseq.csv", row.names = FALSE)
        
        saveRDS(list(
          unsupervised_sv = svseq,
          supervised_sv = sup_svseq,
          filtered_data = dat0,
          controls = controls
        ), "svaseq_output.rds")
        
        pdf("svaseq_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        plot(svseq, pch=19, col="blue", main="Unsupervised svaseq")
        plot(sup_svseq, svseq, pch=19, col="blue", main="Supervised vs Unsupervised")
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # batch-effect correction — declarative pass via corrected-output presence
    # (kBET acceptance metric is a future per-workflow follow-on).
    .bec_artifacts <- list.files(".", pattern = "(?i)(corrected|batch|combat|harmony|mnn).*\\.(rds|csv|h5ad)\$")
    .bec_passes <- length(.bec_artifacts) > 0
    .gates_by_label[["batch-effect correction"]] <- list(
      gate_row = "bioc_batch_effect_correction",
      metric_name = "batch_corrected_artifacts",
      metric_value = length(.bec_artifacts),
      passes = .bec_passes,
      status = if (.bec_passes) "computed (declarative; kBET acceptance pending)"
               else "not_computed (no batch-corrected artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SVA_SVA_SEQUENCING",
      domain  = "bioconductor",
      declared_qc_steps = c("low-count filtering", "batch-effect correction"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SVA_SVA_SEQUENCING":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sva_sequencing.csv versions.yml
    """
}

workflow BIOC_SVA_SVA_SEQUENCING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv, sample_metadata.csv ] ]

    main:
    BIOC_SVA_SVA_SEQUENCING(ch_input)

    emit:
    tables   = BIOC_SVA_SVA_SEQUENCING.out.tables
    plots    = BIOC_SVA_SVA_SEQUENCING.out.plots
    objects  = BIOC_SVA_SVA_SEQUENCING.out.objects
    versions = BIOC_SVA_SVA_SEQUENCING.out.versions
}
