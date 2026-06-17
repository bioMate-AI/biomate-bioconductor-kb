#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clippda — clinical_proteomics_sample_size_planning
// Pre-process raw mass spectrometry peak data with technical replicates, format it with phenotypic covariates into an S4 object, and calculate the required sample
// Input: raw_mass_spec_peaks.csv, phenotypic_data.csv
// Container: quay.io/biocontainers/bioconductor-clippda:1.60.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: clippda
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check the number of replicates per sample using checkNo.replicates
//  * 2. [Core Analysis] Pre-process repeated peak data using preProcRepeatedPeakData to resolve mislabelling and select the most similar replicates
//  * 3. [Core Analysis] Filter out samples with low replicate correlation using spectrumFilter
//  * 4. [Core Analysis] Format the data into a clustered structure using sampleClusteredData
//  * 5. [Core Analysis] Combine expression and phenotypic data into an aclinicalProteomicsData S4 object
//  * 6. [Core Analysis] Extract expression and phenotypic data using proteomicsExprsData and proteomicspData
//  * 7. [Core Analysis] Estimate biological and technical parameters using sampleSizeParameters
//  * 8. [Core Analysis] Calculate the heterogeneity correction factor Z using fisherInformation
//  * 9. [Core Analysis] Compute the required sample sizes using sampleSize
//  * 10. [Visualization & Output] Visualize sample size requirements using sampleSizeContourPlots and sampleSize3DscatterPlots

nextflow.enable.dsl = 2

process BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("clippda")
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
    
    # Load the clippda library
    library(clippda)
    
    # Read user input files from the working directory
    liverRawData <- read.csv("raw_mass_spec_peaks.csv", stringsAsFactors = FALSE)
    liver_pheno <- read.csv("phenotypic_data.csv", stringsAsFactors = FALSE)
    
    # Determine parameters dynamically from the input data
    no.peaks <- length(unique(liverRawData\$Peak))
    no.replicates <- 2
    
    # 1. Check the number of replicates per sample
    checkNo.replicates(liverRawData, no.peaks, no.replicates) 
    
    # 2. Pre-process repeated peak data to resolve mislabelling and select the most similar replicates
    threshold <- 0.80 
    Data <- preProcRepeatedPeakData(liverRawData, no.peaks, no.replicates, threshold)
    
    # 3. Filter out samples with low replicate correlation
    TAGS <- spectrumFilter(Data, threshold, no.peaks)\$SampleTag
    NewRawData2 <- Data[Data\$SampleTag %in% TAGS,]
    
    # 4. Format the data into a clustered structure
    JUNK_DATA <- sampleClusteredData(NewRawData2, no.peaks)
    write.csv(JUNK_DATA, "clustered_data.csv", row.names = TRUE)
    
    # 5. Combine expression and phenotypic data into an aclinicalProteomicsData S4 object
    OBJECT <- new("aclinicalProteomicsData")
    OBJECT@rawSELDIdata <- as.matrix(NewRawData2)
    OBJECT@covariates <- c("tumor", "sex")
    OBJECT@phenotypicData <- as.matrix(liver_pheno)
    OBJECT@variableClass <- c('numeric', 'factor', 'factor')
    OBJECT@no.peaks <- no.peaks
    
    # 6. Extract expression and phenotypic data
    exprs_data <- proteomicsExprsData(OBJECT)
    p_data <- proteomicspData(OBJECT)
    write.csv(exprs_data, "preprocessed_expression_data.csv", row.names = FALSE)
    write.csv(p_data, "preprocessed_phenotypic_data.csv", row.names = FALSE)
    
    # 7. Estimate biological and technical parameters
    intraclasscorr <- 0.60 
    signifcut <- 0.05  
    Data <- OBJECT
    params <- sampleSizeParameters(Data, intraclasscorr, signifcut)
    saveRDS(params, "sample_size_parameters.rds")
    
    # 8. Calculate the heterogeneity correction factor Z
    Z <- as.vector(fisherInformation(Data)[2,2])/2
    
    # 9. Compute the required sample sizes
    sizes <- sampleSize(Data, intraclasscorr, signifcut)
    sizes_df <- as.data.frame(sizes\$sample_size)
    write.csv(sizes_df, "sample_size_calculations.csv", row.names = TRUE)
    
    # 10. Visualize sample size requirements using contour and 3D scatter plots
    m <- 2
    DIFF <- seq(0.1, 0.50, 0.01) 
    VAR <- seq(0.2, 4, 0.1)
    beta <- c(0.90, 0.80, 0.70)
    alpha <- 1 - c(0.001, 0.01, 0.05)/2
    Corr <- c(0.70, 0.90) 
    Z <- 2.4   
    Indicator <- 1 
    observedPara <- c(1, 0.4)
    sampleSizeContourPlots(Z, m, DIFF, VAR, beta, alpha, observedPara, Indicator)
    
    Z <- 2.460018
    m <- 2
    DIFF <- seq(0.1, 0.50, 0.01) 
    VAR <- seq(0.2, 4, 0.1)
    beta <- c(0.90, 0.80, 0.70)
    alpha <- 1 - c(0.001, 0.01, 0.05)/2
    observedDIFF <- 0.4
    observedVAR <- 1.0
    observedSampleSize <- 80
    Indicator <- 1 
    Angle <- 60    
    sampleSize3DscatterPlots(Z, m, DIFF, VAR, beta, alpha, observedDIFF, observedVAR, observedSampleSize, Angle, Indicator)

    writeLines(c(
        '"BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING":',
        paste0('    clippda: ', as.character(packageVersion('clippda')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clinical_proteomics_sample_size_planning.csv versions.yml
    """
}

workflow BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_mass_spec_peaks.csv, phenotypic_data.csv ] ]

    main:
    BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING(ch_input)

    emit:
    tables   = BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING.out.tables
    plots    = BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING.out.plots
    objects  = BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING.out.objects
    versions = BIOC_CLIPPDA_CLINICAL_PROTEOMICS_SAMPLE_SIZE_PLANNING.out.versions
}
