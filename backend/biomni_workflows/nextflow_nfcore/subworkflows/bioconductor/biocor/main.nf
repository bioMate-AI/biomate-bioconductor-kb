#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioCor — gene_and_cluster_similarity
// Calculate functional similarities between genes and gene clusters using pathway annotations, and perform hierarchical clustering.
// Input: genes.id, genesReact
// Container: quay.io/biocontainers/bioconductor-biocor:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioCor, org.Hs.eg.db
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare pathway annotations
//  * 2. [Core Analysis] Calculate gene-to-gene similarity matrix using mgeneSim
//  * 3. [Core Analysis] Cluster genes using hclust
//  * 4. [Input & Preparation] Define gene clusters using cutree
//  * 5. [Core Analysis] Calculate similarities between clusters using mclusterSim (by pathways) or mclusterGeneSim (by genes)

nextflow.enable.dsl = 2

process BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library("BioCor")
    library("org.Hs.eg.db")
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read genes.id (character vector of gene identifiers)
    if (file.exists("genes.id")) {
      # Try reading as RDS first, then fallback to plain text lines
      genes.id <- tryCatch(
        readRDS("genes.id"),
        error = function(e) readLines("genes.id")
      )
    } else {
      stop("Error: Required input file 'genes.id' not found in the working directory.")
    }
    
    # Read genesReact (list of pathway-to-gene annotations)
    if (file.exists("genesReact")) {
      genesReact <- readRDS("genesReact")
    } else if (file.exists("genesReact.rds")) {
      genesReact <- readRDS("genesReact.rds")
    } else {
      stop("Error: Required input file 'genesReact' (or 'genesReact.rds') not found in the working directory.")
    }
    
    # Ensure genes.id is a character vector
    genes.id <- as.character(genes.id)
    
    # ==========================================
    # 2. Prepare Pathway Annotations & Gene IDs
    # ==========================================
    
    # Map Entrez IDs to Gene Symbols using org.Hs.eg.db as documented
    genes.id <- mapIds(org.Hs.eg.db, keys = genes.id, keytype = "ENTREZID", 
                       column = "SYMBOL")
    genes <- names(genes.id)
    names(genes) <- genes.id
    
    # ==========================================
    # 3. Calculate Gene-to-Gene Similarity
    # ==========================================
    
    react <- mgeneSim(genes, genesReact)
    
    # Remove genes which are not in the pathway list
    nan <- genes %in% names(genesReact)
    react <- react[nan, nan]
    
    # Save the gene similarity matrix
    write.csv(as.data.frame(react), "gene_similarity_matrix.csv", row.names = TRUE)
    
    # ==========================================
    # 4. Cluster Genes using hclust
    # ==========================================
    
    hc <- hclust(as.dist(1 - react))
    
    # Plot and save gene similarity dendrogram
    pdf("gene_similarity_dendrogram.pdf", width = 10, height = 7)
    plot(hc, main = "Similarities between genes")
    dev.off()
    
    # ==========================================
    # 5. Define Gene Clusters using cutree
    # ==========================================
    
    mycl <- cutree(hc, h = 0.2)
    clusters <- split(genes[nan], as.factor(mycl))
    
    # Removing clusters of just one gene
    clusters <- clusters[lengths(clusters) >= 2]
    names(clusters) <- paste0("cluster", names(clusters))
    
    # Save the defined clusters
    saveRDS(clusters, "gene_clusters.rds")
    
    # ==========================================
    # 6. Calculate Similarities Between Clusters
    # ==========================================
    
    # Method 1: Similarities between clusters by pathways
    sim_clus1 <- mclusterSim(clusters, genesReact)
    
    write.csv(as.data.frame(sim_clus1), "cluster_similarity_by_pathways.csv", row.names = TRUE)
    
    pdf("cluster_similarity_pathways_dendrogram.pdf", width = 8, height = 6)
    plot(hclust(as.dist(1 - sim_clus1)), 
         main = "Similarities between clusters by pathways")
    dev.off()
    
    # Method 2: Similarities between clusters by genes
    sim_clus2 <- mclusterGeneSim(clusters, genesReact)
    
    write.csv(as.data.frame(sim_clus2), "cluster_similarity_by_genes.csv", row.names = TRUE)
    
    pdf("cluster_similarity_genes_dendrogram.pdf", width = 8, height = 6)
    plot(hclust(as.dist(1 - sim_clus2)), 
         main = "Similarities between clusters by genes")
    dev.off()

    writeLines(c(
        '"BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY":',
        paste0('    BioCor: ', as.character(packageVersion('BioCor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_and_cluster_similarity.csv versions.yml
    """
}

workflow BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes.id, genesReact ] ]

    main:
    BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY.out.tables
    plots    = BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY.out.plots
    objects  = BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY.out.objects
    versions = BIOC_BIOCOR_GENE_AND_CLUSTER_SIMILARITY.out.versions
}
