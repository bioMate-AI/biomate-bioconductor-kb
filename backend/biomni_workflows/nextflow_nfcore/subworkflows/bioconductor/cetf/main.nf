#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CeTF — integrated_cetf_analysis
// Perform the complete integrated RIF and PCIT analysis in a single step, followed by network visualization and functional enrichment.
// Input: counts_matrix.tsv, sample_metadata.csv, tf_list.txt
// Container: quay.io/biocontainers/bioconductor-cetf:1.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CeTF, dplyr, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load count data and sample annotations
//  * 2. [Visualization & Output] Load transcription factor list
//  * 3. [Visualization & Output] Run the complete integrated analysis
//  * 4. [Visualization & Output] Visualize DE and TF impact using SmearPlot
//  * 5. [Visualization & Output] Plot condition-specific networks
//  * 6. [Visualization & Output] Perform group GO analysis
//  * 7. [Visualization & Output] Generate integrated network plots
//  * 8. [Visualization & Output] Plot RIF relationships
//  * 9. [Visualization & Output] Generate enrichment plots
//  * 10. [Visualization & Output] Save tabular outputs

nextflow.enable.dsl = 2

process BIOC_CETF_INTEGRATED_CETF_ANALYSIS {
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
    .bm_deps <- c("CeTF", "org.Hs.eg.db", "dplyr")
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
        library(CeTF)
        library(org.Hs.eg.db)
        library(dplyr)
        
        # ==========================================
        # --- Load count data and sample annotations ---
        # ==========================================
        counts_raw <- read.delim("counts_matrix.tsv", row.names = 1, check.names = FALSE)
        meta <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        
        # Identify sample and condition columns dynamically
        sample_col <- colnames(meta)[1]
        cond_col <- names(which(sapply(meta, function(x) length(unique(x)) == 2)))[1]
        if (is.na(cond_col)) {
          cond_col <- colnames(meta)[2]
        }
        
        # Sort metadata by condition to group them
        meta <- meta[order(meta[[cond_col]], decreasing = TRUE), ]
        conds <- unique(meta[[cond_col]])
        
        # Align counts matrix with sorted metadata
        common_samples <- intersect(meta[[sample_col]], colnames(counts_raw))
        meta <- meta[meta[[sample_col]] %in% common_samples, ]
        counts <- as.matrix(counts_raw[, meta[[sample_col]]])
        
        # Calculate sample sizes for each condition
        nSamples1 <- sum(meta[[cond_col]] == conds[1])
        nSamples2 <- sum(meta[[cond_col]] == conds[2])
        
        # ==========================================
        # --- Load transcription factor list ---
        # ==========================================
        TFs_all <- readLines("tf_list.txt")
        # Filter TFs to those present in the counts matrix
        TFs <- TFs_all[TFs_all %in% rownames(counts)]
        if (length(TFs) == 0) {
          stop("None of the transcription factors in tf_list.txt are present in the counts matrix.")
        }
        
        # Open PDF device to save all plots
        pdf("cetf_analysis_plots.pdf", width = 11, height = 8.5)
        
        # ==========================================
        # --- Run the complete integrated analysis ---
        # ==========================================
        out <- runAnalysis(mat = counts, 
                           conditions = conds,
                           lfc = 5,
                           padj = 0.05,
                           TFs = TFs,
                           nSamples1 = nSamples1,
                           nSamples2 = nSamples2,
                           tolType = "mean",
                           diffMethod = "Reverter", 
                           data.type = "counts")
        
        # Save the CeTF class object
        saveRDS(out, "cetf_analysis_output.rds")
        
        # ==========================================
        # --- Visualize DE and TF impact using SmearPlot ---
        # ==========================================
        print(SmearPlot(object = out, 
                  diffMethod = 'Reverter', 
                  lfc = 1.5, 
                  conditions = conds, 
                  type = "DE"))
        
        # Select a key TF dynamically to avoid hardcoding errors
        key_tfs_df <- NetworkData(out, "keytfs")
        selected_tf <- if (!is.null(key_tfs_df) && nrow(key_tfs_df) > 0) key_tfs_df\$TF[1] else TFs[1]
        
        print(SmearPlot(object = out,
                  diffMethod = 'Reverter',
                  lfc = 1.5,
                  conditions = conds,
                  TF = selected_tf,
                  label = TRUE, 
                  type = "TF"))
        
        # ==========================================
        # --- Plot condition-specific networks ---
        # ==========================================
        print(netConditionsPlot(out))
        
        # ==========================================
        # --- Perform group GO analysis ---
        # ==========================================
        genes <- unique(c(as.character(NetworkData(out, "network1")[, "gene1"]), 
                          as.character(NetworkData(out, "network1")[, "gene2"])))
        
        cond1 <- getGroupGO(genes = genes, 
                            ont = "BP", 
                            keyType = "ENSEMBL", 
                            annoPkg = org.Hs.eg.db, 
                            level = 3)
        
        # ==========================================
        # --- Generate integrated network plots ---
        # ==========================================
        t1 <- head(cond1\$results, 12)
        t2 <- subset(cond1\$netGO, cond1\$netGO\$gene1 %in% as.character(t1[, "ID"]))
        
        # Generating the GO plot grouping by pathways
        pt_pathways <- netGOTFPlot(netCond = NetworkData(out, "network1") %>% 
                            mutate(across(everything(), as.character)),
                          resultsGO = t1,
                          netGO = t2,
                          anno = NetworkData(out, "annotation"),
                          groupBy = 'pathways',
                          type = 'GO')
        print(pt_pathways\$plot)
        
        # Generating the GO plot grouping by TFs
        tfs_plot <- head(NetworkData(out, "keytfs")\$TF, 4)
        pt_tfs <- netGOTFPlot(netCond = NetworkData(out, "network1"),
                          resultsGO = t1,
                          netGO = t2,
                          anno = NetworkData(out, "annotation"),
                          groupBy = 'TFs',
                          TFs = tfs_plot, 
                          type = 'GO')
        print(pt_tfs\$plot)
        
        # Generating the GO plot grouping by specific genes
        genes_plot <- head(genes, 4)
        pt_genes <- netGOTFPlot(netCond = NetworkData(out, "network1"),
                          resultsGO = t1,
                          netGO = t2,
                          anno = NetworkData(out, "annotation"),
                          groupBy = 'genes',
                          genes = genes_plot,
                          type = 'GO')
        print(pt_genes\$plot)
        
        # Generating the integrated GO plot
        pt_integrated <- netGOTFPlot(netCond = NetworkData(out, "network1") %>% 
                           mutate(across(everything(), as.character)),
                          netGO = t2,
                          keyTFs = NetworkData(out, "keytfs"), 
                          type = 'Integrated')
        print(pt_integrated\$plot)
        
        # ==========================================
        # --- Plot RIF relationships ---
        # ==========================================
        print(RIFPlot(object = out,
                color  = "darkblue",
                type   = "RIF"))
        
        print(RIFPlot(object = out,
                color  = "darkblue",
                type   = "DE"))
        
        # ==========================================
        # --- Generate enrichment plots ---
        # ==========================================
        cond1 <- getEnrich(genes = genes, organismDB = org.Hs.eg.db, 
                          keyType = 'ENSEMBL', ont = 'BP', fdrMethod = "BH", 
                          fdrThr = 0.05, minGSSize = 5, maxGSSize = 500)
        
        # Save enrichment results table
        if (!is.null(cond1\$results)) {
          write.csv(cond1\$results, "enrichment_results.csv", row.names = FALSE)
        }
        
        # Plot enrichment outputs with error handling in case of no enriched terms
        tryCatch({
          print(heatPlot(res = cond1\$results,
                   diff = getDE(out, "all")))
        }, error = function(e) {
          message("Skipping heatPlot: ", e\$message)
        })
        
        tryCatch({
          print(enrichPlot(res = cond1\$results,
                     type = "circle"))
        }, error = function(e) {
          message("Skipping enrichPlot (circle): ", e\$message)
        })
        
        tryCatch({
          print(enrichPlot(res = cond1\$results,
                     type = "bar"))
        }, error = function(e) {
          message("Skipping enrichPlot (bar): ", e\$message)
        })
        
        tryCatch({
          print(enrichPlot(res = cond1\$results,
                     type = "dot"))
        }, error = function(e) {
          message("Skipping enrichPlot (dot): ", e\$message)
        })
        
        # Close PDF device
        dev.off()
        
        # ==========================================
        # --- Save tabular outputs ---
        # ==========================================
        if (!is.null(key_tfs_df)) {
          write.csv(key_tfs_df, "key_tfs.csv", row.names = FALSE)
        }
        
        net1 <- NetworkData(out, "network1")
        if (!is.null(net1)) {
          write.csv(net1, "network1_edges.csv", row.names = FALSE)
        }
        
        net2 <- NetworkData(out, "network2")
        if (!is.null(net2)) {
          write.csv(net2, "network2_edges.csv", row.names = FALSE)
        }
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_CETF_INTEGRATED_CETF_ANALYSIS":',
        paste0('    CeTF: ', as.character(packageVersion('CeTF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_cetf_analysis.csv versions.yml
    """
}

workflow BIOC_CETF_INTEGRATED_CETF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.tsv, sample_metadata.csv, tf_list.txt ] ]

    main:
    BIOC_CETF_INTEGRATED_CETF_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CETF_INTEGRATED_CETF_ANALYSIS.out.tables
    plots    = BIOC_CETF_INTEGRATED_CETF_ANALYSIS.out.plots
    objects  = BIOC_CETF_INTEGRATED_CETF_ANALYSIS.out.objects
    versions = BIOC_CETF_INTEGRATED_CETF_ANALYSIS.out.versions
}
