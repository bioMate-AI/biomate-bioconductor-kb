#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: KEGGREST
// A package that provides a client interface to the Kyoto Encyclopedia of Genes and Genomes (KEGG) RES
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/KEGGREST/inst/doc/KEGGREST-vignette.R
// Upstream  : png
// Downstream: ROntoTools, Hiiragi2013
//
// Install: BiocManager::install("KEGGREST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KEGGREST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-keggrest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-keggrest:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-keggrest:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_keggrest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_keggrest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_keggrest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KEGGREST)
    library(jsonlite)

    # --- Entity Retrieval and Sequence Extraction [] ---
    # Key functions: keggGet
    query_res <- keggGet(c("hsa:10458", "ece:Z5100"))
    entry_names <- lapply(query_res, function(x) x$ENTRY)
    dblinks <- lapply(query_res, function(x) x$DBLINKS)
    aa_seqs <- keggGet(c("hsa:10458", "ece:Z5100"), "aaseq")
    nt_seqs <- keggGet(c("hsa:10458", "ece:Z5100"), "ntseq")


    # --- Database Searching and Filtering [] ---
    # Key functions: keggFind
    toxin_genes <- keggFind("genes", c("shiga", "toxin"))
    exact_compounds <- keggFind("compound", "C7H10O5", "formula")
    mass_compounds <- keggFind("compound", 174.05, "exact_mass")
    weight_compounds <- keggFind("compound", 300:310, "mol_weight")


    # --- Identifier Conversion [] ---
    # Key functions: keggConv
    ncbi_to_kegg <- keggConv("ncbi-proteinid", c("hsa:10458", "ece:Z5100"))
    eco_to_ncbi <- keggConv("eco", "ncbi-geneid")
    ncbi_to_eco <- keggConv("ncbi-geneid", "eco")


    # --- Pathway and Gene Linkage [] ---
    # Key functions: keggLink
    hsa_pathways <- keggLink("pathway", "hsa")
    specific_links <- keggLink("pathway", c("hsa:10458", "ece:Z5100"))
    compound_pathways <- keggLink("pathway", "compound")


    # --- Pathway Visualization Retrieval [] ---
    # Key functions: keggGet
    pathway_img <- keggGet("hsa05130", "image")
    img_file <- tempfile(fileext = ".png")
    writeBin(pathway_img, img_file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_keggrest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_keggrest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_keggrest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEGGREST:", paste0("    keggrest: ", packageVersion("KEGGREST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_keggrest_results.csv
    touch ${prefix}_keggrest_output.rds
    echo "BIOC_KEGGREST:" > versions.yml
    echo "    keggrest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEGGREST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEGGREST(ch_input)

    emit:
    results  = BIOC_KEGGREST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEGGREST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEGGREST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEGGREST.out.versions  // channel: path(versions.yml)
}
