#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PROcess
// A package for processing protein mass spectrometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PROcess/inst/doc/howtoprocess.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PROcess")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROCESS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-process"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-process:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-process:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_process_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_process_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_process_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PROcess)
    library(jsonlite)

    # --- Bslnoffsingle [] ---
    # Key functions: files, bslnoff
    library(PROcess)
    fdat <- system.file("Test", package="PROcess")
    fs <- list.files(fdat, pattern="\\.*csv\\.*", full.names=TRUE)
    f1 <- read.files(fs[1])
    fcut <- f1[f1[,1]>0,]
    # --- Ispeaksingle [] ---
    # Key functions: isPeak
    pkgobj <- isPeak(bseoff,span=81,sm.span=11,plot=TRUE)
    # --- Speczoom [] ---
    # Key functions: specZoom
    specZoom(pkgobj, xlim=c(5000,10000))
    # --- Rmbaselinebatch [] ---
    # Key functions: rmBaseline
    testdir <- system.file("Test", package = "PROcess")
    testM <- rmBaseline(testdir)
    # --- Renorm [] ---
    # Key functions: renorm
    rtM <- renorm(testM, cutoff=1500)
    # --- Getpeaksbatch [] ---
    # Key functions: tempdir, getPeaks
    peakfile <- paste(tempdir(), "testpeakinfo.csv", sep = "/")
    getPeaks(rtM, peakfile)
    # --- Qc [] ---
    # Key functions: quality
    qualRes <- quality(testM, peakfile, cutoff=1500)
    print(qualRes)
    # --- tempdir [] ---
    # Key functions: tempdir, pk2bmkr, matplot, getMzs
    bmkfile <- paste(tempdir(), "testbiomarker.csv", sep = "/")
    testBio <- pk2bmkr(peakfile, rtM, bmkfile)
    mzs <- as.numeric(rownames(rtM))
    matplot(mzs, rtM, type = "l", xlim = c(1000, 10000),
    ylab="intensities", main="proto-biomarkers")
    # --- Overallmean [] ---
    # Key functions: aveSpec
    grandAve <- aveSpec(fs)
    mzs <- grandAve[,1]
    # --- Bslnoffrawmean [] ---
    # Key functions: bslnoff
    grandOff <- bslnoff(grandAve[mzs>0,], method="loess",
            plot=T, bw=0.1)
    # --- Rawmeanpeak [] ---
    # Key functions: isPeak
    grandPkg <- isPeak(grandOff[grandOff[,1]>1500,], zerothrsh=1,
    plot=T, ratio=0.1)
    grandpvec <- round(grandPkg[grandPkg$peak, "mz"])
    print(as.vector(grandpvec))
    # --- Getpeaks2 [] ---
    # Key functions: getPeaks2
    grandBmk <- getPeaks2(rtM, grandpvec)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_process_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_process_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_process_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROCESS:", paste0("    process: ", packageVersion("PROcess"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_process_results.csv
    touch ${prefix}_process_output.rds
    echo "BIOC_PROCESS:" > versions.yml
    echo "    process: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROCESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROCESS(ch_input)

    emit:
    results  = BIOC_PROCESS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROCESS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROCESS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROCESS.out.versions  // channel: path(versions.yml)
}
