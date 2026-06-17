#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNERO — gene_coexpression_network
// Preprocess expression data, infer a weighted gene coexpression network, identify modules, correlate them with traits, perform enrichment, and identify hub genes
// Input: zma.se, zma.interpro
// Container: quay.io/biocontainers/bioconductor-bionero:1.18.0--r45hdfd78af_0
// R packages: SummarizedExperiment, BioNERO
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNERO, ComplexHeatmap, SummarizedExperiment, htmlwidgets
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess data step-by-step or automatically using exp_preprocess()
//  * 2. [Visualization & Output] Perform exploratory analysis with plot_heatmap() and plot_PCA()
//  * 3. [Core Analysis] Determine scale-free topology fit power using SFT_fit()
//  * 4. [Core Analysis] Infer gene coexpression network using exp2gcn()
//  * 5. [Visualization & Output] Visualize network properties using plot_dendro_and_colors(), plot_eigengene_network(), and plot_ngenes_per_module()
//  * 6. [Core Analysis] Assess module stability using module_stability()
//  * 7. [Visualization & Output] Calculate module-trait correlations using module_trait_cor() and visualize with plot_module_trait_cor()
//  * 8. [Core Analysis] Perform functional enrichment analysis using module_enrichment()
//  * 9. [Core Analysis] Identify hub genes using get_hubs_gcn()
//  * 10. [Visualization & Output] Extract and filter subgraphs using get_edge_list() and visualize using plot_gcn()

nextflow.enable.dsl = 2

