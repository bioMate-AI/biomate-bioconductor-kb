#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ROntoTools — pathway_express
// Perform Pathway-Express analysis to identify significantly impacted signaling pathways using gene fold changes, p-values, and pathway topology.
// Input: topTable.RData
// Container: quay.io/biocontainers/bioconductor-rontotools:2.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ROntoTools, Rgraphviz, graph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and load KEGG pathway graphs using keggPathwayGraphs
//  * 2. [Core Analysis] Set edge weights based on interaction subtypes using setEdgeWeights
//  * 3. [Core Analysis] Retrieve pathway names using keggPathwayNames
//  * 4. [Core Analysis] Filter differentially expressed genes and extract fold changes and p-values
//  * 5. [Core Analysis] Set node weights using gene significance via setNodeWeights and alphaMLG
//  * 6. [Core Analysis] Run Pathway-Express analysis using pe
//  * 7. [Visualization & Output] Summarize results using Summary
//  * 8. [Visualization & Output] Visualize results using plot and renderGraph

nextflow.enable.dsl = 2

process BIOC_RONTOTOOLS_PATHWAY_EXPRESS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("graph", "Rgraphviz", "ROntoTools")
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
    
    library(graph)
    library(Rgraphviz)
    library(ROntoTools)
    
    # 1. Download and load KEGG pathway graphs
    kpg <- keggPathwayGraphs("hsa", verbose = FALSE)
    
    # 2. Set edge weights based on interaction subtypes
    kpg <- setEdgeWeights(kpg, edgeTypeAttr = "subtype", 
    	edgeWeightByType = list(activation = 1, inhibition = -1, 
    		expression = 1, repression = -1), 
    	defaultWeight = 0)
    
    # 3. Retrieve pathway names
    kpn <- keggPathwayNames("hsa")
    
    # 4. Load user input and filter differentially expressed genes
    load("topTable.RData")
    
    fc <- top\$logFC[top\$adj.P.Val <= .01]
    names(fc) <- top\$entrez[top\$adj.P.Val <= .01]
    
    pv <- top\$P.Value[top\$adj.P.Val <= .01]
    names(pv) <- top\$entrez[top\$adj.P.Val <= .01]
    
    ref <- top\$entrez
    
    # 5. Set node weights using gene significance
    kpg <- setNodeWeights(kpg, weights = alphaMLG(pv), defaultWeight = 1)
    
    # 6. Run Pathway-Express analysis
    peRes <- pe(x = fc, graphs = kpg, ref = ref,  nboot = 200, verbose = FALSE)
    
    # 7. Summarize results and save to CSV
    sum_all <- Summary(peRes)
    write.csv(sum_all, "pe_summary_all.csv", row.names = TRUE)
    
    sum_pPert <- Summary(peRes, pathNames = kpn, totalAcc = FALSE, totalPert = FALSE,
                         pAcc = FALSE, pORA = FALSE, comb.pv = NULL, order.by = "pPert")
    write.csv(sum_pPert, "pe_summary_pPert.csv", row.names = TRUE)
    
    saveRDS(peRes, "peRes.rds")
    
    # 8. Visualize results and save to PDF
    pdf("pe_results_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      plot(peRes)
    }, error = function(e) {
      message("Could not plot peRes: ", e\$message)
    })
    
    tryCatch({
      plot(peRes, c("pAcc", "pORA"), comb.pv.func = compute.normalInv, threshold = .01)
    }, error = function(e) {
      message("Could not plot peRes with threshold: ", e\$message)
    })
    
    # Visualize specific pathway if available in the results
    target_pathway <- "path:hsa05216"
    if (target_pathway %in% names(peRes@pathways)) {
      tryCatch({
        plot(peRes@pathways[[target_pathway]], type = "two.way")
      }, error = function(e) {
        message("Could not plot two.way for ", target_pathway, ": ", e\$message)
      })
    
      tryCatch({
        plot(peRes@pathways[[target_pathway]], type = "boot")
      }, error = function(e) {
        message("Could not plot boot for ", target_pathway, ": ", e\$message)
      })
    
      tryCatch({
        p <- peRes@pathways[[target_pathway]]
        g <- layoutGraph(p@map, layoutType = "dot")
        graphRenderInfo(g) <- list(fixedsize = FALSE)
        edgeRenderInfo(g) <- peEdgeRenderInfo(p)
        nodeRenderInfo(g) <- peNodeRenderInfo(p)
        renderGraph(g)
      }, error = function(e) {
        message("Could not render graph for ", target_pathway, ": ", e\$message)
      })
    } else {
      message("Pathway ", target_pathway, " not found in the analysis results. Skipping pathway-specific plots.")
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_RONTOTOOLS_PATHWAY_EXPRESS":',
        paste0('    ROntoTools: ', as.character(packageVersion('ROntoTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_express.csv versions.yml
    """
}

workflow BIOC_RONTOTOOLS_PATHWAY_EXPRESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ topTable.RData ] ]

    main:
    BIOC_RONTOTOOLS_PATHWAY_EXPRESS(ch_input)

    emit:
    tables   = BIOC_RONTOTOOLS_PATHWAY_EXPRESS.out.tables
    plots    = BIOC_RONTOTOOLS_PATHWAY_EXPRESS.out.plots
    objects  = BIOC_RONTOTOOLS_PATHWAY_EXPRESS.out.objects
    versions = BIOC_RONTOTOOLS_PATHWAY_EXPRESS.out.versions
}
