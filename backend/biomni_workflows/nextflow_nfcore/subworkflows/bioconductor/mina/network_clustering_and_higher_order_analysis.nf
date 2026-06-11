#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mina — network_clustering_and_higher_order_analysis
// Infer co-occurrence networks, perform network clustering, generate higher-order feature tables, and analyze higher-order community diversity.
// Input: maize, maize_des
// Container: quay.io/biocontainers/bioconductor-mina:1.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mina
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate correlation adjacency matrix
//  * 2. [Core Analysis] Perform network clustering using MCL or AP
//  * 3. [Core Analysis] Generate higher-order cluster table by summing member abundances
//  * 4. [Core Analysis] Calculate dissimilarity and unexplained variance on the cluster table

nextflow.enable.dsl = 2

process BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    
    # Load required library
    library(mina)
    
    # Read input files from the working directory
    if (file.exists("maize")) {
      maize <- readRDS("maize")
    } else if (file.exists("maize.rds")) {
      maize <- readRDS("maize.rds")
    } else {
      stop("Error: Input file 'maize' (mina object) not found in the working directory.")
    }
    
    if (file.exists("maize_des")) {
      maize_des <- readRDS("maize_des")
    } else if (file.exists("maize_des.rds")) {
      maize_des <- readRDS("maize_des.rds")
    } else if (file.exists("maize_des.csv")) {
      maize_des <- read.csv("maize_des.csv", header = TRUE, stringsAsFactors = FALSE)
    } else {
      stop("Error: Input file 'maize_des' (metadata table) not found in the working directory.")
    }
    
    # 1. Calculate correlation adjacency matrix
    # Spearman correlation with significance test
    maize <- adj(maize, method = "spearman", sig = TRUE)
    
    # 2. Perform network clustering
    # Network clustering by AP
    maize <- net_cls(maize, method = "ap", cutoff = 0.6, neg = FALSE)
    
    # 3. Generate higher-order cluster table by summing member abundances
    maize <- net_cls_tab(maize)
    
    # 4. Calculate dissimilarity and unexplained variance on the cluster table
    maize_cls_tab <- cls_tab(maize)
    maize_cls_dis <- com_dis(maize_cls_tab, method = "bray")
    r2_result <- get_r2(maize_cls_dis, maize_des, group = colnames(maize_des)[colnames(maize_des) != "Sample_ID"])
    
    # Write outputs to the working directory
    saveRDS(maize, "maize_output.rds")
    saveRDS(maize_cls_dis, "maize_cls_dis.rds")
    
    # Export cluster table as CSV
    write.csv(as.data.frame(maize_cls_tab), "maize_cls_tab.csv", row.names = TRUE)
    
    # Export R2 unexplained variance result
    write.table(r2_result, "unexplained_variance_r2.txt", row.names = FALSE, col.names = FALSE)

    writeLines(c(
        '"BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS":',
        paste0('    mina: ', as.character(packageVersion('mina')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_clustering_and_higher_order_analysis.csv versions.yml
    """
}

workflow BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maize, maize_des ] ]

    main:
    BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS.out.tables
    plots    = BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS.out.plots
    objects  = BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS.out.objects
    versions = BIOC_MINA_NETWORK_CLUSTERING_AND_HIGHER_ORDER_ANALYSIS.out.versions
}
