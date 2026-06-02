#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: enrichViewNet
// This package enables the visualization of functional enrichment results as network graphs. First the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/enrichViewNet/inst/doc/enrichViewNet.R
// Upstream  : ggplot2, gprofiler2, knitr
// Downstream: none
//
// Install: BiocManager::install("enrichViewNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHVIEWNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichviewnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichviewnet:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichviewnet:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enrichviewnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichviewnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichviewnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(enrichViewNet)
    library(jsonlite)


    # --- Graph Demo01 [] ---
    # Key functions: include_graphics, demo01.jpeg, demo_KEGG_emap_v03.jpg, Figure_enrichViewNet_workflow_v05.jpg, FromListToGraph_v03.jpg
    knitr::include_graphics("demo01.jpeg")
    knitr::include_graphics("demo_KEGG_emap_v03.jpg")
    knitr::include_graphics("Figure_enrichViewNet_workflow_v05.jpg")
    knitr::include_graphics("FromListToGraph_v03.jpg")

    # --- Gprofiler [] ---
    # Key functions: parental, sapiens, method, retained, results, gost, parentalNapaVsDMSODEG, hsapiens
    ## Required library
    library(gprofiler2)

    ## The dataset of differentially expressed genes done between 
    ## napabucasin treated and DMSO control parental (Froeling et al 2019)
    ## All genes tested are present
    data("parentalNapaVsDMSODEG")

    ## Retain significant results 
    ## (absolute fold change superior to 1 and adjusted p-value inferior to 0.05)
    ## The 'gostres' object is a list of 2 entries
    ## The 'result' entry contains the enrichment results
    ## The 'meta' entry contains the metadata information

    ## Some columns of interest in the results
    gostres$result[1:4, c("query", "p_value", "term_size", 
                        "query_size", "intersection_size", "term_id")]

    ## The term names can be longer than the one shown
    gostres$result[19:22, c("term_id", "source", "term_name")]

    # --- Network In Cytoscape [] ---
    # Key functions: include_graphics, cytoscape_reactome_all_parental_napa_vs_DMSO.png, parentalNapaVsDMSOEnrichment, term_name, Cytoscape, createNetwork, tempdir, TERM_ID
    knitr::include_graphics("cytoscape_reactome_all_parental_napa_vs_DMSO.png")
    ## Load saved enrichment results between parental Napa vs DMSO
    data("parentalNapaVsDMSOEnrichment")

    ## List of terms of interest
    reactomeSelected <- c("REAC:R-HSA-9031628", "REAC:R-HSA-198725", 
                            "REAC:R-HSA-9614085", "REAC:R-HSA-9617828",
                            "REAC:R-HSA-9614657", "REAC:R-HSA-73857",
                            "REAC:R-HSA-74160", "REAC:R-HSA-381340")

    ## All enrichment results
    ## Create network for REACTOME selected terms
    ## The 'source="TERM_ID"' parameter enable to specify a personalized 
    ## list of terms of interest
    ## The network will either by created in Cytoscape (if the application is open)
    ## or a CX file will be created in the temporary directory
    createNetwork(gostObject=parentalNapaVsDMSOEnrichment,  source="TERM_ID", 
            termIDs=selectedRes$term_id, title="REACTOME_Selected", 
            collection="parental_napa_vs_DMSO",
            fileName=file.path(tempdir(), "parentalNapaVsDMSO_REACTOME.cx"))

    # --- Network Final Reactome [] ---
    # Key functions: include_graphics, REACTOME_Selected.jpeg, parental, sapiens, method, retained, results, gost
    knitr::include_graphics("REACTOME_Selected.jpeg")
    ## Required library
    library(gprofiler2)

    ## The dataset of differentially expressed genes done between 
    ## napabucasin treated and DMSO control parental (Froeling et al 2019)
    ## All genes tested are present
    data("parentalNapaVsDMSODEG")

    ## Retain significant results 
    ## (absolute fold change superior to 1 and adjusted p-value inferior to 0.05)
    ## The 'gostres' object is a list of 2 entries
    ## The 'result' entry contains the enrichment results
    ## The 'meta' entry contains the metadata information

    ## Some columns of interest in the results
    gostres$result[1:4, c("query", "p_value", "term_size", 
                        "query_size", "intersection_size", "term_id")]

    ## The term names can be longer than the one shown

    # --- Run Create Emap Terms [] ---
    # Key functions: createEnrichMap, term_id, query, term_name, parental_napa_vs_DMSO, TERM_ID, scale_color_continuous, orange
    ## Load saved enrichment results between parental Napa vs DMSO
    data(parentalNapaVsDMSOEnrichment)

    ## The term IDs must correspond to the IDs present in the "term_id" column
    head(parentalNapaVsDMSOEnrichment$result[, c("query", "term_id", "term_name")], 
         n=3)

    ## List of selected terms from different sources
    termID <- c("KEGG:04115", "WP:WP4963", "KEGG:04010", 
                    "REAC:R-HSA-5675221", "REAC:R-HSA-112409", "WP:WP382")
    ## Set seed to ensure reproducible results
    set.seed(91)

    ## Create network for all Kegg terms
    createEnrichMap(gostObject=parentalNapaVsDMSOEnrichment, 
                        query="parental_napa_vs_DMSO", 
                        source="KEGG")
    ## The ggplot2 library is required
    library(ggplot2)


    # --- Emap Multi Seed [] ---
    # Key functions: createEnrichMapMultiBasic, scale_fill_manual, element_text, cyan4, bisque3, parental, rosa, bold
    ## Set seed to ensure reproducible results
    set.seed(5)

    ## Enrichment map where the groups are the KEGG results for the 2 different
    ## experiments
    createEnrichMapMultiBasic(gostObjectList=gostObjectList,
        queryList=queryList, source="KEGG", removeRoot=TRUE)
    ## Required library
    library(ggplot2)

    ## Set seed to ensure reproducible results
    set.seed(5)

    ## Enrichment map where the groups are the KEGG results for the 2 different
    ## experiments
    createEnrichMapMultiBasic(gostObjectList=gostObjectList,
        queryList=queryList, source="KEGG", removeRoot=TRUE) +
    ## Set seed to ensure reproducible results
    set.seed(3221)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichviewnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichviewnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichviewnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHVIEWNET:", paste0("    enrichviewnet: ", packageVersion("enrichViewNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichviewnet_results.csv
    touch ${prefix}_enrichviewnet_output.rds
    echo "BIOC_ENRICHVIEWNET:" > versions.yml
    echo "    enrichviewnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHVIEWNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENRICHVIEWNET(ch_input)

    emit:
    results  = BIOC_ENRICHVIEWNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHVIEWNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHVIEWNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHVIEWNET.out.versions  // channel: path(versions.yml)
}
