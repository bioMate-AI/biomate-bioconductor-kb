#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosdef — container_enrichment_and_visualization
// Run functional enrichment analyses and generate standard diagnostic and exploratory plots directly from DESeq2 container objects.
// Input: dds_macrophage, res_macrophage_IFNg_vs_naive
// Container: quay.io/biocontainers/bioconductor-mosdef:1.6.0--r45hdfd78af_0
// R packages: TxDb.Hsapiens.UCSC.hg38.knownGene, AnnotationDbi, clusterProfiler, DESeq2, ggplot2, goseq, macrophage, mosdef, org.Hs.eg.db, topGO
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, DESeq2, TxDb.Hsapiens.UCSC.hg38.knownGene, clusterProfiler, ggplot2, goseq, mosdef, org.Hs.eg.db, topGO
// Visualizations: volcano plot, MA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Validate input containers using mosdef_de_container_check and mosdef_res_check
//  * 2. [Core Analysis] Run functional enrichment using topGO, goseq, or clusterProfiler wrappers
//  * 3. [Visualization & Output] Plot individual gene expression levels across conditions
//  * 4. [Visualization & Output] Generate standard and GO-highlighted volcano plots
//  * 5. [Visualization & Output] Generate MA plots with optional gene highlighting

nextflow.enable.dsl = 2

process BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("TxDb.Hsapiens.UCSC.hg38.knownGene", "AnnotationDbi", "clusterProfiler", "DESeq2", "ggplot2", "goseq", "macrophage", "mosdef", "org.Hs.eg.db", "topGO")
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
    library(mosdef)
    library(DESeq2)
    library(org.Hs.eg.db)
    library(AnnotationDbi)
    library(ggplot2)
    library(topGO)
    library(goseq)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(clusterProfiler)
    
    # Read user input files from the working directory
    dds_macrophage <- readRDS("dds_macrophage.rds")
    res_macrophage_IFNg_vs_naive <- readRDS("res_macrophage_IFNg_vs_naive.rds")
    
    # Ensure the symbol column is present in the results object
    if (!"symbol" %in% colnames(res_macrophage_IFNg_vs_naive)) {
      res_macrophage_IFNg_vs_naive\$symbol <- AnnotationDbi::mapIds(
        org.Hs.eg.db,
        keys = row.names(res_macrophage_IFNg_vs_naive),
        column = "SYMBOL",
        keytype = "ENSEMBL",
        multiVals = "first"
      )
    }
    
    # 1. Validate input containers
    mosdef_de_container_check(dds_macrophage)
    mosdef_res_check(res_macrophage_IFNg_vs_naive)
    
    # 2. Run functional enrichment analyses
    # Run topGO
    res_enrich_macrophage_topGO <- run_topGO(
      de_container = dds_macrophage,
      res_de = res_macrophage_IFNg_vs_naive,
      ontology = "BP",
      mapping = "org.Hs.eg.db",
      FDR_threshold = 0.05,
      gene_id = "symbol",
      de_type = "up_and_down",
      add_gene_to_terms = TRUE,
      topGO_method2 = "elim",
      min_counts = 20,
      top_de = 700,
      verbose = TRUE
    )
    write.csv(res_enrich_macrophage_topGO, "res_enrich_macrophage_topGO.csv", row.names = FALSE)
    saveRDS(res_enrich_macrophage_topGO, "res_enrich_macrophage_topGO.rds")
    
    # Run goseq (wrapped in tryCatch for robustness)
    goseq_macrophage <- tryCatch({
      res_goseq <- run_goseq(
        de_container = dds_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        mapping = "org.Hs.eg.db",
        testCats = "GO:BP"
      )
      write.csv(res_goseq, "goseq_macrophage.csv", row.names = FALSE)
      saveRDS(res_goseq, "goseq_macrophage.rds")
      res_goseq
    }, error = function(e) {
      message("goseq analysis failed: ", e\$message)
      NULL
    })
    
    # Run clusterProfiler (wrapped in tryCatch for robustness)
    clupro_macrophage <- tryCatch({
      res_clupro <- run_cluPro(
        de_container = dds_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        mapping = "org.Hs.eg.db",
        keyType = "SYMBOL",
        ont = "BP"
      )
      saveRDS(res_clupro, "clupro_macrophage.rds")
      res_clupro
    }, error = function(e) {
      message("clusterProfiler analysis failed: ", e\$message)
      NULL
    })
    
    # 3. Plot individual gene expression levels across conditions
    p_gene <- gene_plot(
      de_container = dds_macrophage,
      gene = "ENSG00000125347",
      intgroup = "condition"
    )
    ggplot2::ggsave("gene_plot_ENSG00000125347.pdf", plot = p_gene, width = 7, height = 6)
    
    # 4. Generate standard and GO-highlighted volcano plots
    volcPlot <- de_volcano(
      res_de = res_macrophage_IFNg_vs_naive,
      mapping = "org.Hs.eg.db",
      logfc_cutoff = 1,
      FDR = 0.05, 
      labeled_genes = 25
    )
    ggplot2::ggsave("volcano_plot.pdf", plot = volcPlot, width = 8, height = 8)
    
    Volc_GO <- go_volcano(
      res_de = res_macrophage_IFNg_vs_naive,
      res_enrich = res_enrich_macrophage_topGO,
      term_index = 1,
      logfc_cutoff = 1,
      FDR = 0.05,
      mapping = "org.Hs.eg.db",
      n_overlaps = 50,
      col_to_use = "symbol",
      enrich_col = "genes",
      down_col = "black",
      up_col = "black",
      highlight_col = "tomato"
    )
    ggplot2::ggsave("go_volcano_plot.pdf", plot = Volc_GO, width = 8, height = 8)
    
    # 5. Generate MA plots with optional gene highlighting
    maplot <- plot_ma(
      res_de = res_macrophage_IFNg_vs_naive,
      FDR = 0.05,
      hlines = 1
    )
    ggplot2::ggsave("ma_plot.pdf", plot = maplot, width = 8, height = 6)
    
    maplot_genes <- plot_ma(
      res_de = res_macrophage_IFNg_vs_naive,
      FDR = 0.1,
      add_rug = FALSE,
      intgenes = c(
        "SLC7A2",
        "CFLAR",
        "PDK4",
        "IFNGR1"
      ),
      hlines = 1,
      intgenes_color = "darkblue"
    )
    ggplot2::ggsave("ma_plot_genes.pdf", plot = maplot_genes, width = 8, height = 6)

    writeLines(c(
        '"BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION":',
        paste0('    mosdef: ', as.character(packageVersion('mosdef')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_container_enrichment_and_visualization.csv versions.yml
    """
}

workflow BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds_macrophage, res_macrophage_IFNg_vs_naive ] ]

    main:
    BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION.out.tables
    plots    = BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION.out.plots
    objects  = BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION.out.objects
    versions = BIOC_MOSDEF_CONTAINER_ENRICHMENT_AND_VISUALIZATION.out.versions
}
