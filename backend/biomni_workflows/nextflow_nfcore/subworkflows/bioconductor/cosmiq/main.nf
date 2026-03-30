#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cosmiq
// cosmiq is a tool for the preprocessing of liquid- or gas - chromatography mass spectrometry (LCMS/GC
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cosmiq/inst/doc/cosmiq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cosmiq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSMIQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cosmiq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cosmiq:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cosmiq:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cosmiq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cosmiq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cosmiq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cosmiq)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame
    class <- as.data.frame(c(rep("KO",6),rep("WT", 6)))
    rownames(class) <- basename(my.input.files)
    xs@phenoData <- class
    # --- Combine Spectra [] ---
    # Key functions: combine_spectra
    x <- combine_spectra(xs=xs, mzbin=0.25,
    	linear=TRUE, continuum=FALSE)
    plot(x$mz, x$intensity, type='l',
    	main='combined spectra',
    	xlab='m/Z', ylab='ion intensity')
    # --- Peakdetection [] ---
    # Key functions: peakdetection
    xy <- peakdetection(x=x$mz, y=x$intensity,
        scales=1:10,
        SNR.Th=1.0,
        SNR.area=20, mintr=0.5)
    id.peakcenter<-xy[,4]
    # --- Matrix [] ---
    # Key functions: retcor
    # create dummy object
    xs@peaks <- matrix(c(rep(1, length(my.input.files) * 6),
    	1:length(my.input.files)), ncol=7)
    colnames(xs@peaks) <- c("mz", "mzmin", "mzmax", "rt",
    	"rtmin", "rtmax", "sample")
    # --- Eicmatrix [] ---
    # Key functions: eicmatrix, performance, map, double
    eicmat <- eicmatrix(xs=xs, xy=xy, center=1)
    #
    #  process a reduced mz range for a better package build performance
    (eicmat.mz.range <- range(which(475 < xy[,1] & xy[,1] < 485)))
    eicmat.filter <- eicmat[eicmat.mz.range[1]:eicmat.mz.range[2],]
    # --- Create Datamatrix [] ---
    # Key functions: create_datamatrix
    xs <- create_datamatrix(xs=xs, rxy=rxy)
    # --- Peaktable [] ---
    # Key functions: peakTable, rowSums
    peaktable <- xcms::peakTable(xs)
    idx <- order(rowSums(peaktable[,8:19]), decreasing=TRUE)
    head(peaktable[idx,])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cosmiq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cosmiq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cosmiq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COSMIQ:", paste0("    cosmiq: ", packageVersion("cosmiq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosmiq_results.csv
    touch ${prefix}_cosmiq_output.rds
    echo "BIOC_COSMIQ:" > versions.yml
    echo "    cosmiq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COSMIQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COSMIQ(ch_input)

    emit:
    results  = BIOC_COSMIQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COSMIQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COSMIQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COSMIQ.out.versions  // channel: path(versions.yml)
}
