#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regionReport — general_region_report
// Generate an HTML or PDF report to explore a general set of genomic regions stored as a GRanges object.
// Input: regions
// Container: quay.io/biocontainers/bioconductor-regionreport:1.44.0--r45hdfd78af_0
// R packages: GenomeInfoDb, bumphunter, derfinder, GenomicRanges, refmanager, regionReport, sessioninfo
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, GenomicRanges, regionReport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load regionReport and GenomicRanges
//  * 2. [Core Analysis] Assign chromosome lengths to the GRanges object
//  * 3. [Visualization & Output] Run renderReport() to compile the HTML report

nextflow.enable.dsl = 2

process BIOC_REGIONREPORT_GENERAL_REGION_REPORT {
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
    .bm_deps <- c("GenomeInfoDb", "bumphunter", "derfinder", "GenomicRanges", "refmanager", "regionReport", "sessioninfo")
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
        
        # 1. Load required libraries
        library("regionReport")
        library("GenomicRanges")
        library("GenomeInfoDb")
        
        # 2. Read the user input file from the working directory
        # The pipeline expects a GRanges object stored as 'regions.rds'
        input_file <- "regions.rds"
        if (!file.exists(input_file)) {
            stop(paste("Required input file", input_file, "not found in the working directory."))
        }
        
        regions <- readRDS(input_file)
        
        # Ensure the input is indeed a GRanges object
        if (!inherits(regions, "GRanges")) {
            stop("The input file does not contain a valid GRanges object.")
        }
        
        # 3. Assign chromosome lengths to the GRanges object
        # We attempt to retrieve chromosome lengths from UCSC based on the genome specified in the GRanges object.
        # A tryCatch block is used to handle offline environments or custom genomes gracefully.
        genome_assembly <- unique(unname(genome(regions)))
        genome_assembly <- genome_assembly[!is.na(genome_assembly) & genome_assembly != "unspecified"]
        
        if (length(genome_assembly) == 1) {
            tryCatch({
                seqlengths(regions) <- seqlengths(
                    getChromInfoFromUCSC(genome_assembly, as.Seqinfo = TRUE)
                )[names(seqlengths(regions))]
            }, error = function(e) {
                warning("Could not assign ", genome_assembly, " chromosome lengths from UCSC. Proceeding with existing seqlengths: ", e\$message)
            })
        } else {
            warning("No single valid genome assembly specified in the GRanges object. Skipping UCSC chromosome length retrieval.")
        }
        
        # Create the output directory if it doesn't exist
        dir.create("renderReport-example", showWarnings = FALSE, recursive = TRUE)
        
        # 4. Run renderReport() to compile the HTML report
        # Dynamically determine metadata columns for the report to handle different naming conventions
        mcols_df <- as.data.frame(mcols(regions))
        if (ncol(mcols_df) > 0) {
            num_cols <- names(mcols_df)[vapply(mcols_df, is.numeric, FUN.VALUE = logical(1))]
        } else {
            num_cols <- character(0)
        }
        
        pvalueVars <- num_cols[grepl("p.*val|q.*val|fdr|padj", num_cols, ignore.case = TRUE)]
        if (length(pvalueVars) > 0) {
            names(pvalueVars) <- pvalueVars
        } else {
            pvalueVars <- NULL
        }
        
        densityVars <- num_cols[!num_cols %in% pvalueVars]
        if (length(densityVars) > 0) {
            names(densityVars) <- densityVars
        } else {
            densityVars <- NULL
        }
        
        if (length(pvalueVars) > 0) {
            significantVar <- mcols(regions)[[pvalueVars[1]]] <= 0.05
        } else {
            significantVar <- NULL
        }
    
        report <- renderReport(regions, "Example run",
            pvalueVars = pvalueVars, 
            densityVars = densityVars,
            significantVar = significantVar, 
            nBestRegions = 20,
            outdir = "renderReport-example"
        )
        
        # 5. Write named output files for the meaningful results
        # Save the path/metadata of the generated report
        saveRDS(report, file = "report_metadata.rds")
        
        # Export the analyzed regions with their metadata as a CSV table for downstream use
        write.csv(as.data.frame(regions), file = "analyzed_regions.csv", row.names = FALSE)
        
        cat("Pipeline completed successfully. Report generated in 'renderReport-example/'.\n")

    writeLines(c(
        '"BIOC_REGIONREPORT_GENERAL_REGION_REPORT":',
        paste0('    regionReport: ', as.character(packageVersion('regionReport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_general_region_report.csv versions.yml
    """
}

workflow BIOC_REGIONREPORT_GENERAL_REGION_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ regions ] ]

    main:
    BIOC_REGIONREPORT_GENERAL_REGION_REPORT(ch_input)

    emit:
    tables   = BIOC_REGIONREPORT_GENERAL_REGION_REPORT.out.tables
    plots    = BIOC_REGIONREPORT_GENERAL_REGION_REPORT.out.plots
    objects  = BIOC_REGIONREPORT_GENERAL_REGION_REPORT.out.objects
    versions = BIOC_REGIONREPORT_GENERAL_REGION_REPORT.out.versions
}
