#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MesKit — phylogenetic_and_signature_analysis
// Reconstruct phylogenetic trees, perform functional enrichment of branch-specific mutations, analyze mutational signatures, and visualize trees with mutational h
// Input: maf, BSgenome.Hsapiens.UCSC.hg19
// Container: quay.io/biocontainers/bioconductor-meskit:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, ComplexHeatmap, MesKit, clusterProfiler, cowplot, ggplot2, org.Hs.eg.db
// Visualizations: dot plot, heatmap (ComplexHeatmap), enrichment plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Reconstruct phylogenetic trees using getPhyloTree
//  * 2. [Visualization & Output] Compare trees constructed with different methods using
//  * 3. [Visualization & Output] Extract branch-specific mutations using getMutBranches
//  * 4. [Visualization & Output] Analyze trunk vs. branch mutation spectrum using
//  * 5. [Visualization & Output] Generate a 96-trinucleotide mutation matrix using
//  * 6. [Visualization & Output] Fit mutational signatures and estimate contributions
//  * 7. [Visualization & Output] Plot original and reconstructed mutational signature
//  * 8. [Visualization & Output] Visualize the phylogenetic tree annotated with mutation

nextflow.enable.dsl = 2

process BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(MesKit)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(org.Hs.eg.db)
    library(clusterProfiler)
    library(ComplexHeatmap)
    library(cowplot)
    library(ggplot2)
    
    # Read the Maf object from the working directory
    if (!file.exists("maf.rds")) {
      stop("Error: 'maf.rds' file not found in the working directory.")
    }
    maf <- readRDS("maf.rds")
    
    # Extract patient ID dynamically
    patient_id <- NULL
    if (inherits(maf, "MafList")) {
      patient_id <- names(maf)[1]
    } else {
      # Try to get patient ID from mathScore which returns a list named by patient IDs
      try({
        ms <- mathScore(maf)
        if (is.list(ms) && length(names(ms)) > 0) {
          patient_id <- names(ms)[1]
        }
      }, silent = TRUE)
      
      # Fallback to S4 slots if mathScore fails
      if (is.null(patient_id)) {
        if (.hasSlot(maf, "clinical.data") && "Patient_ID" %in% colnames(maf@clinical.data)) {
          patient_id <- as.character(maf@clinical.data\$Patient_ID[1])
        } else if (.hasSlot(maf, "data") && "Patient_ID" %in% colnames(maf@data)) {
          patient_id <- as.character(maf@data\$Patient_ID[1])
        } else if (.hasSlot(maf, "clin") && "Patient_ID" %in% colnames(maf@clin)) {
          patient_id <- as.character(maf@clin\$Patient_ID[1])
        }
      }
    }
    
    if (is.null(patient_id) || is.na(patient_id)) {
      stop("Error: Could not determine patient ID from the maf object.")
    }
    
    # --- Reconstruct phylogenetic trees using getPhyloTree ---
    phyloTree <- getPhyloTree(maf, patient.id = patient_id, method = "NJ", min.vaf = 0.06)
    tree.NJ <- getPhyloTree(maf, patient.id = patient_id, method = "NJ")
    tree.MP <- getPhyloTree(maf, patient.id = patient_id, method = "MP")
    
    # Save reconstructed trees
    saveRDS(phyloTree, "phyloTree.rds")
    saveRDS(tree.NJ, "tree_NJ.rds")
    saveRDS(tree.MP, "tree_MP.rds")
    
    # --- Compare trees constructed with different methods using ---
    comp_tree_res <- compareTree(tree.NJ, tree.MP, plot = TRUE, use.tumorSampleLabel = TRUE)
    
    # Save comparison results
    write.csv(as.data.frame(t(comp_tree_res\$compare.dist)), "compare_tree_dist.csv")
    pdf("compare_tree_plot.pdf", width = 10, height = 6)
    print(comp_tree_res\$compare.plot)
    dev.off()
    
    # --- Extract branch-specific mutations using getMutBranches ---
    branches_res <- getMutBranches(phyloTree)
    write.csv(branches_res, "branches.csv", row.names = FALSE)
    
    # Dynamically select a mutation type for enrichment (fallback to all if none found)
    if (nrow(branches_res) > 0 && "Mutation_Type" %in% colnames(branches_res)) {
      target_mut_type <- branches_res\$Mutation_Type[1]
      branches_subset <- branches_res[branches_res\$Mutation_Type == target_mut_type, ]
    } else {
      branches_subset <- branches_res
    }
    
    # Perform pathway enrichment analysis with error handling
    tryCatch({
      if (nrow(branches_subset) > 0) {
        geneIDs <- suppressMessages(bitr(branches_subset\$Hugo_Symbol, fromType = "SYMBOL", 
                                         toType = c("ENTREZID"), OrgDb = "org.Hs.eg.db"))
        if (nrow(geneIDs) > 0) {
          kegg_res <- enrichKEGG(
            gene = geneIDs\$ENTREZID,
            organism = 'hsa',
            keyType = 'kegg',
            pvalueCutoff = 0.05
          )
          if (!is.null(kegg_res) && nrow(as.data.frame(kegg_res)) > 0) {
            write.csv(as.data.frame(kegg_res), "KEGG_enrichment.csv", row.names = FALSE)
            pdf("KEGG_enrichment_dotplot.pdf", width = 8, height = 6)
            print(dotplot(kegg_res))
            dev.off()
          } else {
            message("No significant KEGG pathways found.")
          }
        } else {
          message("No Entrez IDs mapped for the input gene symbols.")
        }
      } else {
        message("No mutations found for pathway enrichment.")
      }
    }, error = function(e) {
      message("KEGG enrichment analysis failed: ", e\$message)
    })
    
    # --- Analyze trunk vs. branch mutation spectrum using ---
    mutClass <- mutTrunkBranch(phyloTree, CT = TRUE, plot = TRUE)
    
    # Save trunk/branch mutation spectrum results
    write.csv(mutClass\$mutTrunkBranch.res, "mutTrunkBranch_res.csv", row.names = FALSE)
    pdf("mutTrunkBranch_plot.pdf", width = 8, height = 6)
    print(mutClass\$mutTrunkBranch.plot)
    dev.off()
    
    # --- Generate a 96-trinucleotide mutation matrix using ---
    trimatrix_res <- triMatrix(phyloTree, level = 5)
    saveRDS(trimatrix_res, "trimatrix_res.rds")
    
    # Plot original mutational signature profile
    pdf("original_mut_sig_profile.pdf", width = 10, height = 6)
    print(plotMutSigProfile(trimatrix_res)[[1]])
    dev.off()
    
    # --- Fit mutational signatures and estimate contributions ---
    fit_res <- fitSignatures(trimatrix_res, signaturesRef = "cosmic_v2")
    saveRDS(fit_res, "fit_res.rds")
    
    # --- Plot original and reconstructed mutational signature ---
    pdf("reconstructed_mut_sig_profile.pdf", width = 10, height = 6)
    print(plotMutSigProfile(fit_res)[[1]])
    dev.off()
    
    # Save cosine similarity heatmap
    pdf("cosine_similarity_heatmap.pdf", width = 8, height = 6)
    draw(ComplexHeatmap::Heatmap(fit_res[[patient_id]]\$cosine.similarity, name = "Cosine similarity"))
    dev.off()
    
    # --- Visualize the phylogenetic tree annotated with mutation ---
    phylotree_plot <- plotPhyloTree(phyloTree, use.tumorSampleLabel = TRUE)
    binary_heatmap <- mutHeatmap(maf, min.ccf = 0.04, use.ccf = FALSE, patient.id = patient_id, use.tumorSampleLabel = TRUE)
    CCF_heatmap <- mutHeatmap(maf, use.ccf = TRUE, patient.id = patient_id, 
                                   min.ccf = 0.04, use.tumorSampleLabel = TRUE)
    
    # Save combined phylogenetic tree and heatmap plot
    pdf("phylo_tree_with_heatmaps.pdf", width = 14, height = 8)
    print(cowplot::plot_grid(phylotree_plot, binary_heatmap,
                             CCF_heatmap, nrow = 1, rel_widths = c(1.5, 1, 1)))
    dev.off()
    
    message("Pipeline completed successfully. All outputs have been saved to the working directory.")

    writeLines(c(
        '"BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS":',
        paste0('    MesKit: ', as.character(packageVersion('MesKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phylogenetic_and_signature_analysis.csv versions.yml
    """
}

workflow BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maf, BSgenome.Hsapiens.UCSC.hg19 ] ]

    main:
    BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS.out.tables
    plots    = BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS.out.plots
    objects  = BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS.out.objects
    versions = BIOC_MESKIT_PHYLOGENETIC_AND_SIGNATURE_ANALYSIS.out.versions
}
