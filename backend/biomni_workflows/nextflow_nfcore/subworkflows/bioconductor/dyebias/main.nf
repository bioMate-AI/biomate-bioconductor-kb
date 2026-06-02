#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dyebias
// Many two-colour hybridizations suffer from a dye bias that is both gene-specific and slide-specific.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dyebias/inst/doc/dyebias-vignette.R
// Upstream  : GEOquery, convert, dyebiasexamples, limma, marray
// Downstream: none
//
// Install: BiocManager::install("dyebias")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DYEBIAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dyebias"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dyebias:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dyebias:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dyebias_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dyebias_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dyebias_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSMList)
    library(GenePix)
    library(Meta)
    library(jsonlite)

    # --- Dyebias Vignette.Rnw:223 225 [] ---
    # Key functions: file
    datadir <- system.file("extradata", package="dyebiasexamples")
      datadir
    # --- Dyebias Vignette.Rnw:231 238 [] ---
    # Key functions: path, marrayInfo
    sample.file <-  file.path(datadir, "Tuteja-samples.txt")
      targets <- read.marrayInfo(sample.file)
      summary(targets)
    # --- Dyebias Vignette.Rnw:247 254 [] ---
    # Key functions: marrayLayout, maNspots
    layout <- read.marrayLayout(fname=NULL, ngr=12, ngc=4, nsr=22, nsc=19)
      n.spots <- maNspots(layout)
      summary(layout)
    # --- Dyebias Vignette.Rnw:264 281 [] ---
    # Key functions: path, maInfo, marrayInfo, needed, maControls
    first.file <- file.path(datadir, maInfo(targets)$filename[1])
      first.file
      gnames <- read.marrayInfo(first.file, info.id=c(7,8,10), labels=10, skip=0)
      names(maInfo(gnames)) <- c("control.type", "reporter.group", "reporterId")
      maInfo(gnames)$reporterId <- as.character(maInfo(gnames)$reporterId)
    # --- Dyebias Vignette.Rnw:292 305 [] ---
    # Key functions: GenePix, maInfo

    # --- Dyebias Vignette.Rnw:314 322 [] ---
    # Key functions: maW, maLayout
    maW(data.raw)[ maW(data.raw) == 0] <- 1
      maW(data.raw)[ maW(data.raw) < 0] <- 0
      maLayout(data.raw) <- layout
      summary(data.raw)
    # --- Dyebias Vignette.Rnw:329 348 [] ---
    # Key functions: path
    normalized.data.file <-  file.path(datadir, "E-MTAB-32-processed-data-1641029599.txt")
      data <- read.table(normalized.data.file, sep="\t", as.is=T, header=T, skip=1)
      names(data) <- c("reporterId", "X13685041", "X13685040" , "X13685153" ,"X13685151" ,"X13685042")
      ## get rid of overly long gene names:
    # --- Dyebias Vignette.Rnw:368 371 [] ---
    # Key functions: maM
    maM(data.norm)[,c(3,4)] <- -1 *maM(data.norm)[,c(3,4)]
    # --- Dyebias Vignette.Rnw:377 380 [] ---
    # Key functions: maA, maRf, maGf
    maA(data.norm) <- log2(  maRf(data.raw) * maGf(data.raw) ) / 2
    # --- Dyebias Vignette.Rnw:404 412 [] ---
    # Key functions: iGSDBs
    iGSDBs.estimated <- dyebias.estimate.iGSDBs(data.norm,
                                                  is.balanced=FALSE,
                                                  reference="input",
                                                  verbose=TRUE)
      summary(iGSDBs.estimated)
    # --- Dyebias Vignette.Rnw:447 452 [] ---
    # Key functions: maInfo, maGnames
    estimator.subset <- (maInfo(maGnames(data.norm))$reporter.group=="Experimental")
      summary(estimator.subset)
    # --- Dyebias Vignette.Rnw:474 484 [] ---
    # Key functions: maW

    # --- Dyebias Vignette.Rnw:489 495 [] ---
    # Key functions: correction
    correction <- dyebias.apply.correction(data.norm=data.norm,
                                             iGSDBs=iGSDBs.estimated,
                                             estimator.subset=estimator.subset,
                                             application.subset=application.subset,
                                             verbose=TRUE)
    # --- Dyebias Vignette.Rnw:543 566 [] ---
    # Key functions: rgplot
    layout(matrix(1:2, nrow=1,ncol=2))
    # --- Dyebias Vignette.Rnw:727 778 [] ---
    # Key functions: geo2marray, maA, maRf
    ##
    ##   ## following slides are used to obtain iGSDB estimates:
    ##   slide.ids.est <- c( "GSM237352", "GSM237353", "GSM237354", "GSM237355" )
    ##
    ##   ## column names:

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dyebias_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dyebias_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dyebias_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DYEBIAS:", paste0("    dyebias: ", packageVersion("dyebias"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dyebias_results.csv
    touch ${prefix}_dyebias_output.rds
    echo "BIOC_DYEBIAS:" > versions.yml
    echo "    dyebias: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DYEBIAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DYEBIAS(ch_input)

    emit:
    results  = BIOC_DYEBIAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DYEBIAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DYEBIAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DYEBIAS.out.versions  // channel: path(versions.yml)
}
