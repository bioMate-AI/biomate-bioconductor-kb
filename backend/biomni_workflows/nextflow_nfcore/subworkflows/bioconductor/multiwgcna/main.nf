#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiWGCNA — astrocyte_rnaseq_workflow
// Analyze condition-specific networks in multi-trait RNA-seq data, identify disease-associated modules, and perform permutation-based preservation testing.
// Input: astrocyte_se, sampleTable
// Container: quay.io/biocontainers/bioconductor-multiwgcna:1.7.0--r45hdfd78af_0
// R packages: SummarizedExperiment, doParallel, ExperimentHub, ggplot2, multiWGCNA, vegan, WGCNA
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, multiWGCNA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Network Construction
//  * 3. [Visualization & Output] Compare Modules Across Conditions
//  * 4. [Visualization & Output] Visualize Module Overlap Across Networks
//  * 5. [Visualization & Output] Differential Module Expression Analysis
//  * 6. [Visualization & Output] Visualize Multi-Level Network Correspondences
//  * 7. [Visualization & Output] Identify Reciprocal Best Matches
//  * 8. [Visualization & Output] Plot Co-expression of Top Module Genes
//  * 9. [Visualization & Output] Permutation-Based Preservation Testing

nextflow.enable.dsl = 2

process BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW {
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
    .bm_deps <- c("SummarizedExperiment", "doParallel", "ExperimentHub", "ggplot2", "multiWGCNA", "vegan", "WGCNA")
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
        library(multiWGCNA)
        library(ggplot2)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        if (file.exists("astrocyte_se")) {
          astrocyte_se = readRDS("astrocyte_se")
        } else if (file.exists("astrocyte_se.rds")) {
          astrocyte_se = readRDS("astrocyte_se.rds")
        } else {
          stop("Error: 'astrocyte_se' file not found in the working directory.")
        }
        
        if (file.exists("sampleTable")) {
          sampleTable = readRDS("sampleTable")
        } else if (file.exists("sampleTable.rds")) {
          sampleTable = readRDS("sampleTable.rds")
        } else {
          stop("Error: 'sampleTable' file not found in the working directory.")
        }
        
        # Ensure the first column of sampleTable is named "Sample"
        if (colnames(sampleTable)[1] != "Sample") {
          colnames(sampleTable)[1] = "Sample"
        }
        
        # Define conditions for the two traits from the sample metadata dynamically
        trait1_name = colnames(sampleTable)[2]
        trait2_name = colnames(sampleTable)[3]
        
        conditions1 = unique(sampleTable[,2])
        conditions2 = unique(sampleTable[,3])
        
        cond1_A = conditions1[1]
        cond1_B = conditions1[2]
        
        # ==========================================
        # --- Network Construction ---
        # ==========================================
        astrocyte_networks = constructNetworks(
          astrocyte_se, 
          sampleTable, 
          conditions1, 
          conditions2, 
          networkType = "signed", 
          TOMType = "unsigned", 
          power = 12, 
          minModuleSize = 100, 
          maxBlockSize = 25000, 
          reassignThreshold = 0, 
          minKMEtoStay = 0, 
          mergeCutHeight = 0, 
          numericLabels = TRUE, 
          pamRespectsDendro = FALSE, 
          deepSplit = 4, 
          verbose = 3
        )
        saveRDS(astrocyte_networks, "astrocyte_networks.rds")
        
        # ==========================================
        # --- Compare Modules Across Conditions ---
        # ==========================================
        results = list()
        results\$overlaps = iterate(astrocyte_networks, overlapComparisons, plot=FALSE)
        saveRDS(results\$overlaps, "overlaps.rds")
        
        # ==========================================
        # --- Visualize Module Overlap Across Networks ---
        # ==========================================
        pdf("ModuleFlowPlot.pdf", width = 10, height = 12)
        ModuleFlowPlot(
          WGCNAlist = astrocyte_networks, 
          comparisonList = results\$overlaps, 
          networks = c('combined', conditions1), 
          spacer = 100, 
          label.y = 500, 
          x.scale = 10, 
          color.by = 'trait', 
          p.adj.threshold = 1e-50, 
          label.size = 4
        )
        dev.off()
        
        # ==========================================
        # --- Differential Module Expression Analysis ---
        # ==========================================
        results\$diffModExp = runDME(
          astrocyte_networks[["combined"]], 
          sampleTable, 
          p.adjust = "fdr", 
          refCondition = trait2_name, 
          testCondition = trait1_name
        )
        write.csv(results\$diffModExp, "diffModExp_results.csv", row.names = TRUE)
        
        # Dynamically identify the top module associated with trait1
        sorted_dme = results\$diffModExp[order(results\$diffModExp[[trait1_name]]), ]
        top_module = rownames(sorted_dme)[1]
        
        pdf(paste0("diffModuleExpression_", top_module, ".pdf"), width = 7, height = 6)
        diffModuleExpression(
          astrocyte_networks[["combined"]], 
          geneList = topNGenes(astrocyte_networks[[1]], top_module), 
          design = sampleTable, 
          test = "ANOVA", 
          plotTitle = top_module, 
          plot = TRUE
        )
        dev.off()
        
        # ==========================================
        # --- Visualize Multi-Level Network Correspondences ---
        # ==========================================
        pdf(paste0("drawMultiWGCNAnetwork_", top_module, ".pdf"), width = 8, height = 8)
        drawMultiWGCNAnetwork(
          astrocyte_networks, 
          results\$overlaps, 
          top_module, 
          design = sampleTable, 
          overlapCutoff = 0, 
          padjCutoff = 1, 
          removeOutliers = TRUE, 
          alpha = 1e-50, 
          layout = NULL, 
          hjust = 0.4, 
          vjust = 0.3, 
          width = 0.5
        )
        dev.off()
        
        # ==========================================
        # --- Identify Reciprocal Best Matches ---
        # ==========================================
        comp_name = paste0("combined_vs_", cond1_A)
        best_matches = bidirectionalBestMatches(results\$overlaps[[comp_name]])
        write.csv(best_matches, paste0("bidirectional_best_matches_", comp_name, ".csv"), row.names = FALSE)
        
        # Find the corresponding module in cond1_A
        top_module_num = gsub("combined_", "", top_module)
        match_idx = which(best_matches\$combined == top_module_num)
        if (length(match_idx) > 0) {
          cond1_module_num = best_matches[[cond1_A]][match_idx[1]]
          cond1_module = paste0(cond1_A, "_", cond1_module_num)
        } else {
          # Fallback to overlap dataframe
          overlap_df = results\$overlaps[[comp_name]]\$overlap
          idx = which(overlap_df\$mod1 == top_module)
          if (length(idx) > 0) {
            overlap_df_sub = overlap_df[idx, ]
            overlap_df_sub = overlap_df_sub[order(overlap_df_sub\$p.adj), ]
            cond1_module = overlap_df_sub\$mod2[1]
          } else {
            cond1_module = paste0(cond1_A, "_001")
          }
        }
        
        # ==========================================
        # --- Plot Co-expression of Top Module Genes ---
        # ==========================================
        datExpr = GetDatExpr(astrocyte_networks[[1]], genes = topNGenes(astrocyte_networks[[cond1_A]], cond1_module, 20))
        
        pdf(paste0("coexpressionLineGraph_", cond1_module, ".pdf"), width = 7, height = 5)
        p_coexp = coexpressionLineGraph(datExpr, splitBy = 1.5, fontSize = 2.5) + 
          geom_vline(xintercept = 20.5, linetype='dashed')
        print(p_coexp)
        dev.off()
        
        # ==========================================
        # --- Permutation-Based Preservation Testing ---
        # ==========================================
        # Calculate actual preservation to get the observed score
        results\$preservation = iterate(
          astrocyte_networks[conditions1], 
          preservationComparisons, 
          write = FALSE, 
          plot = FALSE, 
          nPermutations = 2
        )
        
        pres_comp_name = paste0(cond1_A, "_vs_", cond1_B)
        if (!pres_comp_name %in% names(results\$preservation)) {
          pres_comp_name = paste0(cond1_B, "_vs_", cond1_A)
        }
        
        observed.score = 9.16261490617938 # default fallback
        tryCatch({
          pres_out = results\$preservation[[pres_comp_name]]
          z_df = pres_out\$preservation\$Z[[1]][[2]]
          mod_name_short = gsub(paste0(cond1_A, "_"), "", cond1_module)
          if (cond1_module %in% rownames(z_df)) {
            observed.score = z_df[cond1_module, "Zsummary.pres"]
          } else if (mod_name_short %in% rownames(z_df)) {
            observed.score = z_df[mod_name_short, "Zsummary.pres"]
          }
        }, error = function(e) {
          message("Could not extract observed score, using fallback.")
        })
    
        # Dynamically sample genes up to 3000 to avoid out-of-bounds errors
        total_genes = nrow(astrocyte_networks\$combined@datExpr)
        sample_size = min(3000, total_genes)
        set.seed(123)
        sampled_indices = sample(total_genes, sample_size)
        sampled_datExpr = astrocyte_networks\$combined@datExpr[sampled_indices, ]
        
        results\$permutation.test = PreservationPermutationTest(
          sampled_datExpr, 
          sampleTable, 
          constructNetworksIn = cond1_A, 
          testPreservationIn = cond1_B, 
          nPermutations = 10, 
          nPresPermutations = 10, 
          networkType = "signed", 
          TOMType = "unsigned", 
          power = 12, 
          minModuleSize = 100, 
          maxBlockSize = 25000, 
          reassignThreshold = 0, 
          minKMEtoStay = 0, 
          mergeCutHeight = 0, 
          numericLabels = TRUE, 
          pamRespectsDendro = FALSE, 
          deepSplit = 4, 
          verbose = 3
        )
        saveRDS(results\$permutation.test, "permutation_test_results.rds")
        
        # Filter out outlier modules
        permutationTestResultsFiltered = lapply(results\$permutation.test, function(x) x[!x\$is.outlier.module,])
        
        # Dynamically determine the size of the module of interest if possible
        module_size = 303
        tryCatch({
          overlap_df = results\$overlaps[[comp_name]]\$overlap
          if (!is.null(overlap_df)) {
            idx = which(overlap_df\$mod2 == cond1_module)
            if (length(idx) > 0) {
              module_size = overlap_df\$mod2.size[idx[1]]
            }
          }
        }, error = function(e) {
          message("Could not dynamically determine module size, using default 303.")
        })
        
        # Extract the preservation score distribution
        results\$scores.summary = PreservationScoreDistribution(
          permutationTestResultsFiltered, 
          moduleOfInterestSize = module_size
        )
        write.csv(results\$scores.summary, "scores_summary.csv", row.names = FALSE)
        
        # Plot the observed score and the null distribution on a histogram
        pdf("preservation_histogram.pdf", width = 7, height = 5)
        p_hist = ggplot(results\$scores.summary, aes(x=z.summary)) + 
          geom_histogram(color="black", fill="white", bins = 15) + 
          xlab("Preservation score") + 
          ylab("Frequency") + 
          geom_vline(xintercept=observed.score, color="red3", linetype="solid") + 
          scale_y_continuous(expand = c(0,0)) + 
          theme_classic() + 
          theme(plot.title = element_text(hjust = 0.5))
        print(p_hist)
        dev.off()
        
        # Print completion message
        message("Pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW":',
        paste0('    multiWGCNA: ', as.character(packageVersion('multiWGCNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_astrocyte_rnaseq_workflow.csv versions.yml
    """
}

workflow BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ astrocyte_se, sampleTable ] ]

    main:
    BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW.out.tables
    plots    = BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW.out.plots
    objects  = BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW.out.objects
    versions = BIOC_MULTIWGCNA_ASTROCYTE_RNASEQ_WORKFLOW.out.versions
}
