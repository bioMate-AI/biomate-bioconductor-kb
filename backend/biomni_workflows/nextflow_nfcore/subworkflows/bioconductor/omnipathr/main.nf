#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OmnipathR
// A client for the OmniPath web service (https://www.omnipathdb.org) and many other resources. It also
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OmnipathR/inst/doc/bioc_workshop.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("OmnipathR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_OMNIPATHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omnipathr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omnipathr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omnipathr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omnipathr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("OmnipathR", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(OmnipathR)
    library(jsonlite)

    # --- Transcriptional Interaction Network Construction [] ---
    # Key functions: transcriptional, interaction_graph, find_all_paths
    gri <- transcriptional()
    gr_graph <- interaction_graph(gri)
    paths <- find_all_paths(
        graph = gr_graph,
        start = c("EGFR", "STAT3"),
        end = c("AKT1", "ULK1"),
        attr = "name"
    )

    # --- Post-Translational Modification Analysis [] ---
    # Key functions: enzyme_substrate, enzsub_graph, signed_ptms
    enz_sub <- enzyme_substrate()
    es_graph <- enzsub_graph(enz_sub)
    es_signed <- signed_ptms(enz_sub)

    # --- Functional Annotation and Network Integration [] ---
    # Key functions: annotations, omnipath, annotated_network
    hpa_tissue <- annotations(
        resources = "HPA_tissue",
        wide = TRUE,
        proteins = c("DLL1", "MEIS2", "PHOX2A", "BACH1", "KLF11")
    )
    network <- omnipath()
    network_slk_pw <- annotated_network(network, "SignaLink_pathway")

    # --- Intercellular Communication Network Filtering [] ---
    # Key functions: intercell_network, filter_intercell_network
    icn <- intercell_network()
    icn_hc <- filter_intercell_network(
        icn,
        ligand_receptor = TRUE,
        consensus_percentile = 30,
        loc_consensus_percentile = 50,
        simplify = TRUE
    )

    # --- Gene and Protein Identifier Translation [] ---
    # Key functions: translate_ids
    d <- data.frame(uniprot_id = c("P00533", "Q9ULV1", "P43897", "Q9Y2P5"))
    d_translated <- translate_ids(
        d,
        uniprot_id = uniprot,
        genesymbol
    )

    # --- Gene Ontology Graph Construction [] ---
    # Key functions: go_ontology_download, relations_table_to_graph, ontology_ensure_name
    go <- go_ontology_download()
    go_graph <- relations_table_to_graph(go\$rel_tbl_c2p)
    go_term <- ontology_ensure_name("GO:0000022")


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_omnipathr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_omnipathr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_omnipathr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMNIPATHR:", paste0("    omnipathr: ", as.character(packageVersion("OmnipathR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omnipathr_results.csv
    touch ${prefix}_omnipathr_output.rds
    echo "BIOC_OMNIPATHR:" > versions.yml
    echo "    omnipathr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMNIPATHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMNIPATHR(ch_input)

    emit:
    results  = BIOC_OMNIPATHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMNIPATHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMNIPATHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMNIPATHR.out.versions  // channel: path(versions.yml)
}
