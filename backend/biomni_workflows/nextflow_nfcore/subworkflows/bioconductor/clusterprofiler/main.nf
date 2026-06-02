#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clusterProfiler
// This package supports functional characteristics of both coding and non-coding genomics data for tho
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/021-go.html
// Upstream  : none
// Downstream: maEndToEnd
//
// Install: BiocManager::install("clusterProfiler")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERPROFILER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterprofiler"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterprofiler:4.14.6--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterprofiler:4.14.6--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterprofiler_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterprofiler_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterprofiler_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clusterProfiler)
    library(jsonlite)

    # --- GO classification [] ---
    # Key functions: data, groupGO
    library(clusterProfiler)
    library(org.Hs.eg.db)
    
    data(geneList, package="DOSE")
    gene <- names(geneList)[abs(geneList) > 2]
    
    # Entrez gene ID
    head(gene)
    
    # --- GO over-representation analysis [] ---
    # Key functions: enrichGO, bitr
    ego <- enrichGO(gene          = gene,
                    universe      = names(geneList),
                    OrgDb         = org.Hs.eg.db,
                    ont           = "CC",
                    pAdjustMethod = "BH",
                    pvalueCutoff  = 0.01,
                    qvalueCutoff  = 0.05,
            readable      = TRUE)
    head(ego)
    
    # --- GO Gene Set Enrichment Analysis [] ---
    # Key functions: gseGO
    ego3 <- gseGO(geneList     = geneList,
                  OrgDb        = org.Hs.eg.db,
                  ont          = "CC",
                  minGSSize    = 100,
                  maxGSSize    = 500,
                  pvalueCutoff = 0.05,
                  verbose      = FALSE)
    # --- GO analysis for non-model organisms [] ---
    # Key functions: useEnsemblGenomes, getBM
    library(biomaRt)
    ensembl <- useEnsemblGenomes(biomart = "plants_mart", dataset = "nattenuata_eg_gene")
    gene2go <- getBM(attributes =c("ensembl_gene_id", "go_id"), mart=ensembl)
    # --- Visualize enriched GO terms as a directed acyclic graph [] ---
    # Key functions: goplot
    goplot(ego)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterprofiler_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterprofiler_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterprofiler_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERPROFILER:", paste0("    clusterprofiler: ", packageVersion("clusterProfiler"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterprofiler_results.csv
    touch ${prefix}_clusterprofiler_output.rds
    echo "BIOC_CLUSTERPROFILER:" > versions.yml
    echo "    clusterprofiler: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERPROFILER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERPROFILER(ch_input)

    emit:
    results  = BIOC_CLUSTERPROFILER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERPROFILER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERPROFILER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERPROFILER.out.versions  // channel: path(versions.yml)
}
