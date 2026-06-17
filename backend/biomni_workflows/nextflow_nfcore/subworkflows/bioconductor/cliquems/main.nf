#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cliquems — lcms_feature_annotation
// Group coeluting LC/MS features into cliques, annotate isotopes, and identify adducts/fragments to obtain neutral metabolite masses.
// Input: standards.mzXML
// Container: quay.io/biocontainers/bioconductor-cliquems:1.24.0--r45ha27e39d_0
// R packages: cliqueMS, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cliquems:1.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("cliqueMS", "xcms")
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
    
    # Check for required input file
    if (!file.exists("standards.mzXML")) {
      stop("Required input file 'standards.mzXML' not found in the working directory.")
    }
    
    # Load required libraries
    library(cliqueMS)
    library(xcms)
    
    # --- Read and process raw LC/MS data using xcms to find ---
    mzfile <- "standards.mzXML"
    mzraw <- MSnbase::readMSData(files = mzfile, mode = "onDisk")
    cpw <- CentWaveParam(ppm = 15, peakwidth = c(5, 20), snthresh = 10)
    mzData <- findChromPeaks(object = mzraw, param = cpw)
    
    # --- Create an anClique S4 object from the processed peak data ---
    ex.anClique <- createanClique(mzData)
    
    # --- Group coeluting features into cliques using getCliques ---
    set.seed(2)
    ex.cliqueGroups <- getCliques(mzData, filter = TRUE)
    
    # --- Annotate isotopes within each clique group using ---
    ex.Isotopes <- getIsotopes(ex.cliqueGroups, ppm = 10)
    
    # --- Annotate adducts and fragments using getAnnotation with ---
    # Retrieve the package's adduct datasets directly without using the forbidden data() function
    positive.adinfo <- cliqueMS::positive.adinfo
    negative.adinfo <- cliqueMS::negative.adinfo
    
    ex.Adducts <- getAnnotation(ex.Isotopes, ppm = 10,
        adinfo = positive.adinfo, polarity = "positive",
        normalizeScore = TRUE)
    
    # --- Extract the annotated peak list and clique groups ---
    features.clique6 <- getlistofCliques(ex.Adducts)[[6]]
    
    # Extract subset of interest for demonstration/verification
    clique6_subset <- getPeaklistanClique(ex.Adducts)[features.clique6,
        c("an1", "mass1", "an2", "mass2", "an3", "mass3", "an4", "mass4", "an5", "mass5")]
    
    # Write meaningful results to output files
    write.csv(getPeaklistanClique(ex.Adducts), "annotated_peaklist.csv", row.names = TRUE)
    write.csv(clique6_subset, "clique6_annotated_subset.csv", row.names = TRUE)
    saveRDS(ex.Adducts, "cliqueMS_annotated.rds")

    writeLines(c(
        '"BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION":',
        paste0('        cliquems: ', as.character(packageVersion("cliquems")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lcms_feature_annotation.csv versions.yml
    """
}

workflow BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ standards.mzXML ] ]

    main:
    BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION.out.tables
    plots    = BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION.out.plots
    objects  = BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION.out.objects
    versions = BIOC_CLIQUEMS_LCMS_FEATURE_ANNOTATION.out.versions
}
