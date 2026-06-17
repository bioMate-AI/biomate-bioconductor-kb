#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — go_graph_exploration_and_utilities
// Explore the GO-graph, retrieve associations between genes and GO-categories, and refine enrichment results.
// Input: go_ids.txt, gene_symbols.txt, go_enrich_results.RData
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve parent or child nodes of GO-categories
//  * 2. [Core Analysis] Retrieve names and domains of GO-IDs
//  * 3. [Core Analysis] Search for GO-categories by name
//  * 4. [Core Analysis] Retrieve annotated genes for GO-categories
//  * 5. [Core Analysis] Retrieve annotated GO-categories for genes
//  * 6. [Core Analysis] Refine enrichment results using refine

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GOfuncR")
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
    library(GOfuncR)
    
    # ==========================================
    # 0. Read User Input Files
    # ==========================================
    # Read GO IDs from go_ids.txt
    go_ids = readLines("go_ids.txt")
    go_ids = go_ids[go_ids != ""]
    
    # Read Gene Symbols from gene_symbols.txt
    gene_symbols = readLines("gene_symbols.txt")
    gene_symbols = gene_symbols[gene_symbols != ""]
    
    # Load the saved go_enrich result object from go_enrich_results.RData
    env = new.env()
    load("go_enrich_results.RData", envir = env)
    loaded_objs = ls(env)
    if ("res_hyper" %in% loaded_objs) {
      res_hyper = env\$res_hyper
    } else {
      res_hyper = env[[loaded_objs[1]]]
    }
    
    # ==========================================
    # 1. Retrieve parent or child nodes of GO-categories
    # ==========================================
    parents = get_parent_nodes(go_ids)
    write.csv(parents, "parent_nodes.csv", row.names = FALSE)
    
    children = get_child_nodes(go_ids)
    write.csv(children, "child_nodes.csv", row.names = FALSE)
    
    # ==========================================
    # 2. Retrieve names and domains of GO-IDs
    # ==========================================
    go_names = get_names(go_ids)
    write.csv(go_names, "go_names.csv", row.names = FALSE)
    
    # ==========================================
    # 3. Search for GO-categories by name
    # ==========================================
    bbb = get_ids('blood-brain barrier')
    head(bbb)
    write.csv(bbb, "bbb_search_results.csv", row.names = FALSE)
    
    # ==========================================
    # 4. Retrieve annotated genes for GO-categories
    # ==========================================
    # Retrieve annotated genes for the first GO-ID in the input list
    single_go_anno = get_anno_genes(go_ids = go_ids[1])
    head(single_go_anno)
    write.csv(single_go_anno, "anno_genes_single_go.csv", row.names = FALSE)
    
    # Retrieve annotated genes for the input lists of GO-IDs and genes
    genes = gene_symbols
    gos = go_ids
    anno_genes = get_anno_genes(go_ids = gos, genes = genes)
    anno_genes_named = cbind(anno_genes, get_names(anno_genes\$go_id)[, 2:3])
    write.csv(anno_genes_named, "anno_genes_with_names.csv", row.names = FALSE)
    
    # ==========================================
    # 5. Retrieve annotated GO-categories for genes
    # ==========================================
    anno = get_anno_categories(gene_symbols)
    head(anno)
    write.csv(anno, "anno_categories.csv", row.names = FALSE)
    
    # Direct annotations for the first gene in the input list
    direct_anno = get_anno_categories(gene_symbols[1])
    direct_anno
    write.csv(direct_anno, "direct_anno.csv", row.names = FALSE)
    
    parent_ids = unique(get_parent_nodes(direct_anno\$go_id)[, 2])
    full_anno = get_names(parent_ids)
    head(full_anno)
    write.csv(full_anno, "full_anno_parents.csv", row.names = FALSE)
    
    # ==========================================
    # 6. Refine enrichment results using refine
    # ==========================================
    refined = refine(res_hyper, fwer = 0.1)
    refined
    write.csv(refined, "refined_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_graph_exploration_and_utilities.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ go_ids.txt, gene_symbols.txt, go_enrich_results.RData ] ]

    main:
    BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES.out.tables
    plots    = BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES.out.plots
    objects  = BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES.out.objects
    versions = BIOC_GOFUNCR_GO_GRAPH_EXPLORATION_AND_UTILITIES.out.versions
}
