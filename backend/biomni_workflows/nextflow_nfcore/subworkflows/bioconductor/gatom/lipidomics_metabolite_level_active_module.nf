#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gatom — lipidomics_metabolite_level_active_module
// Identify an active metabolic module from lipidomics data using metabolite-level topology and abbreviate lipid labels for readability.
// Input: met.de.lipids
// Container: quay.io/biocontainers/bioconductor-gatom:1.8.4--r45hdfd78af_0
// R packages: data.table, gatom, igraph, mwcsr
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, gatom, igraph, mwcsr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the declared user input file from the working
//  * 2. [Visualization & Output] Download/load the required network and annotation
//  * 3. [Visualization & Output] Construct the metabolic graph with metabolite-level
//  * 4. [Visualization & Output] Score the graph
//  * 5. [Visualization & Output] Solve the maximum weight connected subgraph problem
//  * 6. [Visualization & Output] Abbreviate metabolite labels for improved readability
//  * 7. [Visualization & Output] Visualize the resulting module (creates the widget object)
//  * 8. [Visualization & Output] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE {
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
    .bm_deps <- c("data.table", "gatom", "igraph", "mwcsr")
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
    library(gatom)
    library(data.table)
    library(igraph)
    library(mwcsr)
    
    # --- Read the declared user input file from the working ---
    input_file <- "met.de.lipids"
    if (!file.exists(input_file)) {
      if (file.exists("met.de.lipids.csv")) {
        input_file <- "met.de.lipids.csv"
      } else if (file.exists("met.de.lipids.tsv")) {
        input_file <- "met.de.lipids.tsv"
      } else {
        stop("Required input file 'met.de.lipids' (or .csv/.tsv) not found in the working directory.")
      }
    }
    
    message("Reading user input: ", input_file)
    met.de.lipids <- data.table::fread(input_file)
    
    # --- Download/load the required network and annotation ---
    message("Downloading Rhea lipid subnetwork and annotations...")
    network.lipids <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.rhea.lipids.rds"))
    met.lipids.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.lipids.db.rds"))
    org.Mm.eg.gatom.anno <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/org.Mm.eg.gatom.anno.rds"))
    gene2reaction.extra <- data.table::fread("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/gene2reaction.rhea.mmu.eg.tsv", colClasses="character")
    
    # --- Construct the metabolic graph with metabolite-level ---
    message("Constructing metabolic graph...")
    lg <- makeMetabolicGraph(network=network.lipids,
                             topology="metabolites",
                             org.gatom.anno=org.Mm.eg.gatom.anno,
                             gene.de=NULL,
                             met.db=met.lipids.db,
                             met.de=met.de.lipids,
                             gene2reaction.extra=gene2reaction.extra)
    
    # --- Score the graph ---
    message("Scoring graph...")
    lgs <- scoreGraph(lg, k.gene = NULL, k.met = 50)
    
    # --- Solve the maximum weight connected subgraph problem ---
    message("Solving MWCS problem...")
    solver <- rnc_solver()
    set.seed(42)
    sol <- solve_mwcsp(solver, lgs)
    lm <- sol\$graph
    
    # --- Abbreviate metabolite labels for improved readability ---
    message("Abbreviating labels...")
    lm1 <- abbreviateLabels(lm, orig.names = TRUE, abbrev.names = TRUE)
    
    # --- Visualize the resulting module (creates the widget object) ---
    message("Creating visualization widget...")
    widget <- createShinyCyJSWidget(lm1)
    
    # --- Save meaningful results to output files ---
    message("Saving output files...")
    
    # Save the igraph object
    saveRDS(lm1, "active_lipid_module.rds")
    
    # Save as GraphML
    igraph::write_graph(lm1, file = "active_lipid_module.graphml", format = "graphml")
    
    # Save as interactive HTML widget
    tryCatch({
      saveModuleToHtml(module = lm1, file = "active_lipid_module.html", name = "Active_Lipid_Module")
    }, error = function(e) {
      warning("Could not save HTML widget: ", e\$message)
    })
    
    # Save as PDF plot
    tryCatch({
      set.seed(42)
      saveModuleToPdf(lm1, file = "active_lipid_module.pdf", name = "Active_Lipid_Module", n_iter = 100, force = 1e-5)
    }, error = function(e) {
      warning("Could not save PDF plot: ", e\$message)
    })
    
    # Export node and edge attributes as CSV tables
    tryCatch({
      nodes_dt <- data.table::as.data.table(igraph::as_data_frame(lm1, what = "vertices"))
      edges_dt <- data.table::as.data.table(igraph::as_data_frame(lm1, what = "edges"))
      data.table::fwrite(nodes_dt, "active_lipid_module_nodes.csv")
      data.table::fwrite(edges_dt, "active_lipid_module_edges.csv")
    }, error = function(e) {
      warning("Could not export CSV tables: ", e\$message)
    })
    
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # missing-value handling — scan .rds matrix/data.frame artifacts for max NA fraction
    .mv_na_fracs <- numeric(0)
    .mv_scanned <- character(0)
    for (.mv_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .mv_obj <- tryCatch(readRDS(.mv_rds), error = function(e) NULL)
      .mv_mat <- if (is.matrix(.mv_obj) || is.data.frame(.mv_obj)) .mv_obj else NULL
      if (!is.null(.mv_mat)) {
        .mv_vals <- suppressWarnings(as.numeric(as.matrix(.mv_mat)))
        if (length(.mv_vals) > 0) {
          .mv_na_fracs <- c(.mv_na_fracs, mean(is.na(.mv_vals)))
          .mv_scanned <- c(.mv_scanned, .mv_rds)
        }
      }
    }
    .mv_max <- if (length(.mv_na_fracs) > 0) round(max(.mv_na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .mv_max,
      passes = isTRUE(is.finite(.mv_max) && .mv_max < 0.05),
      status = if (is.finite(.mv_max)) paste0("computed (scanned ", length(.mv_scanned), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling", "count normalization", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE":',
        paste0('    gatom: ', as.character(packageVersion('gatom')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lipidomics_metabolite_level_active_module.csv versions.yml
    """
}

workflow BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ met.de.lipids ] ]

    main:
    BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE(ch_input)

    emit:
    tables   = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.tables
    plots    = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.plots
    objects  = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.objects
    versions = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.versions
}
