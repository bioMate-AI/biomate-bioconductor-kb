#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EventPointer — junction_array_pipeline
// Identify and analyze alternative splicing events from Affymetrix junction microarrays.
// Input: exon_probes.txt, junction_probes.txt, reference_transcriptome.gtf, microarray_data.cel
// Container: quay.io/biocontainers/bioconductor-eventpointer:3.18.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EventPointer, R.utils, aroma.affymetrix
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a custom CDF file using CDFfromGTF
//  * 2. [Visualization & Output] Preprocess CEL files using the aroma.affymetrix pipeline to extract summarized expression data
//  * 3. [Core Analysis] Run statistical analysis and calculate delta PSI using EventPointer
//  * 4. [Visualization & Output] Generate GTF files for IGV visualization using EventPointer_IGV

nextflow.enable.dsl = 2

process BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("EventPointer", "aroma.affymetrix", "R.utils")
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
    
    # Load required libraries
    library(EventPointer)
    library(aroma.affymetrix)
    library(R.utils)
    
    # Define user input files
    DONSON_GTF <- "reference_transcriptome.gtf"
    PSRProbes <- "exon_probes.txt"
    JunctionProbes <- "junction_probes.txt"
    array <- "HTA-2_0"
    
    # Define and create the directory structure required by aroma.affymetrix
    Directory <- "annotationData/chipTypes/EP_HTA-2_0"
    dir.create(Directory, recursive = TRUE, showWarnings = FALSE)
    
    # 1. Create a custom CDF file using CDFfromGTF
    CDFfromGTF(input="AffyGTF", inputFile=DONSON_GTF,
               PSR=PSRProbes, Junc=JunctionProbes,
               PathCDF=Directory, microarray=array)
    
    # Rename the generated CDF file to match the chip type and tag expected by aroma.affymetrix
    generated_cdf <- file.path(Directory, "HTA-2_0.cdf")
    target_cdf <- file.path(Directory, "EP_HTA-2_0,r.cdf")
    if (file.exists(generated_cdf)) {
      file.rename(generated_cdf, target_cdf)
    } else {
      stop("CDF generation failed: HTA-2_0.cdf not found.")
    }
    
    # Set up the CEL files in the rawData directory structure
    projectName <- "Experiment"
    celDir <- "rawData/Experiment/EP_HTA-2_0"
    dir.create(celDir, recursive = TRUE, showWarnings = FALSE)
    
    # Copy user's CEL files to the aroma.affymetrix project directory
    cel_files <- list.files(pattern = "\\\\.[cC][eE][lL]\$")
    if (length(cel_files) == 0) {
      stop("No CEL files found in the working directory.")
    }
    
    # Ensure microarray_data.cel is copied if present, along with any other CEL files
    if ("microarray_data.cel" %in% cel_files) {
      file.copy("microarray_data.cel", file.path(celDir, "microarray_data.CEL"), overwrite = TRUE)
    }
    for (f in cel_files) {
      if (f != "microarray_data.cel") {
        file.copy(f, file.path(celDir, f), overwrite = TRUE)
      }
    }
    
    # 2. Preprocess CEL files using the aroma.affymetrix pipeline
    verbose <- Arguments\$getVerbose(-8);
    timestampOn(verbose);
    cdfGFile <- "EP_HTA-2_0,r"
    cdfG <- AffymetrixCdfFile\$byChipType(cdfGFile)
    cs <- AffymetrixCelSet\$byName(projectName, cdf=cdfG)
    bc <- NormExpBackgroundCorrection(cs, method="mle", tag=c("*","r11"));
    csBC <- process(bc,verbose=verbose,ram=20);
    qn <- QuantileNormalization(csBC, typesToUpdate="pm");
    csN <- process(qn,verbose=verbose,ram=20);
    plmEx <- ExonRmaPlm(csN, mergeGroups=FALSE)
    fit(plmEx, verbose=verbose)
    cesEx <- getChipEffectSet(plmEx)
    ExFit <- extractDataFrame(cesEx, addNames = TRUE)
    
    # Define Design and Contrast matrices dynamically based on the number of samples
    n_samples <- length(list.files(celDir, pattern="\\\\.[cC][eE][lL]\$"))
    if (n_samples >= 2) {
      group <- rep(c(0, 1), length.out = n_samples)
      Dmatrix <- model.matrix(~ group)
      Cmatrix <- matrix(c(0, 1), ncol = 1)
    } else {
      Dmatrix <- matrix(1, nrow = n_samples, ncol = 1)
      Cmatrix <- matrix(1, nrow = 1, ncol = 1)
    }
    
    # Locate the EventsFound.txt file generated by CDFfromGTF
    EventsFound <- file.path(Directory, "EventsFound.txt")
    if (!file.exists(EventsFound) && file.exists("EventsFound.txt")) {
      EventsFound <- "EventsFound.txt"
    }
    
    # 3. Run statistical analysis and calculate delta PSI using EventPointer
    Events <- EventPointer(Design=Dmatrix,
                           Contrast=Cmatrix,
                           ExFit=ExFit,
                           Eventstxt=EventsFound,
                           Filter=FALSE,
                           Qn=0.25,
                           Statistic="LogFC",
                           PSI=TRUE)
    
    # 4. Generate GTF files for IGV visualization using EventPointer_IGV
    tryCatch({
      if (nrow(Events) > 0) {
        EventPointer_IGV(Events[1,,drop=FALSE], "AffyGTF", DONSON_GTF, PSRProbes, JunctionProbes, Directory, EventsFound, array)
      } else {
        warning("No alternative splicing events were detected; skipping IGV file generation.")
      }
    }, error = function(e) {
      message("Warning: EventPointer_IGV failed with error: ", e\$message)
    })
    
    # Write meaningful results to output files
    write.csv(Events, "EventPointer_results.csv", row.names = FALSE)
    saveRDS(Events, "EventPointer_results.rds")
    saveRDS(ExFit, "ExFit_preprocessed.rds")
    
    cat("Pipeline completed successfully. Results saved to EventPointer_results.csv, EventPointer_results.rds, and ExFit_preprocessed.rds.\n")

    writeLines(c(
        '"BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE":',
        paste0('    EventPointer: ', as.character(packageVersion('EventPointer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_junction_array_pipeline.csv versions.yml
    """
}

workflow BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exon_probes.txt, junction_probes.txt, reference_transcriptome.gtf, microarray_data.cel ] ]

    main:
    BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE.out.tables
    plots    = BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE.out.plots
    objects  = BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE.out.objects
    versions = BIOC_EVENTPOINTER_JUNCTION_ARRAY_PIPELINE.out.versions
}
