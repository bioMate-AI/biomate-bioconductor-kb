#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VanillaICE
// Hidden Markov Models for characterizing chromosomal alteration in high throughput SNP arrays.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VanillaICE/inst/doc/VanillaICE.R
// Upstream  : ArrayTV, IRanges, crlmm, doSNOW, foreach
// Downstream: MinimumDistance
//
// Install: BiocManager::install("VanillaICE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VANILLAICE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vanillaice"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vanillaice:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vanillaice:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vanillaice_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vanillaice_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vanillaice_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ArrayViews)
    library(CopyNumScanParams)
    library(EmissionParam)
    library(FilterParam)
    library(GRanges)
    library(HmmTrellisParam)
    library(IRanges)
    library(SnpExperiment)
    library(SnpGRanges)
    library(jsonlite)

    # --- Example Data [] ---
    # Key functions: registerDoSEQ, files
    library(VanillaICE)
    library(foreach)
    registerDoSEQ()
    extdir <- system.file("extdata", package="VanillaICE", mustWork=TRUE)
    files <- list.files(extdir, pattern="FinalReport")
    # --- Annotation File [] ---
    # Key functions: files
    list.files(extdir, pattern="SNP_info")
    # --- Featureannotation [] ---
    # Key functions: fread, path, GRanges, IRanges, SnpGRanges
    require(data.table)
    features <- suppressWarnings(fread(file.path(extdir, "SNP_info.csv")))
    fgr <- GRanges(paste0("chr", features$Chr), IRanges(features$Position, width=1),
                   isSnp=features[["Intensity Only"]]==0)
    fgr <- SnpGRanges(fgr)
    # --- Seqinfo [] ---
    # Key functions: seqlevels, seqinfo
    library(BSgenome.Hsapiens.UCSC.hg18)
    sl <- seqlevels(BSgenome.Hsapiens.UCSC.hg18)
    seqlevels(fgr) <- sl[sl %in% seqlevels(fgr)]
    seqinfo(fgr) <- seqinfo(BSgenome.Hsapiens.UCSC.hg18)[seqlevels(fgr),]
    fgr <- sort(fgr)
    # --- Sourcefiles [] ---
    # Key functions: files
    files <- list.files(extdir, full.names=TRUE, recursive=TRUE, pattern="FinalReport")
    # --- Arrayviews [] ---
    # Key functions: tempdir, ArrayViews, lrrFile, path, fileName
    ##
    ## A directory to keep parsed files
    ##
    parsedDir <- tempdir()
    # --- Fread [] ---
    # Key functions: fread
    ## read the first file
    dat <- fread(files[1], skip="[Data]")
    head(dat,n=3)
    # --- Scan Params [] ---
    # Key functions: CopyNumScanParams
    scan_params <- CopyNumScanParams(index_genome=index_genome,
                                     select=select_columns,
                                     cnvar="Log R Ratio",
                                     bafvar="B Allele Freq",
                                     gtvar=c("Allele1 - AB", "Allele2 - AB"))
    # --- Applyparsesourcefile [] ---
    # Key functions: parseSourceFile
    parseSourceFile(views, scan_params)
    # --- List Parsed Files [] ---
    # Key functions: files, parsedPath
    head(list.files(parsedPath(views)), n=3)
    # --- Views [] ---
    # Key functions: lrr, baf, genotypes
    lrr(views)[1:2, ]
    ## or
    lrr(views[1:2, ])
    ## B allele frequencies
    baf(views[1:2, ])
    # --- Snparrayexperiment [] ---
    # Key functions: SnpExperiment, show
    snp_exp <- SnpExperiment(views[, 4:5])
    show(snp_exp)
    # --- Emission Param [] ---
    # Key functions: EmissionParam
    param <- EmissionParam()
    # --- Temper [] ---
    # Key functions: EmissionParam, show
    param <- EmissionParam(temper=0.5)
    show(param)
    # --- Hmm [] ---
    # Key functions: hmm2, show
    fit <- hmm2(snp_exp, param)
    show(fit)
    length(fit)
    ## HMM object for the first sample
    fit[[1]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vanillaice_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vanillaice_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vanillaice_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VANILLAICE:", paste0("    vanillaice: ", packageVersion("VanillaICE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vanillaice_results.csv
    touch ${prefix}_vanillaice_output.rds
    echo "BIOC_VANILLAICE:" > versions.yml
    echo "    vanillaice: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VANILLAICE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VANILLAICE(ch_input)

    emit:
    results  = BIOC_VANILLAICE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VANILLAICE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VANILLAICE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VANILLAICE.out.versions  // channel: path(versions.yml)
}
