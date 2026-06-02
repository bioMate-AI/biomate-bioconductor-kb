#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CeTF
// This package provides the necessary functions for performing the Partial Correlation coefficient wit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CeTF/inst/doc/CeTF.R
// Upstream  : airway, dplyr, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("CeTF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CETF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cetf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cetf:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cetf:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cetf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cetf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cetf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CeTF)
    library(jsonlite)


    # --- Pcit [] ---
    # Key functions: colData, assay, conditions, rep, expDiff, function, normExp, PCIT
    # Loading packages
    library(CeTF)
    library(airway)
    library(kableExtra)
    library(knitr)

    # Loading airway data
    data("airway")

    # Creating a variable with annotation data
    # Example for trt condition
    histPlot(PCIT_out_trt$adj_sig)
    # Example for trt condition
    densityPlot(mat1 = PCIT_out_trt$adj_raw, 
               mat2 = PCIT_out_trt$adj_sig, 
               threshold = 0.5)

    # --- Rif [] ---
    # Key functions: colData, assay, conditions, rep, expDiff, function, normExp, Factors
    # Loading packages
    library(CeTF)
    library(airway)
    library(kableExtra)
    library(knitr)

    # Loading airway data
    data("airway")

    # Creating a variable with annotation data
    # Loading packages
    library(airway)
    library(CeTF)

    # Loading airway data
    data("airway")

    # Creating a variable with annotation data
    anno <- as.data.frame(colData(airway))


    # --- Smear Plot Tf [] ---
    # Key functions: output, SmearPlot, netConditionsPlot, NetworkData, getGroupGO, network1, gene1, gene2
    # Using the runAnalysis output (CeTF class object)
    SmearPlot(object = out,
              diffMethod = 'Reverter',
              lfc = 1.5,
              conditions = c('untrt', 'trt'),
              TF = 'ENSG00000185917',
              label = TRUE, 
              type = "TF")
    # Using the runAnalysis output (CeTF class object)
    netConditionsPlot(out)
    # Loading Homo sapiens annotation package
    library(org.Hs.eg.db)

    # Accessing the network for condition 1
    genes <- unique(c(as.character(NetworkData(out, "network1")[, "gene1"]), 
                      as.character(NetworkData(out, "network1")[, "gene2"])))

    # Performing getGroupGO analysis
    # --- Net Gotfplot1 [] ---
    # Key functions: netGOTFPlot, NetworkData, mutate, across, everything, network1, annotation, keytfs
    library(dplyr)

    # Subsetting only the first 12 Ontologies with more counts
    t1 <- head(cond1$results, 12)

    # Subsetting the network for the conditions to make available only the 12 nodes subsetted
    t2 <- subset(cond1$netGO, cond1$netGO$gene1 %in% as.character(t1[, "ID"]))

    # generating the GO plot grouping by pathways
    # --- Rifplot2 [] ---
    # Key functions: RIFPlot, darkblue, NetworkData, getEnrich, network1, gene1, gene2, heatPlot
    RIFPlot(object = out,
            color  = "darkblue",
            type   = "DE")
    # Selecting the genes related to the network for condition 1
    genes <- unique(c(as.character(NetworkData(out, "network1")[, "gene1"]), 
                      as.character(NetworkData(out, "network1")[, "gene2"])))

    # Performing enrichment analysis
    cond1 <- getEnrich(genes = genes, organismDB = org.Hs.eg.db, 
                      keyType = 'ENSEMBL', ont = 'BP', fdrMethod = "BH", 
                      fdrThr = 0.05, minGSSize = 5, maxGSSize = 500)
    heatPlot(res = cond1$results,
             diff = getDE(out, "all"))

    # --- Circle [] ---
    # Key functions: enrichPlot, circle, bar, dot
    enrichPlot(res = cond1$results,
               type = "circle")
    enrichPlot(res = cond1$results,
               type = "bar")
    enrichPlot(res = cond1$results,
               type = "dot")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cetf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cetf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cetf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CETF:", paste0("    cetf: ", packageVersion("CeTF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cetf_results.csv
    touch ${prefix}_cetf_output.rds
    echo "BIOC_CETF:" > versions.yml
    echo "    cetf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CETF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CETF(ch_input)

    emit:
    results  = BIOC_CETF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CETF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CETF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CETF.out.versions  // channel: path(versions.yml)
}
