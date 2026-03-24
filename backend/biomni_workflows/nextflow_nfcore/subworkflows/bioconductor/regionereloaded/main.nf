#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regioneReloaded
// RegioneReloaded is a package that allows simultaneous analysis of associations between genomic regio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regioneReloaded/inst/doc/regioneReloaded.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("regioneReloaded")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONERELOADED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionereloaded"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionereloaded:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regionereloaded:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regionereloaded_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionereloaded_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionereloaded_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(regioneReloaded)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: makeCrosswiseMatrix, plotCrosswiseMatrix
    ---------------------------------------------------------------------
    data("cw_Alien")
    cw_Alien_ReG<-makeCrosswiseMatrix(cw_Alien_ReG, pvcut = 1)
    plotCrosswiseMatrix(cw_Alien_ReG)
    # --- Togranges [] ---
    # Key functions: toGRanges, frame
    ---------------------------------------------------------------------
    AlienGenome <-
      toGRanges(data.frame(
        chr = c("AlChr1", "AlChr2", "AlChr3", "AlChr4"),
        start = c(rep(1, 4)),
    # --- Createrandomregions [] ---
    # Key functions: createRandomRegions
    ---------------------------------------------------------------------
    gnm <- AlienGenome
    nreg=100
    regA <-
      createRandomRegions(
    # --- Seq [] ---
    # Key functions: similarRegionSet
    ---------------------------------------------------------------------
    vectorPerc <- seq(0.1, 0.9, 0.1)
    RsetA <-
      similarRegionSet(
        GR = regA,
    # --- Seq [] ---
    # Key functions: sample, similarRegionSet
    ---------------------------------------------------------------------
    vectorPerc2 <- seq(0.2, 0.8, 0.2)
    regAB <- c(sample(regA, nreg / 2), sample(regB, nreg / 2))
    RsetAB <-
      similarRegionSet(
    # --- Createrandomregions [] ---
    # Key functions: createRandomRegions, subtractRegions
    ---------------------------------------------------------------------
    reg_no_A <-
      createRandomRegions(
        nregions = nreg,
        length.mean = 100,
    # --- Sample [] ---
    # Key functions: sample, toGRanges, frame, seqnames, start
    ---------------------------------------------------------------------
    dst <- sample(c(-300,300),length(regA),replace = TRUE)
    regD <- regioneR::toGRanges(
                        data.frame(
                          chr=as.vector(GenomeInfoDb::seqnames(regA)),
    # --- Data [] ---
    # Key functions: getParameters
    ---------------------------------------------------------------------
    data("cw_Alien")
    getParameters(cw_Alien_ReG)
    # --- Makecrosswisematrix [] ---
    # Key functions: makeCrosswiseMatrix
    ---------------------------------------------------------------------
    cw_Alien_RaR <- makeCrosswiseMatrix(cw_Alien_RaR)
    cw_Alien_ReG <- makeCrosswiseMatrix(cw_Alien_ReG)
    cw_Alien_ReR <- makeCrosswiseMatrix(cw_Alien_ReR)
    # --- Gethclust [] ---
    # Key functions: getHClust, plotCrosswiseMatrix
    ---------------------------------------------------------------------
    modX <- getHClust(cw_Alien_ReG,hctype = "rows")
    modY <- getHClust(cw_Alien_ReG,hctype = "cols")
    X<-modX$labels[modX$order]
    Y<-modY$labels[modX$order]
    # --- Plotcrosswisematrix [] ---
    # Key functions: plotCrosswiseMatrix
    ---------------------------------------------------------------------
    p_ReG_cor <- plotCrosswiseMatrix(cw_Alien_ReG, matrix_type = "correlation", ord_mat = ord)
    # p_ReR_cor <- plotCrosswiseMatrix(cw_Alien_ReR, matrix_type = "correlation", ord_mat = ord)
    plot(p_ReG_cor)
    # plot(p_ReR_cor)
    # --- Plotsinglept [] ---
    # Key functions: plotSinglePT
    ---------------------------------------------------------------------
    plotSinglePT(cw_Alien_ReG, RS1 = "regA", RS2 = "regA_05")
    # --- List [] ---
    # Key functions: plotCrosswiseDimRed
    ---------------------------------------------------------------------
    lsRegSet<-list(regA="regA",regB="regB",regC="regC")
    set.seed(42)
    plotCrosswiseDimRed(cw_Alien_ReG, nc = 6, type="PCA",listRS = lsRegSet)
    set.seed(42)
    # --- Getparameters [] ---
    # Key functions: getParameters, getMultiEvaluation
    ---------------------------------------------------------------------
    getParameters(mLZ_regA_ReG)
    mlz_Me <- getMultiEvaluation(rR = mLZ_regA_ReG )
    head(mlz_Me$resumeTable)
    # --- Makelzmatrix [] ---
    # Key functions: makeLZMatrix, getHClust
    ---------------------------------------------------------------------
    mLZ_regA_ReG <- makeLZMatrix(mLZ_regA_ReG)
    plot(getHClust(mLZ_regA_ReG),cex = 0.8)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionereloaded_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionereloaded_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionereloaded_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONERELOADED:", paste0("    regionereloaded: ", packageVersion("regioneReloaded"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionereloaded_results.csv
    touch ${prefix}_regionereloaded_output.rds
    echo "BIOC_REGIONERELOADED:" > versions.yml
    echo "    regionereloaded: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONERELOADED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONERELOADED(ch_input)

    emit:
    results  = BIOC_REGIONERELOADED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONERELOADED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONERELOADED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONERELOADED.out.versions  // channel: path(versions.yml)
}
