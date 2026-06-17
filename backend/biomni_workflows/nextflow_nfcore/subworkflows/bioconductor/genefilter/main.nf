#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genefilter — gene_filtering
// Filter genes from an expression dataset using non-specific criteria, specific criteria, or a combination of both.
// Input: sample.ExpressionSet
// Container: quay.io/biocontainers/bioconductor-genefilter:1.92.0--r45h9e4a190_0
// R packages: ALL, Biobase, class, genefilter
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, genefilter
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the dataset and packages
//  * 2. [Input & Preparation] Define a non-specific filter using kOverA
//  * 3. [Input & Preparation] Define a specific filter using ttest
//  * 4. [Core Analysis] Combine the filters using filterfun
//  * 5. [Core Analysis] Apply the filters to the expression matrix using genefilter

nextflow.enable.dsl = 2

process BIOC_GENEFILTER_GENE_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ALL", "Biobase", "class", "genefilter")
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
        
    # 1. Load the dataset and packages
    library("Biobase")
    library("genefilter")
    
    # Read the user-provided ExpressionSet from the working directory
    sample.ExpressionSet <- readRDS("sample.ExpressionSet")
    
    # 2. Define a non-specific filter using kOverA
    f1 <- kOverA(5, 200)
    ffun <- filterfun(f1)
    wh1 <- genefilter(exprs(sample.ExpressionSet), ffun)
    sum(wh1)
    
    # 3. Define a specific filter using ttest
    # Dynamically identify a covariate with exactly two levels to avoid hardcoding
    pdata <- pData(sample.ExpressionSet)
    cov_name <- names(pdata)[sapply(pdata, function(x) length(unique(na.omit(x))) == 2)][1]
    f2 <- ttest(pdata[[cov_name]], p=0.1)
    wh2 <- genefilter(exprs(sample.ExpressionSet), filterfun(f2))
    sum(wh2)
    
    # 4. Combine the filters using filterfun
    ffun_combined <- filterfun(f1, f2)
    
    # 5. Apply the filters to the expression matrix using genefilter
    wh3 <- genefilter(exprs(sample.ExpressionSet), ffun_combined)
    sum(wh3)
    
    # 6. Write named output files for the meaningful results
    # Create a summary table of the filtering results for each gene
    filter_summary <- data.frame(
      Gene = featureNames(sample.ExpressionSet),
      Passed_NonSpecific = wh1,
      Passed_Specific = wh2,
      Passed_Combined = wh3,
      stringsAsFactors = FALSE
    )
    write.csv(filter_summary, "gene_filtering_results.csv", row.names = FALSE)
    
    # Create a summary table of the counts of genes passing each filter
    counts_summary <- data.frame(
      Filter = c("Non-specific (kOverA)", "Specific (ttest)", "Combined"),
      Passed_Count = c(sum(wh1), sum(wh2), sum(wh3)),
      stringsAsFactors = FALSE
    )
    write.csv(counts_summary, "filtering_counts_summary.csv", row.names = FALSE)
    
    # Save the filtered ExpressionSet containing only the genes that passed the combined filter
    filtered_eset <- sample.ExpressionSet[wh3, ]
    saveRDS(filtered_eset, "filtered_ExpressionSet.rds")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_GENEFILTER_GENE_FILTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GENEFILTER_GENE_FILTERING":',
        paste0('    genefilter: ', as.character(packageVersion('genefilter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_filtering.csv versions.yml
    """
}

workflow BIOC_GENEFILTER_GENE_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet ] ]

    main:
    BIOC_GENEFILTER_GENE_FILTERING(ch_input)

    emit:
    tables   = BIOC_GENEFILTER_GENE_FILTERING.out.tables
    plots    = BIOC_GENEFILTER_GENE_FILTERING.out.plots
    objects  = BIOC_GENEFILTER_GENE_FILTERING.out.objects
    versions = BIOC_GENEFILTER_GENE_FILTERING.out.versions
}
