#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multistateQTL
// A collection of tools for doing various analyses of multi-state QTL data, with a focus on visualizat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multistateQTL/inst/doc/multiStateQTL.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("multistateQTL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTISTATEQTL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multistateqtl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multistateqtl:1.2.2--r44_0' :
        'quay.io/biocontainers/bioconductor-multistateqtl:1.2.2--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_multistateqtl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multistateqtl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multistateqtl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(multistateQTL)
    library(jsonlite)


    # --- Demo Sumstats2qtle [] ---
    # Key functions: sumstats2qtle, betas, extdata, multistateQTL, lung, thyroid, spleen, blood
    input_path <- system.file("extdata", package="multistateQTL")
    state <- c("lung", "thyroid", "spleen", "blood")

    input <- data.frame(
        state=state, 
        path=paste0(input_path, "/GTEx_tx_", state, ".tsv"))

    # --- Basic Simulation [] ---
    # Key functions: qtleSimulate, rowData
    sim <- qtleSimulate(nTests=1000, nStates=6, global=0.5)
    sim
    head(rowData(sim))
    sim <- qtleSimulate(
        nStates=10, nFeatures=100, nTests=1000,
        global=0.2, multi=0.4, unique=0.2, k=2)

    # --- Snapshot Unique [] ---
    # Key functions: rowData, multistate, sample, assay, betas, errors, lfsrs
    head(rowData(subset(sim, QTL == "unique")))
    head(rowData(subset(sim, QTL == "multistate")))

    message("Number of QTL specific to each state-group:")
    table(rowData(subset(sim, QTL == "multistate"))$multistateGroup)
    na_pattern <- sample(seq(1, ncol(sim)*nrow(sim)), 1000)

    sim_na <- sim
    assay(sim_na, "betas")[na_pattern] <- NA
    assay(sim_na, "errors")[na_pattern] <- NA
    assay(sim_na, "lfsrs")[na_pattern] <- NA

    message("Number of simulated tests: ", nrow(sim_na))
    head(betas(sim_na))

    # --- Remove 50p Missing [] ---
    # Key functions: getComplete, replaceNAs, betas, callSignificance, colData, lfsrs
    sim_na <- getComplete(sim_na, n=0.5, verbose=TRUE)
    sim_na <- replaceNAs(sim_na, verbose=TRUE)

    head(betas(sim_na))
    sim <- callSignificance(sim, assay="lfsrs", thresh=0.05)

    message("Median number of significant tests per state: ", 
        median(colData(sim)$nSignificant))

    # --- Simple Sig Calling Performance [] ---
    # Key functions: callSignificance, simPerformance, function, lfsrs, simple, getSignificant, getTopHits, runPairwiseSharing
    sim <- callSignificance(sim, assay="lfsrs", thresh=0.001)
    perf_metrics <- simPerformance(sim)
    lapply(perf_metrics, FUN=function(x) {round(x, 2)})
    sim <- callSignificance(
        sim, mode="simple", assay="lfsrs",
        thresh=0.0001, secondThresh=0.0002)
    simPerformance(sim)$recall
    sim_sig <- getSignificant(sim)
    sim_top <- getTopHits(sim_sig, assay="lfsrs", mode="state")
    sim_top <- runPairwiseSharing(sim_top)
    p1 <- plotPairwiseSharing(sim_top, annotate_cols=c("nSignificant", "multistateGroup"))

    # --- Upset Plot [] ---
    # Key functions: plotUpSet, nSignificant, multistateGroup, runTestMetrics, plotCompareStates, rowData, plotQTLClusters, multistate
    plotUpSet(sim_top, annotateColsBy=c("nSignificant", "multistateGroup"))
    sim_top <- runTestMetrics(sim_top)

    plotCompareStates(sim_top, x="S01", y="S02")

    table(rowData(sim_top)$qtl_type)

    hist(rowData(sim_top)$nSignificant)
    sim_top_ms <- subset(sim_top, qtl_type_simple == "multistate")

    plotQTLClusters(
        sim_top_ms, 
        annotateColsBy=c("multistateGroup"),
        annotateRowsBy=c("qtl_type", "mean_beta", "QTL"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multistateqtl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multistateqtl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multistateqtl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTISTATEQTL:", paste0("    multistateqtl: ", packageVersion("multistateQTL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multistateqtl_results.csv
    touch ${prefix}_multistateqtl_output.rds
    echo "BIOC_MULTISTATEQTL:" > versions.yml
    echo "    multistateqtl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTISTATEQTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_MULTISTATEQTL(ch_input)

    emit:
    results  = BIOC_MULTISTATEQTL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTISTATEQTL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTISTATEQTL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTISTATEQTL.out.versions  // channel: path(versions.yml)
}
