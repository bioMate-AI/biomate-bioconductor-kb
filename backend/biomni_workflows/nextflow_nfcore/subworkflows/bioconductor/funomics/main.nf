#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: funOmics
// The 'funOmics' package ggregates or summarizes omics data into higher level functional representatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/funOmics/inst/doc/funomics_vignette.R
// Upstream  : MultiAssayExperiment, SummarizedExperiment, airway
// Downstream: none
//
// Install: BiocManager::install("funOmics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FUNOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-funomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-funomics:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-funomics:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_funomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_funomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_funomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MultiAssayExperiment)
    library(jsonlite)

    # --- Get Kegg Sets [] ---
    # Key functions: get_kegg_sets
    ---------------------------------------------------------------------
    hsa_kegg_sets_entrez <- get_kegg_sets()
    head(hsa_kegg_sets_entrez)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(SummarizedExperiment)
    library(airway)
    data(airway)
    airway
    # --- Assaynames [] ---
    # Key functions: assayNames
    ---------------------------------------------------------------------
    assayNames(airway)
    # --- Head [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    head(assay(airway, "counts"))
    dim(assay(airway, "counts"))
    # --- Get Kegg Sets [] ---
    # Key functions: get_kegg_sets
    ---------------------------------------------------------------------
    kegg_sets <- get_kegg_sets(geneid_type = "ensembl")
    head(kegg_sets)
    # --- Summarize Pathway Level [] ---
    # Key functions: summarize_pathway_level, assay
    ---------------------------------------------------------------------
    pathway_activity_pca <- summarize_pathway_level(assay(airway, "counts"), kegg_sets, type = "pca")
    # --- Any [] ---
    # Key functions: any, assay, rowSums
    ---------------------------------------------------------------------
    print(any(assay(airway, "counts")[rowSums(assay(airway, "counts")) <0, ]))
    X <- assay(airway, "counts")[rowSums(assay(airway, "counts")) >= 10, ]
    # --- Summarize Pathway Level [] ---
    # Key functions: summarize_pathway_level
    ---------------------------------------------------------------------
    pathway_activity_nmf <- summarize_pathway_level(X, kegg_sets, type = "nmf") # note that the NMF operation can take some minutes
    print(paste("Pathway activity score matrix has dimensions:", nrow(pathway_activity_nmf), ",", ncol(pathway_activity_nmf)))
    # --- List [] ---
    # Key functions: assay, MultiAssayExperiment, colData
    ---------------------------------------------------------------------
    library(MultiAssayExperiment)
    assays_list <- list( counts = assay(airway, "counts"), kegg_nmf_agg = pathway_activity_nmf, kegg_pca_agg = pathway_activity_pca)
    airwayMultiAssay <- MultiAssayExperiment(experiments=assays_list)
    colData(airwayMultiAssay) <- colData(airway)
    # --- Summarize Pathway Level [] ---
    # Key functions: summarize_pathway_level, assay
    ---------------------------------------------------------------------
    min <- 12
    pathway_activity <- summarize_pathway_level(assay(airway, "counts"), kegg_sets, type = "mean", minsize = min)
    print(paste("Pathway activity score matrix has dimensions:", nrow(pathway_activity), ",", ncol(pathway_activity)))
    # --- Short Sets Detail [] ---
    # Key functions: short_sets_detail
    ---------------------------------------------------------------------
    short_sets <- short_sets_detail(kegg_sets, min)
    print(short_sets$short_sets)
    # --- Summarize Pathway Level [] ---
    # Key functions: summarize_pathway_level, assay
    ---------------------------------------------------------------------
    min <- 15
    pathway_activity <- summarize_pathway_level(assay(airway, "counts"), kegg_sets, type = "sd", minsize = min)
    print(paste("Pathway activity score matrix has dimensions:", nrow(pathway_activity), ",", ncol(pathway_activity)))
    head(pathway_activity)
    # --- Short Sets Detail [] ---
    # Key functions: short_sets_detail
    ---------------------------------------------------------------------
    min <- 8
    short_sets <- short_sets_detail(gocc_sets, min)
    print(head(short_sets$short_sets_molecules))
    # --- Summarize Pathway Level [] ---
    # Key functions: summarize_pathway_level
    ---------------------------------------------------------------------
    sd_gocc_expr <- summarize_pathway_level(X_expr, gocc_sets, type="sd", minsize=8)
    head(sd_gocc_expr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_funomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_funomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_funomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FUNOMICS:", paste0("    funomics: ", packageVersion("funOmics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_funomics_results.csv
    touch ${prefix}_funomics_output.rds
    echo "BIOC_FUNOMICS:" > versions.yml
    echo "    funomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FUNOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FUNOMICS(ch_input)

    emit:
    results  = BIOC_FUNOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FUNOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FUNOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FUNOMICS.out.versions  // channel: path(versions.yml)
}
