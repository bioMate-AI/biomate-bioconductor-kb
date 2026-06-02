#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miloR
// Milo performs single-cell differential abundance testing. Cell states are modelled as representative
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miloR/inst/doc/milo_contrasts.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("miloR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MILOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-milor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-milor:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-milor:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_milor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_milor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_milor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MouseSMARTseqData)
    library(jsonlite)

    # --- Mousesmartseqdata [] ---
    # Key functions: MouseSMARTseqData, logNormCounts
    ---------------------------------------------------------------------
    thy.sce <- MouseSMARTseqData() # this function downloads the full SCE object
    thy.sce <- logNormCounts(thy.sce)
    thy.sce
    # --- Buildgraph [] ---
    # Key functions: buildGraph, makeNhoods, colData, countCells, frame
    ---------------------------------------------------------------------
    # we build KNN graph
    thy.milo <- buildGraph(thy.milo, k = 11, d = 40)
    thy.milo <- makeNhoods(thy.milo, prop = 0.2, k = 11, d=40, refined = TRUE, refinement_scheme="graph") # make nhoods using graph-only as this is faster
    colData(thy.milo)$Sample <- paste(colData(thy.milo)$SortDay, colData(thy.milo)$Age, sep="_")
    # --- Plotnhoodsizehist [] ---
    # Key functions: plotNhoodSizeHist
    ---------------------------------------------------------------------
    plotNhoodSizeHist(thy.milo)
    # --- Frame [] ---
    # Key functions: frame, colData, distinct, nhoodCounts
    ---------------------------------------------------------------------
    thy.design <- data.frame(colData(thy.milo))[,c("Sample", "SortDay", "Age")]
    thy.design <- distinct(thy.design)
    rownames(thy.design) <- thy.design$Sample
    ## Reorder rownames to match columns of nhoodCounts(milo)
    # --- Rownames [] ---
    # Key functions: testNhoods
    ---------------------------------------------------------------------
    rownames(thy.design) <- thy.design$Sample
    contrast.1 <- c("Age1wk - Age4wk") # the syntax is <VariableName><ConditionLevel> - <VariableName><ControlLevel>
    # we need to use the ~ 0 + Variable expression here so that we have all of the levels of our variable as separate columns in our model matrix
    da_results <- testNhoods(thy.milo, design = ~ 0 + Age, design.df = thy.design, model.contrasts = contrast.1,
    # --- Testnhoods [] ---
    # Key functions: testNhoods
    ---------------------------------------------------------------------
    contrast1.res <- testNhoods(thy.milo, design=~0+ Age, design.df=thy.design, fdr.weighting="graph-overlap", model.contrasts = contrast.all)
    head(contrast1.res)
    # --- Matrix [] ---
    # Key functions: makeContrasts
    ---------------------------------------------------------------------
    model <- model.matrix(~ 0 + Age, data=thy.design)
    ave.contrast <- c("Age1wk - (Age4wk + Age16wk + Age32wk + Age52wk)/4")
    mod.constrast <- makeContrasts(contrasts=ave.contrast, levels=model)
    mod.constrast
    # --- Testnhoods [] ---
    # Key functions: testNhoods
    ---------------------------------------------------------------------
    da_results <- testNhoods(thy.milo, design = ~ 0 + Age, design.df = thy.design, model.contrasts = ave.contrast, fdr.weighting="graph-overlap")
    table(da_results$SpatialFDR < 0.1)
    head(da_results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_milor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_milor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_milor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MILOR:", paste0("    milor: ", packageVersion("miloR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_milor_results.csv
    touch ${prefix}_milor_output.rds
    echo "BIOC_MILOR:" > versions.yml
    echo "    milor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MILOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_MILOR(ch_input)

    emit:
    results  = BIOC_MILOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MILOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MILOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MILOR.out.versions  // channel: path(versions.yml)
}
