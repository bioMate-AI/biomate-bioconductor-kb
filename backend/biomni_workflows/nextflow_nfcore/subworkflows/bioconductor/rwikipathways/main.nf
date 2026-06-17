#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rWikiPathways — pathway_over_representation_analysis_and_visualization
// Perform pathway over-representation analysis on differential gene expression data, import the top enriched pathways into Cytoscape, overlay expression data, and
// Input: data-lung-cancer.csv, drugbank-5.1.0.xgmml.zip
// Container: quay.io/biocontainers/bioconductor-rwikipathways:1.30.0--r45hdfd78af_1
// R packages: DOSE, RCy3, BridgeDbR, clusterProfiler, dplyr, org.Hs.eg.db, pacman, rWikiPathways
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rwikipathways:1.30.0--r45hdfd78af_1"

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
    .bm_deps <- c("DOSE", "RCy3", "BridgeDbR", "clusterProfiler", "dplyr", "org.Hs.eg.db", "pacman", "rWikiPathways")
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
    library(rWikiPathways)
    library(RCy3)
    library(clusterProfiler)
    library(org.Hs.eg.db)
    library(DOSE)
    library(dplyr)
    
    # --- Load differential expression data and define up- and ---
    lung.expr <- read.csv("data-lung-cancer.csv", stringsAsFactors = FALSE)
    up.genes <- lung.expr[lung.expr\$log2FC > 1 & lung.expr\$adj.P.Value < 0.05, 1]
    dn.genes <- lung.expr[lung.expr\$log2FC < -1 & lung.expr\$adj.P.Value < 0.05, 1]
    bkgd.genes <- lung.expr[,1]
    
    # --- Convert gene identifiers (Ensembl to Entrez) using ---
    up.genes.entrez <- clusterProfiler::bitr(up.genes, fromType = "ENSEMBL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
    dn.genes.entrez <- clusterProfiler::bitr(dn.genes, fromType = "ENSEMBL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
    bkgd.genes.entrez <- clusterProfiler::bitr(bkgd.genes, fromType = "ENSEMBL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
    
    # --- Perform pathway enrichment analysis (Over-representation ---
    ewp.up <- clusterProfiler::enrichWP(
      up.genes.entrez[[2]],
      universe = bkgd.genes.entrez[[2]],
      organism = "Homo sapiens",
      pAdjustMethod = "fdr",
      pvalueCutoff = 0.1
    )
    ewp.up <- DOSE::setReadable(ewp.up, org.Hs.eg.db, keyType = "ENTREZID")
    
    ewp.dn <- clusterProfiler::enrichWP(
      dn.genes.entrez[[2]],
      organism = "Homo sapiens",
      pAdjustMethod = "fdr",
      pvalueCutoff = 0.1
    )
    ewp.dn <- DOSE::setReadable(ewp.dn, org.Hs.eg.db, keyType = "ENTREZID")
    
    # --- Search and explore relevant pathways using rWikiPathways ---
    lc.pathways <- findPathwaysByText("lung cancer")
    human.lc.pathways <- lc.pathways %>% dplyr::filter(species == "Homo sapiens")
    lc.wpids <- human.lc.pathways\$id
    ewp.up.wpids <- ewp.up\$ID
    
    # Save the enrichment results as RData files
    save(ewp.up, file = "lung_cancer_ewp_up.Rdata")
    save(ewp.dn, file = "lung_cancer_ewp_down.Rdata")
    
    # Write enrichment results to CSV tables for downstream use
    write.csv(as.data.frame(ewp.up), file = "lung_cancer_ewp_up_results.csv", row.names = FALSE)
    write.csv(as.data.frame(ewp.dn), file = "lung_cancer_ewp_down_results.csv", row.names = FALSE)
    
    # 5-8. Cytoscape Visualization and Network Extension
    # Wrapped in a tryCatch block to ensure the pipeline completes even if Cytoscape is not running
    tryCatch({
      # Verify connection to Cytoscape
      cytoscapePing()
      
      # Import pathway into Cytoscape
      RCy3::commandsRun('wikipathways import-as-pathway id=WP179')
      toggleGraphicsDetails()
      loadTableData(lung.expr, data.key.column = "GeneID", table.key.column = "Ensembl")
      setNodeColorMapping("log2FC", colors=paletteColorBrewerRdBu, style.name = "WikiPathways")
      
      # Import top 5 enriched pathways and overlay expression data
      lapply(ewp.up.wpids[1:5], function (x) {
        commandsRun(paste0('wikipathways import-as-pathway id=',x))
        loadTableData(lung.expr, data.key.column = "GeneID", table.key.column = "Ensembl")
        toggleGraphicsDetails()
      })
      
      # Import pathway as a network and extend with drug-target interactions
      commandsRun('wikipathways import-as-network id=WP179')
      loadTableData(lung.expr, data.key.column = "GeneID", table.key.column = "Ensembl")
      
      # Unzip the drugbank linkset database from the working directory
      unzip("drugbank-5.1.0.xgmml.zip", exdir = getwd())
      drugbank <- file.path(getwd(), "drugbank-5.1.0.xgmml")
      
      # Extend network using CyTargetLinker
      commandsRun(paste0('cytargetlinker extend idAttribute="Ensembl" linkSetFiles="', drugbank, '"') )
      commandsRun('cytargetlinker applyLayout network="current"')
      
      # Customize visualization of drug nodes
      my.drugs <- selectNodes("drug", by.col = "CTL.Type", preserve = FALSE)\$nodes
      clearSelection()
      setNodeColorBypass(my.drugs, "#DD99FF")
      setNodeShapeBypass(my.drugs, "hexagon")
      
      # Apply drug labels
      drug.labels <- getTableColumns(columns=c("SUID","CTL.label"))
      drug.labels <- na.omit(drug.labels)
      mapply(function(x,y) setNodeLabelBypass(x,y), drug.labels\$SUID, drug.labels\$CTL.label)
      
      # Save Cytoscape session and export images
      saveSession('tutorial_session')
      exportImage('tutorial_image2', type='PDF')
      exportImage('tutorial_image2', type='PNG', zoom=200)
      
    }, error = function(e) {
      message("Cytoscape connection or execution failed. Please ensure Cytoscape is running with the WikiPathways and CyTargetLinker apps installed.")
      message("Error details: ", e\$message)
    })

    writeLines(c(
        '"BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION":',
        paste0('        rWikiPathways: ', as.character(packageVersion("rWikiPathways")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_over_representation_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data-lung-cancer.csv, drugbank-5.1.0.xgmml.zip ] ]

    main:
    BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_RWIKIPATHWAYS_PATHWAY_OVER_REPRESENTATION_ANALYSIS_AND_VISUALIZATION.out.versions
}
