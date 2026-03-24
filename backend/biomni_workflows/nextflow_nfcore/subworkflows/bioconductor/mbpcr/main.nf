#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mBPCR
// It contains functions for estimating the DNA copy number profile using mBPCR with the aim of detecti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mBPCR/inst/doc/mBPCR.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("mBPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbpcr:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbpcr:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mBPCR)
    library(jsonlite)

    # --- Array [] ---
    # Key functions: array
    A <- array(1, dim=(maxProbeNumber+1)*(maxProbeNumber+2)/2)
    # --- Estprofilewithmbpcr [] ---
    # Key functions: estProfileWithMBPCR
    results <- estProfileWithMBPCR(rec10k$SNPname, rec10k$Chromosome, rec10k$PhysicalPosition, rec10k$log2ratio, chrToBeAnalyzed=c(3,5), maxProbeNumber=1000)
    # --- Writeestprofile [] ---
    # Key functions: writeEstProfile
    writeEstProfile(path='', sampleName='rec10k',rec10k$SNPname, rec10k$Chromosome, rec10k$PhysicalPosition, rec10k$log2ratio, chrToBeWritten=c(3,5), results$estPC, results$estBoundaries)
    # --- Gentable1 [] ---
    # Key functions: xtable, label, caption, align
    xx <- xtable(head(temp$mBPCRestimate))
    label(xx) <- "tab_mBPCR"
    caption(xx) <- "Example of table containing the profile estimated with mBPCR."
    align(xx) <- c("|c|","|c|","c|","c|","c|","c|")
    print(xx,latex.environments=c("center","small"),include.rownames=FALSE)
    # --- Gentable2 [] ---
    # Key functions: xtable, label, caption, align
    xx <- xtable(head(temp$mBPCRbreakpoints))
    label(xx) <- "tab_bounds"
    caption(xx) <- "Example of table containing a summary of the breakpoints estimated with mBPCR."
    align(xx) <- c("|c|","|c|","c|","c|","c|","c|","c|","c|")
    print(xx,latex.environments=c("center","small"),include.rownames=FALSE)
    # --- Estprofilewithmbpcr [] ---
    # Key functions: estProfileWithMBPCR
    results <- estProfileWithMBPCR(rec10k$SNPname, rec10k$Chromosome, rec10k$PhysicalPosition, rec10k$log2ratio, chrToBeAnalyzed=3, regr='BRC', maxProbeNumber=1000)
    # --- Plotestprofile [] ---
    # Key functions: plotEstProfile
    plotEstProfile(sampleName='rec10k', rec10k$Chromosome, rec10k$PhysicalPosition, rec10k$log2ratio, chrToBePlotted=3, results$estPC, maxProbeNumber=2000, regrCurve=results$regrCurve, regr='BRC')
    # --- Data [] ---
    # Key functions: data
    ## data(jekoChr11Array250Knsp)
    # --- Array [] ---
    # Key functions: array
    ## A <- array(1, dim=(maxProbeNumber+1)*(maxProbeNumber+2)/2)
    # --- Estprofilewithmbpcr [] ---
    # Key functions: estProfileWithMBPCR
    ## results <- estProfileWithMBPCR(jekoChr11Array250Knsp$SNPname, jekoChr11Array250Knsp$Chromosome, jekoChr11Array250Knsp$PhysicalPosition, jekoChr11Array250Knsp$log2ratio, chrToBeAnalyzed=11, maxProbeNumber=9000, rhoSquare=0.0479, nu=-3.012772e-10, sigmaSquare=0.0699)
    # --- Plotestprofile [] ---
    # Key functions: plotEstProfile
    ## plotEstProfile(sampleName='jeko250Knsp', jekoChr11Array250Knsp$Chromosome, jekoChr11Array250Knsp$PhysicalPosition, jekoChr11Array250Knsp$log2ratio, chrToBePlotted=11, results$estPC, maxProbeNumber=9000)
    # --- Estglobparam [] ---
    # Key functions: estGlobParam
    estGlobParam(rec10k$log2ratio)
    # --- Data [] ---
    # Key functions: data
    data(jekoChr11Array250Knsp)
    # --- Computembpcr [] ---
    # Key functions: computeMBPCR
    results <- computeMBPCR(y, nu=-3.012772e-10, rhoSquare=0.0479, sigmaSquare=0.0699, regr='BRC')
    # --- Importcndata [] ---
    # Key functions: importCNData
    rec10k <- importCNData(path, NRowSkip=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBPCR:", paste0("    mbpcr: ", packageVersion("mBPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbpcr_results.csv
    touch ${prefix}_mbpcr_output.rds
    echo "BIOC_MBPCR:" > versions.yml
    echo "    mbpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBPCR(ch_input)

    emit:
    results  = BIOC_MBPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBPCR.out.versions  // channel: path(versions.yml)
}
