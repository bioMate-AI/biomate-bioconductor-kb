#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: microbiome — microbiome_analysis_pipeline
// Perform a comprehensive microbiome analysis including quality control, alpha diversity profiling, taxonomic composition visualization, core microbiome identific
// Input: abundance.csv, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: microbiome
// Visualizations: box plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("microbiome")
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
    
    # Load the authoritative microbiome package
    library(microbiome)
    
    # ==========================================
    # --- Data Loading & Preprocessing ---
    # ==========================================
    message("Stage 1: Loading and preprocessing input data...")
    
    # Read inputs per the declared contract: abundance.csv has a 'taxon_id' ID column
    # (taxa as rows), coldata.csv has a 'sample' ID column (samples as rows).
    abundance_df <- read.csv("abundance.csv", check.names = FALSE, row.names = "taxon_id")
    coldata_df   <- read.csv("coldata.csv",   check.names = FALSE, row.names = "sample")

    # Construct the phyloseq object directly from the abundance matrix and metadata.
    # (read_csv2phyloseq forces a CSV round-trip and additionally requires a taxonomy
    # file the workflow does not produce — direct construction is robust and avoids it.)
    otu_mat <- as.matrix(abundance_df)
    storage.mode(otu_mat) <- "double"
    # align samples present in both the abundance matrix (columns) and the metadata (rows)
    common_samples <- intersect(colnames(otu_mat), rownames(coldata_df))
    if (length(common_samples) == 0) {
      stop("No overlapping sample IDs between abundance columns and metadata rows.")
    }
    otu_mat <- otu_mat[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    pseq <- phyloseq(
      otu_table(otu_mat, taxa_are_rows = TRUE),
      sample_data(coldata_df)
    )
    
    # ==========================================
    # --- Quality Control & Profiling ---
    # ==========================================
    message("Stage 2: Profiling samples and taxa...")
    
    # Calculate sample read counts
    sample_reads <- readcount(pseq)
    
    # Identify the dominant taxon in each sample
    dom_taxa <- dominant(pseq)
    
    # Calculate sample divergence (beta diversity divergence to the median profile)
    div_val <- tryCatch({
      divergence(pseq)
    }, error = function(e) {
      warning("Divergence calculation failed: ", e\$message)
      rep(NA, ncol(abundances(pseq)))
    })
    
    # Combine metadata with QC and profiling metrics
    metadata <- meta(pseq)
    sample_summary <- data.frame(
      sample = rownames(metadata),
      metadata,
      read_count = sample_reads[rownames(metadata)],
      dominant_taxon = dom_taxa[rownames(metadata)],
      divergence = div_val[rownames(metadata)],
      stringsAsFactors = FALSE
    )
    write.csv(sample_summary, "sample_summary.csv", row.names = FALSE)
    
    # ==========================================
    # --- Alpha Diversity Analysis ---
    # ==========================================
    message("Stage 3: Analyzing alpha diversity...")
    
    # Calculate comprehensive alpha diversity indices
    alpha_metrics <- alpha(pseq, index = "all")
    write.csv(alpha_metrics, "alpha_diversity.csv", row.names = TRUE)
    
    # Generate alpha diversity boxplot grouped by the 'group' variable
    tryCatch({
      pdf("alpha_boxplot.pdf", width = 8, height = 6)
      p_alpha <- boxplot_alpha(pseq, index = "shannon", x = "group")
      print(p_alpha)
      dev.off()
    }, error = function(e) {
      warning("Alpha boxplot generation failed: ", e\$message)
      # Create fallback empty PDF
      pdf("alpha_boxplot.pdf", width = 8, height = 6)
      plot.new()
      text(0.5, 0.5, "Alpha boxplot generation failed", cex = 1.2)
      dev.off()
    })
    
    # ==========================================
    # --- Compositional & Core Microbiome Analysis ---
    # ==========================================
    message("Stage 4: Analyzing taxonomic composition and core members...")
    
    # Transform abundances to relative abundances (compositional)
    pseq_rel <- transform(pseq, "compositional")
    
    # Generate taxonomic composition plot
    tryCatch({
      pdf("composition_plot.pdf", width = 10, height = 8)
      p_comp <- plot_composition(pseq_rel)
      print(p_comp)
      dev.off()
    }, error = function(e) {
      warning("Composition plot generation failed: ", e\$message)
      pdf("composition_plot.pdf", width = 10, height = 8)
      plot.new()
      text(0.5, 0.5, "Composition plot generation failed", cex = 1.2)
      dev.off()
    })
    
    # Identify core taxa members
    core_taxa <- core_members(pseq_rel, detection = 0.001, prevalence = 0.1)
    
    # Generate core microbiome heatmap
    tryCatch({
      pdf("core_heatmap.pdf", width = 10, height = 8)
      p_core <- plot_core(pseq_rel, plot.type = "heatmap")
      print(p_core)
      dev.off()
    }, error = function(e) {
      warning("Core heatmap generation failed: ", e\$message)
      pdf("core_heatmap.pdf", width = 10, height = 8)
      plot.new()
      text(0.5, 0.5, "Core heatmap generation failed", cex = 1.2)
      dev.off()
    })
    
    # ==========================================
    # --- Taxon-Level Summary ---
    # ==========================================
    message("Stage 5: Generating taxon-level summary...")
    
    taxa_names <- taxa(pseq)
    tax_abundances <- abundances(pseq_rel)
    mean_abundance <- rowMeans(tax_abundances)
    tax_prevalence <- prevalence(pseq)
    
    taxon_summary <- data.frame(
      taxon_id = taxa_names,
      mean_relative_abundance = mean_abundance[taxa_names],
      prevalence = tax_prevalence[taxa_names],
      is_core = taxa_names %in% core_taxa,
      stringsAsFactors = FALSE
    )
    write.csv(taxon_summary, "taxon_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE":',
        paste0('    microbiome: ', as.character(packageVersion('microbiome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_analysis_pipeline.csv versions.yml
    """
}

workflow BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE.out.tables
    plots    = BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE.out.plots
    objects  = BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE.out.objects
    versions = BIOC_MICROBIOME_MICROBIOME_ANALYSIS_PIPELINE.out.versions
}
