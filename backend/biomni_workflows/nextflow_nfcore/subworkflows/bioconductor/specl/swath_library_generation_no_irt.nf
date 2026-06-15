#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: specL — swath_library_generation_no_irt
// Generate a SWATH/DIA spectral library using original experimental retention times when iRT standard peptides are not present.
// Input: peptideStd.sqlite, SP201602-specL.fasta.gz
// Container: quay.io/biocontainers/bioconductor-specl:1.44.0--r45hdfd78af_0
// R packages: seqinr, specL
// Bioconductor: 3.20 | R: 4.4
// Requires: seqinr, specL
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the non-redundant BiblioSpec sqlite file
//  * 2. [Visualization & Output] Load the FASTA database
//  * 3. [Visualization & Output] Generate the SWATH ion library without providing
//  * 4. [Visualization & Output] Export the library to a Spectronaut-compatible text file

nextflow.enable.dsl = 2

process BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("seqinr", "specL")
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
    library(specL)
    library(seqinr)
    
    # Define input files as specified by the user
    blib_file <- "peptideStd.sqlite"
    fasta_file <- "SP201602-specL.fasta.gz"
    
    # Verify input files exist in the working directory
    if (!file.exists(blib_file)) {
      stop(paste("Required input file missing:", blib_file))
    }
    if (!file.exists(fasta_file)) {
      stop(paste("Required input file missing:", fasta_file))
    }
    
    # --- Read the non-redundant BiblioSpec sqlite file ---
    BLIB_FILTERED <- read.bibliospec(blib_file)
    
    # --- Load the FASTA database ---
    FASTA <- read.fasta(fasta_file, 
                        seqtype = "AA", 
                        as.string = TRUE)
    
    # Re-annotate protein IDs to the PSM set
    BLIB_FILTERED <- annotate.protein_id(BLIB_FILTERED, 
                                         fasta = FASTA)
    
    # --- Generate the SWATH ion library without providing ---
    res.genSwathIonLib.no_iRT <- genSwathIonLib(BLIB_FILTERED)
    
    # --- Export the library to a Spectronaut-compatible text file ---
    write.spectronaut(res.genSwathIonLib.no_iRT, file="specL-Spectronaut.txt")
    
    # Save additional meaningful results (RDS object and PDF plots)
    saveRDS(res.genSwathIonLib.no_iRT, file="specL_no_iRT_library.rds")
    
    # Generate and save diagnostic plots to a PDF file
    pdf("specL_no_iRT_plots.pdf", width=10, height=7)
    op <- par(mfrow = c(2, 3))
    plot(res.genSwathIonLib.no_iRT)
    par(op)
    dev.off()
    
    # Print summary to console
    cat("\n--- SWATH Ion Library Generation Summary (No iRT) ---\n")
    print(summary(res.genSwathIonLib.no_iRT))

    writeLines(c(
        '"BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT":',
        paste0('    specL: ', as.character(packageVersion('specL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_swath_library_generation_no_irt.csv versions.yml
    """
}

workflow BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptideStd.sqlite, SP201602-specL.fasta.gz ] ]

    main:
    BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT(ch_input)

    emit:
    tables   = BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT.out.tables
    plots    = BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT.out.plots
    objects  = BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT.out.objects
    versions = BIOC_SPECL_SWATH_LIBRARY_GENERATION_NO_IRT.out.versions
}