process BIOC_BIONERO_GENE_COEXPRESSION_NETWORK {
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
    .bm_deps <- c("SummarizedExperiment", "BioNERO")
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
        library(BioNERO)
        
        # Set seed for reproducibility
        set.seed(123)
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        # Read the SummarizedExperiment object and Interpro annotation data frame
        zma.se <- readRDS("zma.se")
        zma.interpro <- readRDS("zma.interpro")
        
        # ==========================================
        # 2. Data Preprocessing
        # ==========================================
        # Step-by-step data preprocessing
        exp_filt <- replace_na(zma.se)
        exp_filt <- remove_nonexp(exp_filt, method = "median", min_exp = 10)
        exp_filt <- filter_by_variance(exp_filt, n = 2000)
        exp_filt <- ZKfiltering(exp_filt, cor_method = "pearson")
        exp_filt <- PC_correction(exp_filt)
        
        # Automatic, one-step data preprocessing
        final_exp <- exp_preprocess(
            zma.se, min_exp = 10, variance_filter = TRUE, n = 2000
        )
        
        # Save preprocessed expression data
        saveRDS(final_exp, "final_exp.rds")
        
        # ==========================================
        # 3. Exploratory Data Analysis
        # ==========================================
        pdf("exploratory_analysis.pdf", width = 7, height = 6)
        
        p1 <- plot_heatmap(final_exp, type = "samplecor", show_rownames = FALSE)
        grid::grid.newpage()
        ComplexHeatmap::draw(p1)
        
        p2 <- plot_heatmap(
            final_exp[1:50, ], type = "expr", show_rownames = FALSE, show_colnames = FALSE
        )
        grid::grid.newpage()
        ComplexHeatmap::draw(p2)
        
        print(plot_PCA(final_exp))
        
        dev.off()
        
        # ==========================================
        # 4. Gene Coexpression Network Inference
        # ==========================================
        sft <- SFT_fit(final_exp, net_type = "signed hybrid", cor_method = "pearson")
        power <- sft\$power
        
        # Save SFT plot
        pdf("sft_fit_plot.pdf", width = 8, height = 6)
        plot(sft\$plot)
        dev.off()
        
        net <- exp2gcn(
            final_exp, net_type = "signed hybrid", SFTpower = power, 
            cor_method = "pearson"
        )
        
        # Save network object
        saveRDS(net, "gcn_network.rds")
        
        # ==========================================
        # 5. Visualizing Network Properties
        # ==========================================
        pdf("network_properties.pdf", width = 8, height = 6)
        plot_dendro_and_colors(net)
        print(plot_eigengene_network(net))
        print(plot_ngenes_per_module(net))
        dev.off()
        
        # ==========================================
        # 6. Assessing Module Stability
        # ==========================================
        # This function automatically saves a PDF named "module_stability_plot.pdf" (or similar) in the working directory
        tryCatch({
            module_stability(final_exp, net, nRuns = 5)
        }, error = function(e) {
            warning("Module stability assessment failed: ", e\$message)
        })
        
        # ==========================================
        # 7. Module-Trait Associations
        # ==========================================
        MEtrait <- module_trait_cor(exp = final_exp, MEs = net\$MEs)
        write.csv(MEtrait, "module_trait_correlations.csv", row.names = FALSE)
        
        pdf("module_trait_associations.pdf", width = 7, height = 7)
        print(plot_module_trait_cor(MEtrait))
        
        # Dynamically select a module for expression profile
        available_modules <- gsub("^ME", "", colnames(net\$MEs))
        available_modules <- available_modules[available_modules != "grey"]
        if(length(available_modules) == 0) available_modules <- "grey"
        mod_profile <- available_modules[1]
        
        # Wrap in tryCatch in case the module is not present in the generated network
        tryCatch({
            print(plot_expression_profile(
                exp = final_exp, 
                net = net, 
                plot_module = TRUE, 
                modulename = mod_profile
            ))
        }, error = function(e) {
            warning("Could not plot expression profile for '", mod_profile, "' module: ", e\$message)
        })
        dev.off()
        
        # ==========================================
        # 8. Enrichment Analysis
        # ==========================================
        interpro_enrichment <- module_enrichment(
            net = net, 
            background_genes = rownames(final_exp),
            annotation = zma.interpro
        )
        write.csv(interpro_enrichment, "interpro_enrichment_results.csv", row.names = FALSE)
        
        # ==========================================
        # 9. Hub Gene Identification
        # ==========================================
        hubs <- get_hubs_gcn(final_exp, net)
        write.csv(hubs, "hub_genes.csv", row.names = FALSE)
        
        # ==========================================
        # 10. Extracting Subgraphs and Visualization
        # ==========================================
        # Dynamically select a module for subgraph extraction
        mod_subgraph <- available_modules[min(2, length(available_modules))]
        
        # Wrap in tryCatch in case the module is not present in the generated network
        tryCatch({
            edges <- get_edge_list(net, module = mod_subgraph)
            write.csv(edges, paste0("edges_", mod_subgraph, "_all.csv"), row.names = FALSE)
        
            edges_filtered <- get_edge_list(net, module = mod_subgraph, filter = TRUE)
            write.csv(edges_filtered, paste0("edges_", mod_subgraph, "_filtered_sft.csv"), row.names = FALSE)
        
            edges_filtered_pvalue <- get_edge_list(
                net, module = mod_subgraph,
                filter = TRUE, method = "pvalue", 
                nSamples = ncol(final_exp)
            )
            write.csv(edges_filtered_pvalue, paste0("edges_", mod_subgraph, "_filtered_pvalue.csv"), row.names = FALSE)
        
            edges_filtered_mincor <- get_edge_list(
                net, module = mod_subgraph, 
                filter = TRUE, method = "min_cor", rcutoff = 0.7
            )
            write.csv(edges_filtered_mincor, paste0("edges_", mod_subgraph, "_filtered_mincor.csv"), row.names = FALSE)
        
            # Static Network Visualization
            pdf("gcn_network_visualization.pdf", width = 7, height = 7)
            print(plot_gcn(
                edgelist_gcn = edges_filtered, 
                net = net, 
                color_by = "module", 
                hubs = hubs
            ))
            dev.off()
        
            # Interactive Network Visualization
            p_interactive <- plot_gcn(
                edgelist_gcn = edges_filtered, 
                net = net,
                color_by = "module",
                hubs = hubs,
                interactive = TRUE,
                dim_interactive = c(500, 500)
            )
            
            if (requireNamespace("htmlwidgets", quietly = TRUE)) {
                htmlwidgets::saveWidget(p_interactive, "gcn_interactive_visualization.html")
            }
        
        }, error = function(e) {
            warning("Subgraph extraction or visualization failed: ", e\$message)
        })

    writeLines(c(
        '"BIOC_BIONERO_GENE_COEXPRESSION_NETWORK":',
        paste0('    BioNERO: ', as.character(packageVersion('BioNERO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_coexpression_network.csv versions.yml
    """
}

workflow BIOC_BIONERO_GENE_COEXPRESSION_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zma.se, zma.interpro ] ]

    main:
    BIOC_BIONERO_GENE_COEXPRESSION_NETWORK(ch_input)

    emit:
    tables   = BIOC_BIONERO_GENE_COEXPRESSION_NETWORK.out.tables
    plots    = BIOC_BIONERO_GENE_COEXPRESSION_NETWORK.out.plots
    objects  = BIOC_BIONERO_GENE_COEXPRESSION_NETWORK.out.objects
    versions = BIOC_BIONERO_GENE_COEXPRESSION_NETWORK.out.versions
}
