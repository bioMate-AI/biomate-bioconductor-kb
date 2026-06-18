#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOstats — go_association_supported_organism
// Perform standard or conditional hypergeometric testing for GO term association using a standard Bioconductor annotation package.
// Input: expression_data.RData
// Container: quay.io/biocontainers/bioconductor-gostats:2.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GOstats, annotate, genefilter
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input
//  * 2. [Visualization & Output] Run Documented Workflow Steps
//  * 3. [Visualization & Output] Save Outputs

nextflow.enable.dsl = 2

process BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM {
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
    .bm_deps <- c("Biobase", "annotate", "genefilter", "GOstats", "annot_db")
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
    library(Biobase)
    library(annotate)
    library(genefilter)
    library(GOstats)
    
    # --- Load User Input ---
    input_file <- "expression_data.RData"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Load the RData file
    env <- new.env()
    load(input_file, envir = env)
    
    # Find the ExpressionSet object in the loaded environment
    eset_name <- NULL
    for (obj in ls(env)) {
      if (inherits(env[[obj]], "ExpressionSet")) {
        eset_name <- obj
        break
      }
    }
    
    if (is.null(eset_name)) {
      stop("No ExpressionSet object found in expression_data.RData")
    }
    
    # Assign to the variable name used in the documented code
    bcrAblOrNeg <- env[[eset_name]]
    
    # Dynamically determine the annotation package from the ExpressionSet
    annot_pkg <- annotation(bcrAblOrNeg)
    if (length(annot_pkg) == 0 || annot_pkg == "") {
      stop("ExpressionSet does not have an annotation package specified.")
    }
    annot_db <- paste0(annot_pkg, ".db")
    
    if (!require(annot_db, character.only = TRUE)) {
      stop(paste("Annotation package", annot_db, "is not installed."))
    }
    
    # Dynamically get the required mapping environments
    entrez_env <- get(paste0(annot_pkg, "ENTREZID"))
    go_env <- get(paste0(annot_pkg, "GO"))
    chr_env <- get(paste0(annot_pkg, "CHR"))
    
    # Ensure the phenoData has a factor with exactly two levels for rowttests
    if ("mol.biol" %in% colnames(pData(bcrAblOrNeg)) && length(unique(na.omit(bcrAblOrNeg\$mol.biol))) >= 2) {
      target_col <- "mol.biol"
    } else {
      target_col <- NULL
      for (col in colnames(pData(bcrAblOrNeg))) {
        if (length(unique(na.omit(pData(bcrAblOrNeg)[[col]]))) >= 2) {
          target_col <- col
          break
        }
      }
      if (is.null(target_col)) {
        stop("No suitable phenoData column with at least 2 levels found for t-tests.")
      }
    }
    
    # Subset to the first two unique levels of the target column to prevent rowttests from crashing
    vals <- unique(na.omit(pData(bcrAblOrNeg)[[target_col]]))
    keep_levels <- vals[1:2]
    bcrAblOrNeg <- bcrAblOrNeg[, pData(bcrAblOrNeg)[[target_col]] %in% keep_levels]
    bcrAblOrNeg\$mol.biol <- factor(pData(bcrAblOrNeg)[[target_col]], levels = keep_levels)
    
    # Define cutoffs used in the workflow
    iqrCutoff <- 0.5
    ttestCutoff <- 0.05
    hgCutoff <- 0.001
    
    # --- Run Documented Workflow Steps ---
    entrezIds <- mget(featureNames(bcrAblOrNeg), envir=entrez_env)
    haveEntrezId <- names(entrezIds)[sapply(entrezIds, function(x) !is.na(x))]
    bcrAblOrNeg <- bcrAblOrNeg[haveEntrezId, ]
    
    haveGo <- sapply(mget(featureNames(bcrAblOrNeg), go_env), function(x){ if (length(x) == 1 && is.na(x)) FALSE else TRUE })
    bcrAblOrNeg <- bcrAblOrNeg[haveGo, ]
    
    bcrAblOrNegIqr <- apply(exprs(bcrAblOrNeg), 1, IQR)
    selected <- bcrAblOrNegIqr > iqrCutoff
    
    chrN <- mget(featureNames(bcrAblOrNeg), envir=chr_env)
    onY <- sapply(chrN, function(x) any(x=="Y"))
    onY[is.na(onY)] <- FALSE
    selected <- selected & !onY
    
    nsFiltered <- bcrAblOrNeg[selected, ]
    
    # Define nsFilteredIqr for findLargest
    nsFilteredIqr <- bcrAblOrNegIqr[selected]
    uniqGenes <- findLargest(featureNames(nsFiltered), nsFilteredIqr, annot_pkg)
    nsFiltered <- nsFiltered[uniqGenes, ]
    
    affyUniverse <- featureNames(nsFiltered)
    entrezUniverse <- unlist(mget(affyUniverse, entrez_env))
    
    ttests = rowttests(nsFiltered, "mol.biol")
    smPV = ttests\$p.value < ttestCutoff
    pvalFiltered <- nsFiltered[smPV, ]
    
    selectedEntrezIds <- unlist(mget(featureNames(pvalFiltered), entrez_env))
    
    params <- new("GOHyperGParams", geneIds=selectedEntrezIds, universeGeneIds=entrezUniverse, annotation=annot_db, ontology="BP", pvalueCutoff=hgCutoff, conditional=FALSE, testDirection="over")
    paramsCond <- params
    conditional(paramsCond) <- TRUE
    
    hgOver <- hyperGTest(params)
    hgCondOver <- hyperGTest(paramsCond)
    
    df <- summary(hgOver)
    
    # Execute accessor functions safely without hardcoded out-of-bounds indices
    pvals_top <- head(pvalues(hgOver), 3)
    odds_top <- head(oddsRatios(hgOver), 3)
    expected_top <- head(expectedCounts(hgOver), 3)
    gene_counts_top <- head(geneCounts(hgOver), 3)
    univ_counts_top <- head(universeCounts(hgOver), 3)
    g_ids_len <- length(geneIds(hgOver))
    
    univ_list <- geneIdUniverse(hgOver)
    g_id_univ_len <- if (length(univ_list) >= 3) {
      length(univ_list[[3]])
    } else if (length(univ_list) > 0) {
      length(univ_list[[length(univ_list)]])
    } else {
      0
    }
    
    dag <- goDag(hgOver)
    g_mapped_cnt <- geneMappedCount(hgOver)
    u_mapped_cnt <- universeMappedCount(hgOver)
    is_cond <- conditional(hgOver)
    test_dir <- testDirection(hgOver)
    t_name <- testName(hgOver)
    
    # Generate HTML Report
    htmlReport(hgCondOver, file="ALL_hgco.html")
    
    # --- Save Outputs ---
    write.csv(df, "hgOver_summary.csv", row.names=FALSE)
    write.csv(summary(hgCondOver), "hgCondOver_summary.csv", row.names=FALSE)
    saveRDS(hgOver, "hgOver.rds")
    saveRDS(hgCondOver, "hgCondOver.rds")
    
    # Save accessor results to a text summary
    sink("workflow_metadata_summary.txt")
    cat("=== GOstats Workflow Metadata Summary ===\n\n")
    cat("Top 3 P-values:\n")
    print(pvals_top)
    cat("\nTop 3 Odds Ratios:\n")
    print(odds_top)
    cat("\nTop 3 Expected Counts:\n")
    print(expected_top)
    cat("\nTop 3 Gene Counts:\n")
    print(gene_counts_top)
    cat("\nTop 3 Universe Counts:\n")
    print(univ_counts_top)
    cat("\nGene IDs Length:", g_ids_len, "\n")
    cat("Gene ID Universe (3rd element or last) Length:", g_id_univ_len, "\n")
    cat("Gene Mapped Count:", g_mapped_cnt, "\n")
    cat("Universe Mapped Count:", u_mapped_cnt, "\n")
    cat("Is Conditional:", is_cond, "\n")
    cat("Test Direction:", test_dir, "\n")
    cat("Test Name:", t_name, "\n")
    sink()
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
      process = "BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM":',
        paste0('    GOstats: ', as.character(packageVersion('GOstats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_association_supported_organism.csv versions.yml
    """
}

workflow BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData ] ]

    main:
    BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM(ch_input)

    emit:
    tables   = BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM.out.tables
    plots    = BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM.out.plots
    objects  = BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM.out.objects
    versions = BIOC_GOSTATS_GO_ASSOCIATION_SUPPORTED_ORGANISM.out.versions
}
