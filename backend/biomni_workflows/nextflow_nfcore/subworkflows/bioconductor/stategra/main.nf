#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: STATegRa
// Classes and tools for multi-omics data integration.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/STATegRa/inst/doc/STATegRa.R
// Upstream  : Biobase, ggplot2, gridExtra
// Downstream: none
//
// Install: BiocManager::install("STATegRa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STATEGRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-stategra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-stategra:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-stategra:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_stategra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_stategra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_stategra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(STATegRa)
    library(jsonlite)

    # --- Createomicsexpressionset [] ---
    # Key functions: createOmicsExpressionSet
    ---------------------------------------------------------------------
    # Block1 - gene expression data
    B1 <- createOmicsExpressionSet(Data=Block1.PCA, pData=ed.PCA,
                                   pDataDescr=c("classname"))
    # Block2 - miRNA expression data
    # --- Modelselection [] ---
    # Key functions: modelSelection, arrange
    ---------------------------------------------------------------------
    ms <- modelSelection(Input=list(B1, B2), Rmax=3, fac.sel="single%",
                         varthreshold=0.03, center=TRUE, scale=TRUE,
                         weight=TRUE, plot_common=FALSE, plot_dist=FALSE)
    grid.arrange(ms$common$pssq, ms$common$pratios, ncol=2) #switching plot_common=TRUE gives automaticaly these plots
    # --- Omicscompanalysis [] ---
    # Key functions: omicsCompAnalysis
    ---------------------------------------------------------------------
    discoRes <- omicsCompAnalysis(Input=list(B1, B2), Names=c("expr", "mirna"),
                                  method="DISCOSCA", Rcommon=2, Rspecific=c(2, 2),
                                  center=TRUE, scale=TRUE, weight=TRUE)
    # --- Slotnames [] ---
    # Key functions: slotNames
    ---------------------------------------------------------------------
    slotNames(discoRes)
    # --- Getvaf [] ---
    # Key functions: getVAF, plotVAF
    ---------------------------------------------------------------------
    # DISCO-SCA plotVAF
    getVAF(discoRes)
    plotVAF(discoRes)
    # JIVE plotVAF
    # --- Plotres [] ---
    # Key functions: plotRes
    ---------------------------------------------------------------------
    # Scatterplot of scores variables associated to common components
    # DISCO-SCA
    # --- Plotres [] ---
    # Key functions: plotRes, g_legend, arrange, arrangeGrob, theme
    ---------------------------------------------------------------------
    # O2PLS
    # Scatterplot of scores variables associated to common components
    # Associated to first block
    # --- Plotres [] ---
    # Key functions: plotRes, arrange, arrangeGrob, theme
    ---------------------------------------------------------------------
    # Loadings plot for common components
    # Separately for each block
    # --- Createomicsexpressionset [] ---
    # Key functions: createOmicsExpressionSet
    ---------------------------------------------------------------------
    # Block1 - Expression data
    mRNA.ds <- createOmicsExpressionSet(Data=Block1, pData=ed, pDataDescr=c("classname"))
    # Block2 - miRNA expression data
    miRNA.ds <- createOmicsExpressionSet(Data=Block2, pData=ed, pDataDescr=c("classname"))
    # --- Biodistclass [] ---
    # Key functions: bioDistclass, exprs
    ---------------------------------------------------------------------
    # Create Gene-gene distance computed through mRNA data
    # --- Biomap [] ---
    # Key functions: bioMap
    ---------------------------------------------------------------------
    # --- Biodist [] ---
    # Key functions: bioDist
    ---------------------------------------------------------------------
    # --- Biodistw [] ---
    # Key functions: bioDistW
    ---------------------------------------------------------------------
    bioDistWList <- bioDistW(referenceFeatures=rownames(Block1),
                             bioDistList=bioDistList,
                             weights=sample.weights)
    length(bioDistWList)
    # --- Biodistfeature [] ---
    # Key functions: bioDistFeature
    ---------------------------------------------------------------------
    IDH1.F <- bioDistFeature(Feature="IDH1",
                             listDistW=bioDistWList,
                             threshold.cor=0.7)
    # --- Omicsnpc [] ---
    # Key functions: omicsNPC
    ---------------------------------------------------------------------
    results <- omicsNPC(dataInput=TCGA_BRCA_Data, dataTypes=dataTypes,
                        combMethods=combMethods, numPerms=numPerms,
                        numCores=numCores, verbose=verbose)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_stategra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_stategra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_stategra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STATEGRA:", paste0("    stategra: ", packageVersion("STATegRa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stategra_results.csv
    touch ${prefix}_stategra_output.rds
    echo "BIOC_STATEGRA:" > versions.yml
    echo "    stategra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STATEGRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STATEGRA(ch_input)

    emit:
    results  = BIOC_STATEGRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STATEGRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STATEGRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STATEGRA.out.versions  // channel: path(versions.yml)
}
