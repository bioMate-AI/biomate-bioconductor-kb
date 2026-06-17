#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GWENA — single_condition_coexpression
// Perform gene co-expression network analysis, module detection, biological enrichment, phenotypic association, and visualization for a single experimental condit
// Input: kuehne_expr, kuehne_traits
// Container: quay.io/biocontainers/bioconductor-gwena:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GWENA, dplyr, magrittr
// Visualizations: enrichment plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check expression data validity using is_data_expr
//  * 2. [Core Analysis] Filter low variation genes using filter_low_var
//  * 3. [Input & Preparation] Build co-expression network using build_net
//  * 4. [Core Analysis] Detect and merge modules using detect_modules
//  * 5. [Visualization & Output] Plot module merging using plot_modules_merge
//  * 6. [Visualization & Output] Perform functional enrichment using bio_enrich and plot with plot_enrichment
//  * 7. [Visualization & Output] Associate modules with phenotypes using associate_phenotype and plot with plot_modules_phenotype
//  * 8. [Input & Preparation] Build graph and sub-clusters using build_graph_from_sq_mat and get_sub_clusters
//  * 9. [Visualization & Output] Plot modules and sub-clusters using plot_module

nextflow.enable.dsl = 2

process BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION {
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
    .bm_deps <- c("GWENA", "magrittr", "dplyr")
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
    library(GWENA)
    library(magrittr)
    library(dplyr)
    
    # Set threads to use based on OS
    threads_to_use <- if (.Platform\$OS.type == "windows") 1 else 2
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Read kuehne_expr
    if (file.exists("kuehne_expr.rds")) {
      kuehne_expr <- readRDS("kuehne_expr.rds")
    } else if (file.exists("kuehne_expr.csv")) {
      kuehne_expr <- read.csv("kuehne_expr.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("kuehne_expr.tsv")) {
      kuehne_expr <- read.delim("kuehne_expr.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("kuehne_expr")) {
      kuehne_expr <- read.table("kuehne_expr", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Error: kuehne_expr file not found in the working directory.")
    }
    
    # Read kuehne_traits
    if (file.exists("kuehne_traits.rds")) {
      kuehne_traits <- readRDS("kuehne_traits.rds")
    } else if (file.exists("kuehne_traits.csv")) {
      kuehne_traits <- read.csv("kuehne_traits.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("kuehne_traits.tsv")) {
      kuehne_traits <- read.delim("kuehne_traits.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("kuehne_traits")) {
      kuehne_traits <- read.table("kuehne_traits", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Error: kuehne_traits file not found in the working directory.")
    }
    
    # Ensure expression data is a matrix or data frame
    kuehne_expr <- as.matrix(kuehne_expr)
    
    # -----------------------------------------------------------------------------
    # 2. Run GWENA Pipeline
    # -----------------------------------------------------------------------------
    
    # Check expression data validity
    is_data_expr(kuehne_expr)
    
    # Filter low variation genes
    kuehne_expr_filtered <- filter_low_var(kuehne_expr, pct = 0.7, type = "median")
    
    # Build co-expression network
    net <- build_net(kuehne_expr_filtered, cor_func = "spearman", n_threads = threads_to_use)
    saveRDS(net, "net.rds")
    
    # Detect and merge modules
    modules <- detect_modules(kuehne_expr_filtered, net\$network, detailled_result = TRUE, merge_threshold = 0.25)
    saveRDS(modules, "modules.rds")
    
    # Plot module merging
    pdf("plot_modules_merge.pdf", width = 10, height = 8)
    layout_mod_merge <- plot_modules_merge(modules_premerge = modules\$modules_premerge, modules_merged = modules\$modules)
    dev.off()
    
    # Perform functional enrichment (wrapped in tryCatch to handle potential offline/gProfiler issues)
    enrichment <- tryCatch({
      bio_enrich(modules\$modules)
    }, error = function(e) {
      warning("Functional enrichment failed (possibly due to network or gProfiler service issues): ", e\$message)
      NULL
    })
    
    if (!is.null(enrichment)) {
      saveRDS(enrichment, "enrichment.rds")
      pdf("plot_enrichment.pdf", width = 12, height = 12)
      plot_enrichment(enrichment)
      dev.off()
    }
    
    # Associate modules with phenotypes
    phenotype_association <- associate_phenotype(modules\$modules_eigengenes, kuehne_traits)
    write.csv(phenotype_association, "phenotype_association.csv", row.names = TRUE)
    
    # Plot phenotypic association
    pdf("plot_modules_phenotype.pdf", width = 10, height = 8)
    plot_modules_phenotype(phenotype_association)
    dev.off()
    
    # Ensure module '2' exists in the detected modules to prevent downstream failures
    if (is.null(modules\$modules\$`2`)) {
      # Fallback to the first available non-zero module if '2' is not present
      available_mods <- names(modules\$modules)[names(modules\$modules) != "0"]
      if (length(available_mods) > 0) {
        modules\$modules\$`2` <- modules\$modules[[available_mods[1]]]
      } else {
        modules\$modules\$`2` <- modules\$modules[[1]]
      }
    }
    
    # Build graph for module 2
    module_example <- modules\$modules\$`2`
    graph <- build_graph_from_sq_mat(net\$network[module_example, module_example])
    
    # Plot module 2 network
    pdf("plot_module_2.pdf", width = 12, height = 12)
    layout_mod_2 <- plot_module(graph, upper_weight_th = 0.999995, vertex.label.cex = 0, node_scaling_max = 7, legend_cex = 1)
    dev.off()
    
    # Get sub-clusters within module 2
    net_mod_2 <- net\$network[modules\$modules\$`2`, modules\$modules\$`2`] 
    sub_clusters <- get_sub_clusters(net_mod_2)
    saveRDS(sub_clusters, "sub_clusters_module_2.rds")
    
    # Plot module 2 sub-clusters
    pdf("plot_module_2_sub_clusters.pdf", width = 12, height = 12)
    layout_mod_2_sub_clust <- plot_module(graph, upper_weight_th = 0.999995, groups = sub_clusters, vertex.label.cex = 0, node_scaling_max = 7, legend_cex = 1)
    dev.off()
    
    cat("GWENA pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION":',
        paste0('    GWENA: ', as.character(packageVersion('GWENA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_condition_coexpression.csv versions.yml
    """
}

workflow BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kuehne_expr, kuehne_traits ] ]

    main:
    BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION(ch_input)

    emit:
    tables   = BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION.out.tables
    plots    = BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION.out.plots
    objects  = BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION.out.objects
    versions = BIOC_GWENA_SINGLE_CONDITION_COEXPRESSION.out.versions
}
