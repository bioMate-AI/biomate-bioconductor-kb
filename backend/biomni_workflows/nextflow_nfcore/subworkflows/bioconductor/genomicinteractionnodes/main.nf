#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicInteractionNodes — detect_and_analyze_interaction_nodes
// Import chromatin interactions, detect interaction nodes, annotate them with gene promoters, and perform Gene Ontology enrichment analysis.
// Input: WT.2.bedpe
// Container: quay.io/biocontainers/bioconductor-genomicinteractionnodes:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, GenomicInteractionNodes, TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import chromatin interactions from a BEDPE file
//  * 2. [Core Analysis] Detect genomic interaction nodes
//  * 3. [Core Analysis] Annotate node regions with gene promoters
//  * 4. [Core Analysis] Perform Gene Ontology enrichment analysis

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("GenomicInteractionNodes", "rtracklayer", "TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db", "GO.db")
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
    library(GenomicInteractionNodes)
    library(rtracklayer)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    library(GO.db)
    
    # Define input file path
    input_file <- "WT.2.bedpe"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # 1. Import chromatin interactions from the BEDPE file
    message("Importing chromatin interactions...")
    interactions <- import(con=input_file, format="bedpe")
    
    # 2. Detect genomic interaction nodes
    message("Detecting interaction nodes...")
    nodes <- detectNodes(interactions)
    names(nodes)
    lapply(nodes, head, n=2)
    
    # Save detected nodes to RDS
    saveRDS(nodes, file="detected_nodes.rds")
    
    # 3. Annotate node regions with gene promoters
    message("Annotating node regions...")
    node_regions <- nodes\$node_regions
    node_regions <- annotateNodes(node_regions,
                                  txdb=TxDb.Hsapiens.UCSC.hg19.knownGene,
                                  orgDb=org.Hs.eg.db,
                                  upstream=2000, downstream=500)
    head(node_regions, n=2)
    
    # Save annotated node regions
    saveRDS(node_regions, file="annotated_node_regions.rds")
    write.csv(as.data.frame(node_regions), file="annotated_node_regions.csv", row.names=FALSE)
    
    # 4. Gene Ontology enrichment analysis
    message("Performing Gene Ontology enrichment analysis...")
    enrich <- enrichmentAnalysis(node_regions, orgDb=org.Hs.eg.db)
    names(enrich\$enriched)
    names(enrich\$enriched_in_compound)
    
    # Extract and order Biological Process (BP) enrichment results
    res <- enrich\$enriched\$BP
    res <- res[order(res\$fdr), ]
    head(res, n=2)
    
    # Save enrichment results
    saveRDS(enrich, file="enrichment_results.rds")
    write.csv(res, file="enrichment_BP_ordered.csv", row.names=TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES":',
        paste0('    GenomicInteractionNodes: ', as.character(packageVersion('GenomicInteractionNodes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_and_analyze_interaction_nodes.csv versions.yml
    """
}

workflow BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WT.2.bedpe ] ]

    main:
    BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES(ch_input)

    emit:
    tables   = BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES.out.tables
    plots    = BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES.out.plots
    objects  = BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES.out.objects
    versions = BIOC_GENOMICINTERACTIONNODES_DETECT_AND_ANALYZE_INTERACTION_NODES.out.versions
}
