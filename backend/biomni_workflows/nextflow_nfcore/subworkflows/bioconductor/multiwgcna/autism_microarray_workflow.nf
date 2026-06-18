#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: multiWGCNA — autism_microarray_workflow
// Analyze multi-trait microarray data, track gene recruitment across networks using TOM flow plots, and summarize differentially expressed and non-preserved modul
// Input: autism_se, sampleTable
// Container: quay.io/biocontainers/bioconductor-multiwgcna:1.7.0--r45hdfd78af_0
// R packages: SummarizedExperiment, ggalluvial, ggplot2, multiWGCNA
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggalluvial, ggplot2, multiWGCNA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define conditions for the two traits from the sample metadata. 2. Construct combined and condition-specific networks using constru

nextflow.enable.dsl = 2

process BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW {
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
    .bm_deps <- c("SummarizedExperiment", "ggalluvial", "ggplot2", "multiWGCNA")
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
    library(multiWGCNA)
    library(ggplot2)
    library(ggalluvial)
    
    # Read user input files from the working directory
    if (file.exists("autism_se")) {
      autism_se <- readRDS("autism_se")
    } else if (file.exists("autism_se.rds")) {
      autism_se <- readRDS("autism_se.rds")
    } else {
      stop("Required input file 'autism_se' or 'autism_se.rds' not found in the working directory.")
    }
    
    if (file.exists("sampleTable")) {
      sampleTable <- readRDS("sampleTable")
    } else if (file.exists("sampleTable.rds")) {
      sampleTable <- readRDS("sampleTable.rds")
    } else {
      stop("Required input file 'sampleTable' or 'sampleTable.rds' not found in the working directory.")
    }
    
    # Define conditions for the two traits dynamically
    conditions1 = as.character(unique(sampleTable[,2]))
    conditions2 = as.character(unique(sampleTable[,3]))
    
    # Construct combined and condition-specific networks
    autism_networks = constructNetworks(
      autism_se, 
      sampleTable, 
      conditions1, 
      conditions2, 
      networkType = "unsigned", 
      power = 10, 
      minModuleSize = 40, 
      maxBlockSize = 25000, 
      reassignThreshold = 0, 
      minKMEtoStay = 0.7, 
      mergeCutHeight = 0.10, 
      numericLabels = TRUE, 
      pamRespectsDendro = FALSE, 
      verbose = 3, 
      saveTOMs = TRUE
    )
    
    # Save the constructed networks
    saveRDS(autism_networks, "autism_networks.rds")
    
    # Compare modules across conditions by hypergeometric overlap
    results = list()
    results\$overlaps = iterate(autism_networks, overlapComparisons, plot = TRUE)
    
    # Visualize module overlap across networks and save to PDF
    networks = c('combined', conditions1, conditions2)
    
    pdf("ModuleFlowPlot.pdf", width = 10, height = 8)
    ModuleFlowPlot(
      autism_networks, 
      comparisonList = results\$overlaps, 
      networks = networks, 
      width = 0.3, 
      height = 0.2, 
      only.signif = TRUE, 
      only.contiguous = TRUE, 
      scale.by.size = TRUE, 
      spacer = 10, 
      label.y = 50
    )
    dev.off()
    
    # Perform differential module expression analysis
    test_cond = colnames(sampleTable)[2]
    ref_cond = colnames(sampleTable)[3]
    
    results\$diffModExp = runDME(
      autism_networks[["combined"]], 
      sampleTable, 
      p.adjust = "fdr", 
      refCondition = ref_cond, 
      testCondition = test_cond
    )
    
    # Save DME results table
    write.csv(results\$diffModExp, "diffModExp_results.csv", row.names = TRUE)
    
    # Identify top module for downstream plotting dynamically
    sorted_mods = rownames(results\$diffModExp)[order(results\$diffModExp[[test_cond]])]
    top_combined_mod = sorted_mods[sorted_mods != "combined_000"][1]
    
    # Track gene recruitment across networks using TOM flow plots
    toms = lapply(networks, function(x) { 
      load(paste0(x, '-block.1.RData'))
      get("TOM") 
    })
    
    tom.df = BuildTOMFlowDF(
      autism_networks, 
      networks, 
      toms, 
      genes_to_label = topNGenes(autism_networks[["combined"]], top_combined_mod)
    )
    
    pdf("TOMFlowPlot.pdf", width = 10, height = 8)
    PlotMultiNodesTOMflow(tom.df, labels = networks)
    dev.off()
    
    # Plot differential module expression for the top module
    pdf(paste0("diffModuleExpression_", top_combined_mod, ".pdf"), width = 8, height = 6)
    diffModuleExpression(
      autism_networks[["combined"]], 
      geneList = topNGenes(autism_networks[["combined"]], top_combined_mod), 
      design = sampleTable, 
      test = "ANOVA", 
      plotTitle = top_combined_mod, 
      plot = TRUE
    )
    dev.off()
    
    # Calculate module preservation statistics
    results\$preservation = iterate(
      autism_networks[conditions1], 
      preservationComparisons, 
      write = FALSE, 
      plot = TRUE, 
      nPermutations = 10
    )
    
    # Save the final results list
    saveRDS(results, "results.rds")
    
    # Summarize interesting results and write to a text file
    sink("summary_results.txt")
    summarizeResults(autism_networks, results)
    sink()

    writeLines(c(
        '"BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW":',
        paste0('    multiWGCNA: ', as.character(packageVersion('multiWGCNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_autism_microarray_workflow.csv versions.yml
    """
}

workflow BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ autism_se, sampleTable ] ]

    main:
    BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW.out.tables
    plots    = BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW.out.plots
    objects  = BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW.out.objects
    versions = BIOC_MULTIWGCNA_AUTISM_MICROARRAY_WORKFLOW.out.versions
}
