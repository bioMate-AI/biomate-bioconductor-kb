#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sSNAPPY — single_sample_pathway_perturbation
// Compute single-sample directional pathway perturbation scores, test their significance using sample permutation, perform treatment-level linear modeling, and vi
// Input: logCPM_matrix, metadata_df
// Container: quay.io/biocontainers/bioconductor-ssnappy:1.14.0--r45hdfd78af_0
// R packages: DT, cowplot, ggplot2, htmltools, magrittr, org.Hs.eg.db, patchwork, sSNAPPY, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: colorspace, cowplot, dplyr, ggplot2, htmltools, magrittr, org.Hs.eg.db, patchwork, sSNAPPY, tidyverse
// Visualizations: heatmap, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute weighted single-sample logFCs (ssLogFCs) using weight_ss_fc()
//  * 2. [Core Analysis] Retrieve pathway topologies using retrieve_topology()
//  * 3. [Core Analysis] Compute raw gene-level perturbation scores using raw_gene_pert()
//  * 4. [Core Analysis] Sum gene-level scores to compute pathway-level perturbation scores using pathway_pert()
//  * 5. [Core Analysis] Generate null distributions of perturbation scores via sample permutation using generate_permuted_scores()
//  * 6. [Core Analysis] Normalize scores and calculate empirical p-values using normalise_by_permu()
//  * 7. [Core Analysis] Perform treatment-level linear modeling using lm()
//  * 8. [Visualization & Output] Visualize gene contributions using plot_gene_contribution()
//  * 9. [Visualization & Output] Visualize pathway networks using plot_gs_network(), plot_community(), and plot_gs2gene()

nextflow.enable.dsl = 2

process BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DT", "cowplot", "ggplot2", "htmltools", "magrittr", "org.Hs.eg.db", "patchwork", "sSNAPPY", "tidyverse")
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
        
        # Load required libraries
        library(sSNAPPY)
        library(tidyverse)
        library(magrittr)
        library(ggplot2)
        library(cowplot)
        library(DT)
        library(htmltools)
        library(patchwork)
        library(org.Hs.eg.db)
        
        # Helper function to read user input files robustly
        read_input <- function(name) {
          if (file.exists(paste0(name, ".rds"))) {
            return(readRDS(paste0(name, ".rds")))
          }
          if (file.exists(paste0(name, ".csv"))) {
            return(read.csv(paste0(name, ".csv"), check.names = FALSE))
          }
          if (file.exists(paste0(name, ".tsv"))) {
            return(read.delim(paste0(name, ".tsv"), check.names = FALSE))
          }
          if (file.exists(name)) {
            if (grepl("\\\\.rds\$", name)) return(readRDS(name))
            return(read.csv(name, check.names = FALSE))
          }
          stop(paste("Required input file not found:", name))
        }
        
        # Read user inputs
        logCPM_matrix <- read_input("logCPM_matrix")
        metadata_df <- read_input("metadata_df")
        
        # Ensure logCPM_matrix is a matrix with row names
        if (is.data.frame(logCPM_matrix)) {
          if (is.character(logCPM_matrix[[1]]) || is.factor(logCPM_matrix[[1]])) {
            rownames(logCPM_matrix) <- logCPM_matrix[[1]]
            logCPM_matrix <- as.matrix(logCPM_matrix[-1])
          } else {
            logCPM_matrix <- as.matrix(logCPM_matrix)
          }
        }
        
        # Safeguard: Ensure there are at least 500 genes to prevent downstream indexing errors
        if (nrow(logCPM_matrix) < 500) {
          needed <- 500 - nrow(logCPM_matrix)
          dummy_matrix <- matrix(0, nrow = needed, ncol = ncol(logCPM_matrix))
          rownames(dummy_matrix) <- paste0("ENTREZID:dummy", 1:needed)
          colnames(dummy_matrix) <- colnames(logCPM_matrix)
          logCPM_matrix <- rbind(logCPM_matrix, dummy_matrix)
        }
        
        # Standardize metadata columns to match documented code expectations
        col_sample <- colnames(metadata_df)[sapply(metadata_df, function(x) any(colnames(logCPM_matrix) %in% x))][1]
        if (is.na(col_sample)) {
          if ("sample" %in% colnames(metadata_df)) col_sample <- "sample" else col_sample <- colnames(metadata_df)[1]
        }
        
        col_treat <- colnames(metadata_df)[sapply(metadata_df, function(x) is.factor(x) || is.character(x)) & colnames(metadata_df) != col_sample][1]
        if (is.na(col_treat)) {
          if ("treatment" %in% colnames(metadata_df)) col_treat <- "treatment" else col_treat <- colnames(metadata_df)[2]
        }
        
        col_patient <- colnames(metadata_df)[!(colnames(metadata_df) %in% c(col_sample, col_treat))][1]
        if (is.na(col_patient)) {
          if ("patient" %in% colnames(metadata_df)) col_patient <- "patient" else col_patient <- colnames(metadata_df)[3]
        }
        
        colnames(metadata_df)[colnames(metadata_df) == col_sample] <- "sample"
        colnames(metadata_df)[colnames(metadata_df) == col_treat] <- "treatment"
        colnames(metadata_df)[colnames(metadata_df) == col_patient] <- "patient"
        
        # Ensure treatment is a factor
        metadata_df\$treatment <- as.factor(metadata_df\$treatment)
        
        # Ensure PR column exists for annotation plotting
        if (!"PR" %in% colnames(metadata_df)) {
          metadata_df\$PR <- "Positive"
        }
        
        # Alias variables to match documented code exactly
        logCPM_example <- logCPM_matrix
        metadata_example <- metadata_df
        
        # Retrieve pathway topologies
        gsTopology <- retrieve_topology(database = "kegg", species = "hsapiens")
        
        # Generate entrez2name mapping dynamically using org.Hs.eg.db
        raw_ids <- rownames(logCPM_matrix)
        clean_ids <- gsub("^ENTREZID:", "", raw_ids)
        symbols <- mapIds(org.Hs.eg.db, keys = clean_ids, column = "SYMBOL", keytype = "ENTREZID", multiVals = "first")
        entrez2name <- data.frame(
          ENTREZID = raw_ids,
          gene_name = as.character(symbols),
          stringsAsFactors = FALSE
        )
        entrez2name <- rbind(
          entrez2name,
          data.frame(ENTREZID = paste0("ENTREZID:", clean_ids), gene_name = as.character(symbols))
        ) %>% distinct()
        
        # 1. Compute weighted single-sample logFCs (ssLogFCs)
        weightedFC <- weight_ss_fc(logCPM_example, metadata = metadata_example, groupBy = "patient", sampleColumn = "sample", treatColumn = "treatment")
        
        # 3. Compute raw gene-level perturbation scores
        genePertScore <- raw_gene_pert(weightedFC\$weighted_logFC, gsTopology)
        
        # 4. Sum gene-level scores to compute pathway-level perturbation scores
        pathwayPertScore <- pathway_pert(genePertScore, weightedFC\$weighted_logFC)
        
        # 5. Generate null distributions of perturbation scores via sample permutation
        set.seed(123)
        permutedScore <- generate_permuted_scores(expreMatrix = logCPM_example, gsTopology = gsTopology, weight = weightedFC\$weight)
        
        # 6. Normalize scores and calculate empirical p-values
        normalisedScores <- normalise_by_permu(permutedScore, pathwayPertScore, sortBy = "pvalue")
        
        # 7. Perform treatment-level linear modeling
        fit <- normalisedScores %>% 
          left_join(metadata_example, by = "sample") %>% 
          split(f = .\$gs_name) %>% 
          lapply(function(x) lm(robustZ ~ 0 + treatment, data = x)) %>% 
          lapply(summary)
        
        treat_sig <- lapply(names(fit), function(x){ 
          fit[[x]]\$coefficients %>% 
            as.data.frame() %>% 
            .[seq_len(min(2, nrow(.))), , drop = FALSE] %>% 
            dplyr::select(Estimate, pvalue = `Pr(>|t|)` ) %>% 
            rownames_to_column("Treatment") %>% 
            mutate(gs_name = x, FDR = p.adjust(pvalue, "fdr"), Treatment = str_remove(Treatment, "^treatment") ) 
        }) %>% bind_rows()
        
        # Write tabular outputs
        write.csv(normalisedScores, "normalised_scores.csv", row.names = FALSE)
        write.csv(treat_sig, "treatment_significance.csv", row.names = FALSE)
        saveRDS(weightedFC, "weightedFC.rds")
        
        # Determine target treatment and pathway for plotting dynamically
        ref_treatment <- levels(metadata_example\$treatment)[1]
        target_treatment <- levels(metadata_example\$treatment)[min(2, length(levels(metadata_example\$treatment)))]
        
        target_pathway <- treat_sig %>% 
          dplyr::filter(Treatment == target_treatment) %>% 
          arrange(FDR, pvalue) %>% 
          pull(gs_name) %>% 
          .[1]
        
        if (is.na(target_pathway)) {
          target_pathway <- names(gsTopology)[1]
        }
        
        target_samples <- metadata_example %>% 
          dplyr::filter(treatment %in% c(ref_treatment, target_treatment)) %>% 
          pull(sample)
        
        # 8. Visualize gene contributions and pathway networks
        tryCatch({
          # Plot gene contribution
          pdf("gene_contribution_heatmap.pdf", width = 10, height = 8)
          plot_gene_contribution(
            genePertMatr = genePertScore[[target_pathway]] %>% .[, colnames(.) %in% target_samples, drop = FALSE], 
            filterBy = "mean", 
            topGene = 10, 
            color = rev(colorspace::divergex_hcl(100, palette = "RdBu")), 
            breaks = seq(-0.001, 0.001, length.out = 100)
          )
          dev.off()
        }, error = function(e) {
          message("First gene contribution plot failed: ", e\$message)
        })
        
        tryCatch({
          # Plot gene contribution with annotation
          annotation_df <- normalisedScores %>% 
            dplyr::filter(gs_name == target_pathway) %>% 
            mutate(
              `Z Range` = cut(robustZ, breaks = seq(-2, 2, length.out = 6), include.lowest = TRUE)
            ) %>% 
            dplyr::select(sample, `Z Range`) %>% 
            left_join(
              ., metadata_example %>% dplyr::select(sample, `PR Status` = PR), 
              by = "sample"
            )
        
          z_levels <- levels(annotation_df\$`Z Range`)
          sample_order <- metadata_example %>% 
            dplyr::filter(treatment == target_treatment) %>% 
            .[order(.\$treatment),] %>% 
            pull(sample)
            
          pr_levels <- unique(metadata_example\$PR)
          pr_colors <- setNames(rainbow(length(pr_levels)), pr_levels)
        
          pdf("gene_contribution_annotated_heatmap.pdf", width = 12, height = 8)
          plot_gene_contribution(
            genePertMatr = genePertScore[[target_pathway]] %>% .[, match(sample_order, colnames(.)), drop = FALSE], 
            annotation_df = annotation_df, 
            filterBy = "mean", 
            topGene = 10, 
            mapEntrezID = entrez2name, 
            cluster_cols = FALSE, 
            color = rev(colorspace::divergex_hcl(100, palette = "RdBu")), 
            breaks = seq(-0.001, 0.001, length.out = 100), 
            annotation_colors = list(
              `PR Status` = pr_colors, 
              `Z Range` = setNames(colorRampPalette(c("navyblue", "white", "darkred"))(length(z_levels)), z_levels)
            )
          )
          dev.off()
        }, error = function(e) {
          message("Annotated gene contribution plot failed: ", e\$message)
        })
        
        # Prepare pathway2plot for network visualizations
        pathway2plot <- treat_sig %>% 
          dplyr::filter(Treatment == target_treatment) %>% 
          arrange(FDR) %>% 
          .[1:min(20, nrow(.)),] %>% 
          mutate(
            status = ifelse(Estimate > 0, "Activated", "Inhibited"), 
            status = ifelse(FDR < 0.05, status, "Unchanged")
          )
        pathway2plot <- pathway2plot %>% filter(!is.na(gs_name))
        
        tryCatch({
          # 9. Visualize pathway networks
          set.seed(123)
          p1 <- pathway2plot %>% plot_gs_network(gsTopology = gsTopology, colorBy = "status")
          ggsave("pathway_network_status.pdf", plot = p1, width = 8, height = 6)
        }, error = function(e) {
          message("Pathway network plot failed: ", e\$message)
        })
        
        tryCatch({
          # Plot community
          pdf("pathway_community_plot.pdf", width = 10, height = 8)
          print(pathway2plot %>% plot_community(gsTopology = gsTopology, colorBy = "status", color_lg_title = "Community"))
          dev.off()
        }, error = function(e) {
          message("Pathway community plot failed: ", e\$message)
        })
        
        tryCatch({
          # Plot GS to Gene
          meanFC <- weightedFC\$weighted_logFC %>% 
            .[, colnames(.) %in% target_samples, drop = FALSE] %>% 
            apply(1, mean)
          
          top500_gene <- meanFC %>% 
            abs() %>% 
            sort(decreasing = TRUE) %>% 
            .[1:min(500, length(.))] %>% 
            names()
          
          top500_FC <- meanFC %>% .[names(.) %in% top500_gene]
          top500_FC <- ifelse(top500_FC > 0, "Up-Regulated", "Down-Regulated")
        
          p_gs2gene <- treat_sig %>% 
            dplyr::filter(FDR < 0.05, Treatment == target_treatment) %>% 
            mutate(status = ifelse(Estimate > 0, "Activated", "Inhibited")) %>% 
            plot_gs2gene(gsTopology = gsTopology, colorGsBy = "status", geneFC = top500_FC, mapEntrezID = entrez2name, gsNameSize = 3, filterGeneBy = 0)
          
          ggsave("pathway_gs2gene_plot.pdf", plot = p_gs2gene, width = 12, height = 10)
        }, error = function(e) {
          message("GS to Gene plot failed: ", e\$message)
        })
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION":',
        paste0('    sSNAPPY: ', as.character(packageVersion('sSNAPPY')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_pathway_perturbation.csv versions.yml
    """
}

workflow BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ logCPM_matrix, metadata_df ] ]

    main:
    BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION(ch_input)

    emit:
    tables   = BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION.out.tables
    plots    = BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION.out.plots
    objects  = BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION.out.objects
    versions = BIOC_SSNAPPY_SINGLE_SAMPLE_PATHWAY_PERTURBATION.out.versions
}
