#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — convenient_pipeline
// Run the entire two-sample punctuated peak calling pipeline in a single function call.
// Input: STAT1_ChIP_eland_results.txt, STAT1_control_eland_results.txt
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSAICS_CONVENIENT_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("mosaics")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load the required Bioconductor package
    library(mosaics)
    
    # Define the expected input files in the working directory
    chip_input <- "STAT1_ChIP_eland_results.txt"
    control_input <- "STAT1_control_eland_results.txt"
    
    # Verify that the required user input files exist
    if (!file.exists(chip_input)) {
        stop(paste("Error: Required ChIP input file missing in working directory:", chip_input))
    }
    if (!file.exists(control_input)) {
        stop(paste("Error: Required Control input file missing in working directory:", control_input))
    }
    
    # Create the output directories to prevent write errors
    dir.create("./bin/", showWarnings = FALSE, recursive = TRUE)
    dir.create("./peak/", showWarnings = FALSE, recursive = TRUE)
    dir.create("./reports/", showWarnings = FALSE, recursive = TRUE)
    
    # Run the complete two-sample punctuated peak calling pipeline in a single function call.
    # All function and argument names are preserved exactly as documented.
    mosaicsRunAll( 
        chipFile=chip_input, 
        chipFileFormat="eland_result", 
        controlFile=control_input, 
        controlFileFormat="eland_result", 
        binfileDir="./bin/", 
        peakFile=c("./peak/STAT1_peak_list.bed", 
                   "./peak/STAT1_peak_list.gff"),
        peakFileFormat=c("bed", "gff"),
        reportSummary=TRUE, 
        summaryFile="./reports/mosaics_summary.txt", 
        reportExploratory=TRUE, 
        exploratoryFile="./reports/mosaics_exploratory.pdf", 
        reportGOF=TRUE, 
        gofFile="./reports/mosaics_GOF.pdf",
        byChr=FALSE, useChrfile=FALSE, chrfile=NULL, excludeChr="chrM",
        PET=FALSE, FDR=0.05, fragLen=200, binSize=200, capping=0,
        bgEst="rMOM", signalModel="BIC", parallel=FALSE, nCore=1 )
    
    message("mosaics convenient_pipeline workflow completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MOSAICS_CONVENIENT_PIPELINE":
        mosaics: \$(Rscript -e 'cat(as.character(packageVersion("mosaics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_convenient_pipeline.csv versions.yml
    """
}

workflow BIOC_MOSAICS_CONVENIENT_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ STAT1_ChIP_eland_results.txt, STAT1_control_eland_results.txt ] ]

    main:
    BIOC_MOSAICS_CONVENIENT_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MOSAICS_CONVENIENT_PIPELINE.out.tables
    plots    = BIOC_MOSAICS_CONVENIENT_PIPELINE.out.plots
    objects  = BIOC_MOSAICS_CONVENIENT_PIPELINE.out.objects
    versions = BIOC_MOSAICS_CONVENIENT_PIPELINE.out.versions
}
