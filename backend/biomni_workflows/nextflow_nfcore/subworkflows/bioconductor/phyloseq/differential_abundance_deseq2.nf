#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phyloseq — differential_abundance_deseq2
// Convert a phyloseq object to a DESeq2 object to perform negative binomial differential abundance testing and visualize the results.
// Input: phyloseq_object
// Container: quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0
// R packages: DESeq2, ggplot2, phyloseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2 {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phyloseq:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("DESeq2", "ggplot2", "phyloseq")
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
    library(phyloseq)
    library(DESeq2)
    library(ggplot2)
    
    # --- Read the user input file (phyloseq S4 object) ---
    kostic <- readRDS("phyloseq_object")
    
    # Define alpha threshold for significance filtering
    alpha <- 0.01
    
    # --- Filter out low-read samples and clean up metadata ---
    kostic <- subset_samples(kostic, DIAGNOSIS != "None")
    kostic <- prune_samples(sample_sums(kostic) > 500, kostic)
    
    # --- Convert the phyloseq object to a DESeq2 dataset ---
    diagdds = phyloseq_to_deseq2(kostic, ~ DIAGNOSIS)
    
    # --- Estimate size factors using geometric means and run DESeq2 ---
    gm_mean = function(x, na.rm=TRUE){ exp(sum(log(x[x > 0]), na.rm=na.rm) / length(x)) }
    geoMeans = apply(counts(diagdds), 1, gm_mean)
    diagdds = estimateSizeFactors(diagdds, geoMeans = geoMeans)
    diagdds = DESeq(diagdds, fitType="local")
    
    # --- Extract and filter significant results ---
    res = results(diagdds)
    res = res[order(res\$padj, na.last=NA), ]
    sigtab = res[(res\$padj < alpha), ]
    sigtab = cbind(as(sigtab, "data.frame"), as(tax_table(kostic)[rownames(sigtab), ], "matrix"))
    
    # Prepare the sigtabgen object for plotting (filtering out NA Genus if present)
    if ("Genus" %in% colnames(sigtab)) {
      sigtabgen = subset(sigtab, !is.na(Genus))
    } else {
      sigtabgen = sigtab
    }
    
    # --- Visualize the results using ggplot2 ---
    p <- ggplot(sigtabgen, aes(y=Genus, x=log2FoldChange, color=Phylum)) + 
      geom_vline(xintercept = 0.0, color = "gray", size = 0.5) + 
      geom_point(size=6) + 
      theme(axis.text.x = element_text(angle = -90, hjust = 0, vjust=0.5))
    
    # --- Save outputs to the working directory ---
    write.csv(as.data.frame(res), "deseq2_results_all.csv", row.names = TRUE)
    write.csv(as.data.frame(sigtab), "deseq2_results_significant.csv", row.names = TRUE)
    saveRDS(diagdds, "deseq2_dataset.rds")
    ggsave("differential_abundance_plot.pdf", plot = p, width = 12, height = 8)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2":',
        paste0('        phyloseq: ', as.character(packageVersion("phyloseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_abundance_deseq2.csv versions.yml
    """
}

workflow BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq_object ] ]

    main:
    BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2(ch_input)

    emit:
    tables   = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.tables
    plots    = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.plots
    objects  = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.objects
    versions = BIOC_PHYLOSEQ_DIFFERENTIAL_ABUNDANCE_DESEQ2.out.versions
}
