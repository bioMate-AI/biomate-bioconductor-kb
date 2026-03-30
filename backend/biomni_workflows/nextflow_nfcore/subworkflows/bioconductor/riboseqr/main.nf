#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: riboSeqR
// Plotting functions, frameshift detection and parsing of sequencing data from ribosome profiling expe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/riboSeqR/inst/doc/riboSeqR.R
// Upstream  : baySeq
// Downstream: none
//
// Install: BiocManager::install("riboSeqR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-riboseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-riboseqr:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-riboseqr:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_riboseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_riboseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_riboseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(riboSeqR)
    library(jsonlite)

    # --- Readribodata [] ---
    # Key functions: readRibodata
    riboDat <- readRibodata(ribofiles, replicates = c("WT", "WT", "M", "M"))
    # --- Framecounting [] ---
    # Key functions: frameCounting
    fCs <- frameCounting(riboDat, fastaCDS)
    # --- Frameshift [] ---
    # Key functions: readingFrame, plotFS
    fS <- readingFrame(rC = fCs); fS
    plotFS(fS)
    # --- Filterhits [] ---
    # Key functions: filterHits
    ffCs <- filterHits(fCs, lengths = c(27, 28), frames = list(1, 0),
                       hitMean = 50, unqhitMean = 10, fS = fS)
    # --- Plotcds27 [] ---
    # Key functions: plotCDS
    plotCDS(coordinates = ffCs@CDS, riboDat = riboDat, lengths = 27)
    # --- Plotcds28 [] ---
    # Key functions: plotCDS
    plotCDS(coordinates = ffCs@CDS, riboDat = riboDat, lengths = 28)
    # --- Figcds27 [] ---
    # Key functions: plotCDS
    plotCDS(coordinates = ffCs@CDS, riboDat = riboDat, lengths = 27)
    # --- Figcds28 [] ---
    # Key functions: plotCDS
    plotCDS(coordinates = ffCs@CDS, riboDat = riboDat, lengths = 28)
    # --- Plottranscript [] ---
    # Key functions: plotTranscript
    plotTranscript("CUFF.37930.1", coordinates = ffCs@CDS,
                   riboData = riboDat, length = 27, cap = 200)
    # --- Figtran [] ---
    # Key functions: plotTranscript
    plotTranscript("CUFF.37930.1", coordinates = ffCs@CDS,
                   riboData = riboDat, length = 27, cap = 200)
    # --- Slicecounts [] ---
    # Key functions: sliceCounts
    riboCounts <- sliceCounts(ffCs, lengths = c(27, 28), frames = list(0, 2))
    # --- Rnacounts [] ---
    # Key functions: rnaCounts
    rnaCounts <- rnaCounts(riboDat, ffCs@CDS)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_riboseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_riboseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_riboseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIBOSEQR:", paste0("    riboseqr: ", packageVersion("riboSeqR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_riboseqr_results.csv
    touch ${prefix}_riboseqr_output.rds
    echo "BIOC_RIBOSEQR:" > versions.yml
    echo "    riboseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIBOSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIBOSEQR(ch_input)

    emit:
    results  = BIOC_RIBOSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIBOSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIBOSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIBOSEQR.out.versions  // channel: path(versions.yml)
}
