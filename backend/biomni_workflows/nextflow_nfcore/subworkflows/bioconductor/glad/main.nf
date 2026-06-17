#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GLAD — glad_analysis
// Detect genomic breakpoints and assign copy number status using the classic GLAD algorithm.
// Input: user_data.txt
// Container: quay.io/biocontainers/bioconductor-glad:2.74.0--r45h1ca3914_0
// R packages: GLAD
// Bioconductor: 3.20 | R: 4.4
// Requires: GLAD
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert data to a profileCGH object
//  * 2. [Core Analysis] Run the glad segmentation and calling algorithm
//  * 3. [Visualization & Output] Plot the genomic profile with cytoband information

nextflow.enable.dsl = 2

process BIOC_GLAD_GLAD_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("GLAD")
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
    
    # Load required library
    library(GLAD)
    
    # 1. Read the user input file
    # The file must contain LogRatio, Chromosome, PosOrder, and optionally PosBase and Clone
    user_data <- read.table("user_data.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Convert the input data frame to a profileCGH object
    profileCGH <- as.profileCGH(user_data)
    
    # 2. Run the glad segmentation and calling algorithm
    res <- glad(profileCGH, mediancenter=FALSE,
                smoothfunc="lawsglad", bandwidth=10, round=1.5,
                model="Gaussian", lkern="Exponential", qlambda=0.999,
                base=FALSE,
                lambdabreak=8, lambdacluster=8, lambdaclusterGen=40,
                type="tricubic", param=c(d=6),
                alpha=0.001, msize=2,
                method="centroid", nmax=8,
                verbose=FALSE)
    
    # Retrieve the cytoband reference data from the package namespace (avoiding data() call)
    cytoband <- get("cytoband", envir = asNamespace("GLAD"))
    
    # 3. Plot the genomic profile with cytoband information and save to PDF
    pdf("genomic_profile.pdf", width = 12, height = 8)
    plotProfile(res, unit=3, Bkp=TRUE, labels=FALSE, plotband=FALSE, Smoothing="Smoothing", cytoband = cytoband)
    dev.off()
    
    # 4. Write named output files for the results
    # Save the profile values containing segmentation and status assignments
    write.csv(res\$profileValues, "glad_results.csv", row.names = FALSE)
    
    # Save the complete profileCGH object as an RDS file
    saveRDS(res, "glad_results.rds")

    writeLines(c(
        '"BIOC_GLAD_GLAD_ANALYSIS":',
        paste0('    GLAD: ', as.character(packageVersion('GLAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glad_analysis.csv versions.yml
    """
}

workflow BIOC_GLAD_GLAD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.txt ] ]

    main:
    BIOC_GLAD_GLAD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GLAD_GLAD_ANALYSIS.out.tables
    plots    = BIOC_GLAD_GLAD_ANALYSIS.out.plots
    objects  = BIOC_GLAD_GLAD_ANALYSIS.out.objects
    versions = BIOC_GLAD_GLAD_ANALYSIS.out.versions
}
