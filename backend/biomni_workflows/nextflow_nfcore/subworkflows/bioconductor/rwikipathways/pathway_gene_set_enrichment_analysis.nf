#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rWikiPathways — pathway_gene_set_enrichment_analysis
// Perform Gene Set Enrichment Analysis (GSEA) on a ranked list of genes using WikiPathways.
// Input: data-lung-cancer.csv
// Container: quay.io/biocontainers/bioconductor-rwikipathways:1.30.0--r45hdfd78af_1
// R packages: clusterProfiler, org.Hs.eg.db, rWikiPathways
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("clusterProfiler", "org.Hs.eg.db", "rWikiPathways")
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
    library(clusterProfiler)
    library(org.Hs.eg.db)
    
    # --- Load differential expression data and convert background ---
    lung.expr <- read.csv("data-lung-cancer.csv", stringsAsFactors = FALSE)
    bkgd.genes <- lung.expr[,1]
    bkgd.genes.entrez <- bitr(bkgd.genes, fromType = "ENSEMBL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
    
    # --- Calculate a ranking metric (e.g., based on log2 fold ---
    lung.expr\$fcsign <- sign(lung.expr\$log2FC)
    lung.expr\$logfdr <- -log10(lung.expr\$P.Value)
    lung.expr\$sig <- lung.expr\$logfdr/lung.expr\$fcsign
    
    # --- Merge the ranking metric with the converted Entrez IDs ---
    sig.lung.expr.entrez<-merge(lung.expr, bkgd.genes.entrez, by.x = "GeneID", by.y = "ENSEMBL")
    gsea.sig.lung.expr <- sig.lung.expr.entrez[,8]
    names(gsea.sig.lung.expr) <- as.character(sig.lung.expr.entrez[,9])
    gsea.sig.lung.expr <- sort(gsea.sig.lung.expr,decreasing = TRUE)
    
    # --- Run GSEA against WikiPathways using clusterProfiler::gseWP ---
    gwp.sig.lung.expr <- clusterProfiler::gseWP(
      gsea.sig.lung.expr,
      pAdjustMethod = "fdr",
      pvalueCutoff = 0.05, #p.adjust cutoff
      organism = "Homo sapiens"
    )
    
    # --- Extract and filter pathways enriched for up-regulated or ---
    gwp.sig.lung.expr.df = as.data.frame(gwp.sig.lung.expr)
    up_pathways <- gwp.sig.lung.expr.df[which(gwp.sig.lung.expr.df\$NES > 1),] #pathways enriched for upregulated lung cancer genes
    down_pathways <- gwp.sig.lung.expr.df[which(gwp.sig.lung.expr.df\$NES < -1),] #pathways enriched for downregulated lung cancer genes
    
    # Write outputs to the working directory
    write.csv(gwp.sig.lung.expr.df, "gsea_all_pathways.csv", row.names = FALSE)
    write.csv(up_pathways, "gsea_upregulated_pathways.csv", row.names = FALSE)
    write.csv(down_pathways, "gsea_downregulated_pathways.csv", row.names = FALSE)
    saveRDS(gwp.sig.lung.expr, "gsea_results.rds")

    writeLines(c(
        '"BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS":',
        paste0('        rWikiPathways: ', as.character(packageVersion("rWikiPathways")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_gene_set_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data-lung-cancer.csv ] ]

    main:
    BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_RWIKIPATHWAYS_PATHWAY_GENE_SET_ENRICHMENT_ANALYSIS.out.versions
}
