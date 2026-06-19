#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ITALICS — italics_normalization_and_calling
// Normalize Affymetrix GeneChip Human Mapping chips and call DNA copy number alterations using the iterative ITALICS algorithm.
// Input: HF0844_Xba.CEL, Xba.QuartetEffect.csv
// Container: quay.io/biocontainers/bioconductor-italics:2.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ITALICS, affy
// Visualizations: profile plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the CEL file header to identify the chip type and platform
//  * 2. [Input & Preparation] Load the corresponding quartet effect reference data
//  * 3. [Core Analysis] Retrieve SNP and quartet metadata for the platform
//  * 4. [Input & Preparation] Read CEL intensities and calculate quartet log ratios
//  * 5. [Core Analysis] Add quartet effect information and map quartet-level data to SNP-level data
//  * 6. [Core Analysis] Run the iterative ITALICS normalization and copy number calling
//  * 7. [Visualization & Output] Plot the normalized genomic profile

nextflow.enable.dsl = 2

process BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("ITALICS", "affy", "GLAD")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(ITALICS)
    library(affy)
    library(GLAD)
    
    # 1. Read the CEL file header to identify the chip type and platform
    filename <- "HF0844_Xba.CEL"
    headdetails <- readCelHeader(filename[1])
    pkgname <- cleanPlatformName(headdetails[["chiptype"]])
    
    # 2. Load the corresponding quartet effect reference data
    quartetEffectFile <- "Xba.QuartetEffect.csv"
    quartetEffect <- read.table(quartetEffectFile, sep=";", header=TRUE)
    
    # 3. Retrieve SNP and quartet metadata for the platform
    snpInfo <- getSnpInfo(pkgname)
    quartet <- getQuartet(pkgname, snpInfo)
    
    # 4. Read CEL intensities and calculate quartet log ratios
    tmpExprs <- readCelIntensities(filename, indices=quartet\$fid)
    quartet\$quartetInfo\$quartetLogRatio <- readQuartetCopyNb(tmpExprs)
    
    # 5. Add quartet effect information and map quartet-level data to SNP-level data
    quartet\$quartetInfo <- addInfo(quartet, quartetEffect)
    snpInfo <- fromQuartetToSnp(cIntensity="quartetLogRatio",
              quartetInfo=quartet\$quartetInfo, snpInfo=snpInfo)
    
    # 6. Run the iterative ITALICS normalization and copy number calling
    profilSNPXba <- ITALICS(quartet\$quartetInfo, snpInfo,
         formule="Smoothing+QuartetEffect+FL+I(FL^2)+I(FL^3)+GC+I(GC^2)+I(GC^3)")
    
    # Save the resulting profile object and values
    saveRDS(profilSNPXba, file = "profilSNPXba.rds")
    if (!is.null(profilSNPXba\$profileValues)) {
      write.csv(profilSNPXba\$profileValues, file = "profilSNPXba_values.csv", row.names = FALSE)
    }
    
    # Retrieve cytoband data from GLAD namespace without using data()
    my_cytoband <- NULL
    if (exists("cytoband", envir = asNamespace("GLAD"))) {
      my_cytoband <- get("cytoband", envir = asNamespace("GLAD"))
    }
    
    # 7. Plot the normalized genomic profile and save to PDF
    pdf("profile_plot.pdf", width = 11, height = 8.5)
    plotProfile(profilSNPXba, Smoothing="Smoothing", cytoband=my_cytoband)
    dev.off()

    writeLines(c(
        '"BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING":',
        paste0('    ITALICS: ', as.character(packageVersion('ITALICS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_italics_normalization_and_calling.csv versions.yml
    """
}

workflow BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HF0844_Xba.CEL, Xba.QuartetEffect.csv ] ]

    main:
    BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING(ch_input)

    emit:
    tables   = BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING.out.tables
    plots    = BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING.out.plots
    objects  = BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING.out.objects
    versions = BIOC_ITALICS_ITALICS_NORMALIZATION_AND_CALLING.out.versions
}
