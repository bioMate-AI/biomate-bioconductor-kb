#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zenith — zenith_gsa_workflow
// Perform gene set enrichment analysis on differential expression results from a linear mixed model fit with dream and visualize the results.
// Input: geneCounts, df_metadata
// Container: quay.io/biocontainers/bioconductor-zenith:1.12.0--r45hdfd78af_0
// R packages: edgeR, EnrichmentBrowser, kableExtra, knitr, tweeDEseqCountData, variancePartition, zenith
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR, kableExtra, tweeDEseqCountData, variancePartition, zenith
// Visualizations: plot (ggplot/base)
// QC: filter low-expression genes, TMM normalization, voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-expressed genes using edgeR::filterByExpr
//  * 2. [Core Analysis] Compute library size normalization using edgeR::calcNormFactors
//  * 3. [Core Analysis] Estimate precision weights using variancePartition::voomWithDreamWeights
//  * 4. [Core Analysis] Fit linear (mixed) model using variancePartition::dream and limma::eBayes
//  * 5. [Input & Preparation] Load gene sets using get_MSigDB or get_GeneOntology
//  * 6. [Core Analysis] Run zenith gene set analysis using zenith_gsa
//  * 7. [Visualization & Output] Plot results using plotZenithResults

nextflow.enable.dsl = 2

process BIOC_ZENITH_ZENITH_GSA_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("edgeR", "EnrichmentBrowser", "kableExtra", "knitr", "tweeDEseqCountData", "variancePartition", "zenith")
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
        
        # Load packages
        library(zenith)
        library(edgeR)
        library(variancePartition)
        library(tweeDEseqCountData)
        library(kableExtra)
        
        # Load RNA-seq data from user input files
        if (file.exists("geneCounts.rds")) {
          geneCounts = readRDS("geneCounts.rds")
        } else if (file.exists("geneCounts.csv")) {
          geneCounts = as.matrix(read.csv("geneCounts.csv", row.names=1, check.names=FALSE))
        } else if (file.exists("geneCounts.tsv")) {
          geneCounts = as.matrix(read.delim("geneCounts.tsv", row.names=1, check.names=FALSE))
        } else {
          stop("Error: geneCounts file not found in the working directory (expected geneCounts.rds, geneCounts.csv, or geneCounts.tsv).")
        }
        
        if (file.exists("df_metadata.rds")) {
          df_metadata = readRDS("df_metadata.rds")
        } else if (file.exists("df_metadata.csv")) {
          df_metadata = read.csv("df_metadata.csv", row.names=1, check.names=FALSE)
        } else if (file.exists("df_metadata.tsv")) {
          df_metadata = read.delim("df_metadata.tsv", row.names=1, check.names=FALSE)
        } else {
          stop("Error: df_metadata file not found in the working directory (expected df_metadata.rds, df_metadata.csv, or df_metadata.tsv).")
        }
        
        # Filter genes
        # Note this is low coverage data, so just use as code example
        covariate = colnames(df_metadata)[1]
        form = as.formula(paste0("~ `", covariate, "`"))
        dsgn = model.matrix(form, df_metadata)
        keep = filterByExpr(geneCounts, dsgn, min.count=5)
        
        # Compute library size normalization
        dge = DGEList(counts = geneCounts[keep,])
        dge = calcNormFactors(dge)
        
        # Estimate precision weights using voom
        vobj = voomWithDreamWeights(dge, form, df_metadata)
        
        # Apply dream analysis
        fit = dream(vobj, form, df_metadata)
        fit = eBayes(fit)
        
        # Load get_MSigDB database, Hallmark genes
        # use gene 'SYMBOL', or 'ENSEMBL' id
        # use get_GeneOntology() to load Gene Ontology
        msdb.gs = get_MSigDB("H", to="ENSEMBL")
           
        # Run zenith analysis, and specific which coefficient to evaluate
        coef_name = colnames(dsgn)[2]
        res.gsa = zenith_gsa(fit, msdb.gs, coef_name, progressbar=FALSE )
        
        # Show top gene sets: head(res.gsa)
        kable_res = kable_styling(kable(head(res.gsa), row.names=FALSE))
        
        # Save tabular results
        write.csv(res.gsa, "zenith_results.csv", row.names=FALSE)
        saveRDS(res.gsa, "zenith_results.rds")
        writeLines(as.character(kable_res), "top_genesets.html")
        
        # for each cell type select 3 genesets with largest t-statistic
        # and 1 geneset with the lowest
        # Grey boxes indicate the gene set could not be evaluted because
        #    to few genes were represented
        pdf("zenith_results_plot.pdf", width=10, height=8)
        print(plotZenithResults(res.gsa))
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # filter low-expression genes — alias of low-count filtering metric
    # (Chen 2016 F1000 edgeR filterByExpr semantics).
    .fleg_kept <- NA_real_; .fleg_files <- character(0)
    for (.fleg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .fleg_obj <- tryCatch(readRDS(.fleg_rds), error = function(e) NULL)
      .fleg_mat <- if (is.matrix(.fleg_obj) || is.data.frame(.fleg_obj)) .fleg_obj else NULL
      if (!is.null(.fleg_mat) && nrow(.fleg_mat) > 100) {
        .fleg_m <- suppressWarnings(as.matrix(.fleg_mat))
        .fleg_rowmed <- suppressWarnings(apply(.fleg_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
        .fleg_kept <- sum(is.finite(.fleg_rowmed) & .fleg_rowmed >= 1) / nrow(.fleg_m)
        .fleg_files <- c(.fleg_files, .fleg_rds); break
      }
    }
    .gates_by_label[["filter low-expression genes"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = if (is.finite(.fleg_kept)) round(.fleg_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.fleg_kept) && .fleg_kept >= 0.3 && .fleg_kept <= 0.6),
      status = if (is.finite(.fleg_kept)) paste0("computed (median count >= 1 rows / total)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
    )

    # voom — limma EList\$weights present, range > 0 (Law 2014 GB).
    .voom_w_range <- NA_real_
    for (.voom_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .voom_obj <- tryCatch(readRDS(.voom_rds), error = function(e) NULL)
      if (!is.null(.voom_obj) && inherits(.voom_obj, "EList")) {
        .voom_w <- tryCatch(.voom_obj\$weights, error = function(e) NULL)
        if (!is.null(.voom_w) && length(.voom_w) > 0) {
          .voom_w_range <- round(diff(range(.voom_w, na.rm = TRUE)), 4); break
        }
      }
    }
    .gates_by_label[["voom mean-variance modelling"]] <- list(
      gate_row = "bioc_voom_mean_variance",
      metric_name = "voom_weight_range",
      metric_value = .voom_w_range,
      passes = isTRUE(is.finite(.voom_w_range) && .voom_w_range > 0),
      status = if (is.finite(.voom_w_range)) "computed (EList\$weights range)"
               else "not_computed (no limma EList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_ZENITH_ZENITH_GSA_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("filter low-expression genes", "TMM normalization", "voom mean-variance modelling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_ZENITH_ZENITH_GSA_WORKFLOW":',
        paste0('    zenith: ', as.character(packageVersion('zenith')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zenith_gsa_workflow.csv versions.yml
    """
}

workflow BIOC_ZENITH_ZENITH_GSA_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCounts, df_metadata ] ]

    main:
    BIOC_ZENITH_ZENITH_GSA_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.tables
    plots    = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.plots
    objects  = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.objects
    versions = BIOC_ZENITH_ZENITH_GSA_WORKFLOW.out.versions
}
