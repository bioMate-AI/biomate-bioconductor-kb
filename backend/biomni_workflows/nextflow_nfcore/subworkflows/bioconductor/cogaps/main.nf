#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CoGAPS
// Coordinated Gene Activity in Pattern Sets (CoGAPS) implements a Bayesian MCMC matrix factorization a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CoGAPS/inst/doc/CoGAPS.R
// Upstream  : Seurat, viridis
// Downstream: none
//
// Install: BiocManager::install("CoGAPS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COGAPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cogaps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cogaps:3.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cogaps:3.26.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cogaps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cogaps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cogaps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocFileCache)
    library(CoGAPS)
    library(CogapsParams)
    library(DefaultAssay)
    library(FeaturePlot)
    library(MANOVA)
    library(jsonlite)

    # --- new [] ---
    # Key functions: new, getParam, setParam
    params <- new("CogapsParams")
    getParam(params, "nPatterns")
    params <- setParam(params, "nPatterns", 3)
    # --- cogaps on modsim [] ---
    # Key functions: CoGAPS
    cogapsresult <- CoGAPS(modsimdata, params, outputFrequency = 10000)
    # --- load single cell data from zenodo [] ---
    # Key functions: BiocFileCache, bfcrpath
    options(timeout=50000) # adjust this if you're getting timeout downloading the file
    bfc <- BiocFileCache::BiocFileCache()
    pdac_data <- BiocFileCache::bfcrpath(bfc, pdac_url)
    # --- extract counts matrix [] ---
    # Key functions: log1p
    pdac_epi_counts <- as.matrix(pdac_data@assays$originalexp@counts)
    norm_pdac_epi_counts <- log1p(pdac_epi_counts)
    head(pdac_epi_counts, n=c(5L, 2L))
    # --- Cogaps Params [] ---
    # Key functions: CogapsParams
    library(CoGAPS)
    pdac_params <- CogapsParams(nIterations=50000, # 50000 iterations
    # --- distributed params [] ---
    # Key functions: setDistributedParams
    pdac_params <- setDistributedParams(pdac_params, nSets=7)
    # --- run CoGAPS on single [] ---
    # Key functions: CoGAPS, toCSV
    startTime <- Sys.time()
    pdac_epi_result <- CoGAPS(pdac_epi_counts, pdac_params)
    endTime <- Sys.time()
    # --- load precomputed from zenodo [] ---
    # Key functions: bfcrpath
    cogapsresult <- BiocFileCache::bfcrpath(bfc, cogapsresult_url)
    cogapsresult <- readRDS(cogapsresult)
    # --- pattern UMAP [] ---
    # Key functions: DefaultAssay, viridis, FeaturePlot
    DefaultAssay(pdac_data) <- "CoGAPS"
    pattern_names = rownames(pdac_data@assays$CoGAPS)
    library(viridis)
    # --- pattern Markers [] ---
    # Key functions: patternMarkers
    pm <- patternMarkers(cogapsresult)
    # --- get hallmarks [] ---
    # Key functions: getPatternGeneSet
    hallmark_ls <- list(
    "HALLMARK_ALLOGRAFT_REJECTION" = c(
    "HALLMARK_EPITHELIAL_MESENCHYMAL_TRANSITION" = c(
    # --- plot hallmarks [] ---
    # Key functions: plotPatternGeneSet
    pl_pattern7 <- plotPatternGeneSet(
    # --- MANOVA variables [] ---
    # Key functions: MANOVA
    interestedVariables <- cbind(pdac_data@meta.data[["nCount_RNA"]], pdac_data@meta.data[["nFeature_RNA"]])
    manova_results <- MANOVA(interestedVariables, cogapsresult)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cogaps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cogaps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cogaps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COGAPS:", paste0("    cogaps: ", packageVersion("CoGAPS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cogaps_results.csv
    touch ${prefix}_cogaps_output.rds
    echo "BIOC_COGAPS:" > versions.yml
    echo "    cogaps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COGAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_COGAPS(ch_input)

    emit:
    results  = BIOC_COGAPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COGAPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COGAPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COGAPS.out.versions  // channel: path(versions.yml)
}
