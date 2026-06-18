#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRepertoire — tcr_repertoire_analysis
// Process raw TCR contig data, combine them into clones, and perform basic and advanced repertoire visualizations and diversity analyses without single-cell expre
// Input: filtered_contig_annotations.csv
// Container: quay.io/biocontainers/bioconductor-screpertoire:2.2.0--r44he5774e6_0
// R packages: BiocStyle, circlize, ggplot2, ggraph, scales, scater, scRepertoire
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, scRepertoire
// Visualizations: scatter plot, diversity plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load contigs from the declared user input file
//  * 2. [Visualization & Output] Combine contigs into TCR clones
//  * 3. [Visualization & Output] Add metadata variables
//  * 4. [Visualization & Output] Quantify and visualize clones
//  * 5. [Visualization & Output] Analyze clonal dynamics
//  * 6. [Visualization & Output] Summarize repertoires (Gene usage)
//  * 7. [Visualization & Output] Comparing Clonal Diversity and Overlap

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("BiocStyle", "circlize", "ggplot2", "ggraph", "scales", "scater", "scRepertoire")
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
        library(scRepertoire)
        library(ggplot2)
        
        # --- Load contigs from the declared user input file ---
        raw_contigs <- read.csv("filtered_contig_annotations.csv", stringsAsFactors = FALSE)
        
        # Treat the input file as a single sample rather than splitting by barcode suffix
        contig_list <- list(raw_contigs)
        
        # Use loadContigs to support multiple formats (10x, TRUST4, WAT3R, etc.)
        contig_list <- loadContigs(input = contig_list, format = "auto")
        
        sample_names <- paste0("Sample", seq_along(contig_list))
        
        # --- Combine contigs into TCR clones ---
        combined.TCR <- combineTCR(contig_list, 
                                   samples = sample_names,
                                   removeNA = FALSE, 
                                   removeMulti = FALSE, 
                                   filterMulti = FALSE)
        
        # --- Add metadata variables ---
        # Assign "B" and "L" types based on the number of actual samples recovered
        types <- rep(c("B", "L"), length.out = length(combined.TCR))
        combined.TCR <- addVariable(combined.TCR, 
                                    variable.name = "Type", 
                                    variables = types)
        
        # Save the processed combined TCR object
        saveRDS(combined.TCR, file = "combined_TCR.rds")
        
        # --- Quantify and visualize clones ---
        p_quant <- clonalQuant(combined.TCR, 
                               cloneCall="strict", 
                               chain = "both", 
                               scale = TRUE)
        ggsave("clonal_quantification.pdf", plot = p_quant, width = 8, height = 6)
        
        p_abundance <- clonalAbundance(combined.TCR, 
                                       cloneCall = "gene", 
                                       scale = FALSE)
        ggsave("clonal_abundance.pdf", plot = p_abundance, width = 8, height = 6)
        
        p_length <- clonalLength(combined.TCR, 
                                cloneCall="aa", 
                                chain = "both") 
        ggsave("clonal_length.pdf", plot = p_length, width = 8, height = 6)
        
        # Safely select samples for comparative plots
        if (length(combined.TCR) > 1) {
          s1 <- names(combined.TCR)[1]
          s2 <- names(combined.TCR)[2]
          
          p_compare <- clonalCompare(combined.TCR, 
                                       top.clones = 10, 
                                       samples = c(s1, s2), 
                                       cloneCall="aa", 
                                       graph = "alluvial")
          ggsave("clonal_compare.pdf", plot = p_compare, width = 8, height = 6)
          
          p_scatter <- clonalScatter(combined.TCR, 
                                   cloneCall ="gene", 
                                   x.axis = s1, 
                                   y.axis = s2,
                                   dot.size = "total",
                                   graph = "proportion")
          ggsave("clonal_scatter.pdf", plot = p_scatter, width = 8, height = 6)
        }
        
        # --- Analyze clonal dynamics ---
        p_home <- clonalHomeostasis(combined.TCR, cloneCall = "gene")
        ggsave("clonal_homeostasis.pdf", plot = p_home, width = 8, height = 6)
        
        p_prop <- clonalProportion(combined.TCR, cloneCall = "gene")
        ggsave("clonal_proportion.pdf", plot = p_prop, width = 8, height = 6)
        
        # --- Summarize repertoires (Gene usage) ---
        p_genes <- percentGenes(combined.TCR, chain = "TRB", gene = "Vgene", summary.fun = "percent")
        ggsave("percent_genes.pdf", plot = p_genes, width = 8, height = 6)
        
        p_vj <- percentVJ(combined.TCR, chain = "TRB", summary.fun = "percent")
        ggsave("percent_vj.pdf", plot = p_vj, width = 8, height = 6)
        
        p_aa <- percentAA(combined.TCR, chain = "TRB", aa.length = 20)
        ggsave("percent_aa.pdf", plot = p_aa, width = 8, height = 6)
        
        p_pe <- positionalEntropy(combined.TCR, chain = "TRB", aa.length = 20)
        ggsave("positional_entropy.pdf", plot = p_pe, width = 8, height = 6)
        
        p_pp <- positionalProperty(combined.TCR, chain = "TRB", aa.length = 20, method = "atchleyFactors")
        ggsave("positional_property.pdf", plot = p_pp, width = 8, height = 6)
        
        p_kmer <- percentKmer(combined.TCR, cloneCall = "aa", chain = "TRB", motif.length = 3, top.motifs = 25)
        ggsave("percent_kmer.pdf", plot = p_kmer, width = 8, height = 6)
        
        # --- Comparing Clonal Diversity and Overlap ---
        p_div <- clonalDiversity(combined.TCR, cloneCall = "gene")
        ggsave("clonal_diversity.pdf", plot = p_div, width = 8, height = 6)
        
        p_rarefaction <- clonalRarefaction(combined.TCR, cloneCall = "gene")
        ggsave("clonal_rarefaction.pdf", plot = p_rarefaction, width = 8, height = 6)
        
        p_size_dist <- clonalSizeDistribution(combined.TCR, cloneCall = "gene")
        ggsave("clonal_size_distribution.pdf", plot = p_size_dist, width = 8, height = 6)
        
        if (length(combined.TCR) > 1) {
          p_overlap <- clonalOverlap(combined.TCR, cloneCall = "gene")
          ggsave("clonal_overlap.pdf", plot = p_overlap, width = 8, height = 6)
        }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS":',
        paste0('    scRepertoire: ', as.character(packageVersion('scRepertoire')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcr_repertoire_analysis.csv versions.yml
    """
}

workflow BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ filtered_contig_annotations.csv ] ]

    main:
    BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.tables
    plots    = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.plots
    objects  = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.objects
    versions = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.versions
}
