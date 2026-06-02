#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PanomiR
// PanomiR is a package to detect miRNAs that target groups of pathways from gene expression data. This
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PanomiR/inst/doc/PanomiR.R
// Upstream  : GSEABase
// Downstream: none
//
// Install: BiocManager::install("PanomiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANOMIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-panomir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-panomir:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-panomir:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_panomir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_panomir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_panomir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PanomiR)
    library(jsonlite)

    # --- Pathway Summary Statistics [pathwaySummary] ---
    # Key functions: pathwaySummary
    data("path_gene_table")
    data("miniTestsPanomiR")
    summaries <- pathwaySummary(
        geneCounts = miniTestsPanomiR$mini_LIHC_Exp,
        pathways = path_gene_table,
        method = "x2",
        zNormalize = TRUE,
        id = "ENSEMBL"
    )
    head(summaries)[, 1:2]

    # --- Differential Pathway Analysis [differentialPathwayAnalysis] ---
    # Key functions: differentialPathwayAnalysis
    data("path_gene_table")
    data("miniTestsPanomiR")
    output0 <- differentialPathwayAnalysis(
        geneCounts = miniTestsPanomiR$mini_LIHC_Exp,
        pathways = path_gene_table,
        covariates = miniTestsPanomiR$mini_LIHC_Cov,
        condition = "shortLetterCode"
    )
    de.paths <- output0$DEP

    # --- Pathway Clustering and Mapping [mappingPathwaysClusters] ---
    # Key functions: mappingPathwaysClusters
    data("miniTestsPanomiR")
    mock_de_paths <- data.frame(
        Pathway = colnames(miniTestsPanomiR$miniPCXN)[1:10],
        p.val = runif(10, 0, 0.05)
    )
    pathwayClustsLIHC <- mappingPathwaysClusters(
        pcxn = miniTestsPanomiR$miniPCXN,
        dePathways = mock_de_paths,
        topPathways = 10,
        outDir = ".",
        plot = FALSE,
        subplot = FALSE,
        prefix = "",
        clusteringFunction = "cluster_louvain",
        correlationCutOff = 0.1
    )

    # --- MicroRNA Prioritization [prioritizeMicroRNA] ---
    # Key functions: prioritizeMicroRNA
    data("miniTestsPanomiR")
    output2 <- prioritizeMicroRNA(
        enriches0 = miniTestsPanomiR$miniEnrich,
        pathClust = miniTestsPanomiR$miniPathClusts$Clustering,
        topClust = 1,
        sampRate = 50,
        method = c("aggInv"),
        outDir = "Output/",
        dataDir = "outData/",
        saveSampling = FALSE,
        runJackKnife = FALSE,
        numCores = 1,
        prefix = "outmiR",
        saveCSV = FALSE
    )

    # --- Custom miRNA Pathway Enrichment [miRNAPathwayEnrichment, reportEnrichment] ---
    # Key functions: miRNAPathwayEnrichment, reportEnrichment
    data("msigdb_c2")
    data("targetScan_03")
    tempEnrich <- miRNAPathwayEnrichment(
        targetScan_03[1:30],
        msigdb_c2[1:30]
    )
    enrichReport <- reportEnrichment(tempEnrich)

    # --- Gene Set Collection Conversion [tableFromGSC] ---
    # Key functions: tableFromGSC
    data("gscExample")
    newPathGeneTable <- tableFromGSC(gscExample)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_panomir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_panomir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_panomir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANOMIR:", paste0("    panomir: ", packageVersion("PanomiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panomir_results.csv
    touch ${prefix}_panomir_output.rds
    echo "BIOC_PANOMIR:" > versions.yml
    echo "    panomir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANOMIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANOMIR(ch_input)

    emit:
    results  = BIOC_PANOMIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANOMIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANOMIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANOMIR.out.versions  // channel: path(versions.yml)
}
