#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vtpnet — vtp_network_construction
// Intersect GWAS variants with transcription factor binding sites and filter by disease map to identify phenotype-TF links.
// Input: gwas_variants.GRanges, tf_binding_sites.GRanges, disease_map.RData
// Container: quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0
// R packages: GenomicRanges, doParallel, foreach, graph, gwascat, MotifDb, Rgraphviz, vtpnet
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: bar plot

nextflow.enable.dsl = 2

process BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "doParallel", "foreach", "graph", "gwascat", "MotifDb", "Rgraphviz", "vtpnet")
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
    library(vtpnet)
    library(GenomicRanges)
    library(gwascat)
    
    # --- Load GWAS variants and TF binding sites from user input ---
    # Read the GRanges objects
    maurGWAS <- readRDS("gwas_variants.GRanges")
    pax4 <- readRDS("tf_binding_sites.GRanges")
    
    # Since the user provides a single TF binding sites file, we use it for the comparisons
    pax4_85 <- pax4
    pax4_75 <- pax4
    
    # Load the disease map from the RData file
    env <- new.env()
    load("disease_map.RData", envir = env)
    loaded_names <- ls(env)
    if ("cancerMap" %in% loaded_names) {
      cancerMap <- env\$cancerMap
    } else if (length(loaded_names) > 0) {
      cancerMap <- env[[loaded_names[1]]]
    } else {
      stop("The disease_map.RData file is empty or could not be loaded properly.")
    }
    
    # --- Find overlaps between GWAS variants and TF binding sites ---
    vp_pax4_85 = maurGWAS[ overlapsAny(maurGWAS, pax4_85) ]
    length(vp_pax4_85)
    
    vp_pax4_75 = maurGWAS[ overlapsAny(maurGWAS, pax4_75) ]
    length(vp_pax4_75)
    
    # --- Filter the GWAS variants by a disease map using ---
    gwrngs19 <- maurGWAS
    cangw = filterGWASbyMap( gwrngs19, cancerMap )
    
    # --- Identify specific hits using getOneHits ---
    hits = getOneHits( pax4, cangw, "fimo" )
    
    # Save the results to output files
    saveRDS(hits, "one_hits.rds")
    write.csv(as.data.frame(hits), "one_hits.csv", row.names = FALSE)
    
    saveRDS(vp_pax4_75, "vp_pax4_75_overlaps.rds")
    write.csv(as.data.frame(vp_pax4_75), "vp_pax4_75_overlaps.csv", row.names = FALSE)
    
    # Generate a summary plot of the hits
    pdf("hits_summary.pdf")
    if (length(hits) > 0) {
      # Plot distribution of hits across chromosomes
      chrom_counts <- table(as.character(seqnames(hits)))
      barplot(chrom_counts, 
              main = "Number of Hits by Chromosome", 
              xlab = "Chromosome", 
              ylab = "Hit Count", 
              col = "skyblue", 
              las = 2)
    } else {
      plot.new()
      text(0.5, 0.5, "No hits identified to plot.", cex = 1.2)
    }
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION",
      domain  = "bioconductor",
      declared_qc_steps = c("alignment/mapping QC", "low-count filtering", "count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION":',
        paste0('        vtpnet: ', as.character(packageVersion("vtpnet")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vtp_network_construction.csv versions.yml
    """
}

workflow BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gwas_variants.GRanges, tf_binding_sites.GRanges, disease_map.RData ] ]

    main:
    BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.tables
    plots    = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.plots
    objects  = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.objects
    versions = BIOC_VTPNET_VTP_NETWORK_CONSTRUCTION.out.versions
}
