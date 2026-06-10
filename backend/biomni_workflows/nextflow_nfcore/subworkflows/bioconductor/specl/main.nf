#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: specl — generate_swath_spectral_library
// Generate a non-redundant, retention-time-normalized SWATH/DIA spectral library from BiblioSpec SQLite files and a FASTA database, and export it to a Spectronaut
// Input: BLIB_FILTERED_FILE.sqlite, BLIB_REDUNDANT_FILE.sqlite, FASTA_FILE.fasta.gz
// Container: quay.io/biocontainers/bioconductor-specl:1.44.0--r45hdfd78af_0
// R packages: BiocStyle, knitr, rmarkdown, seqinr, specL
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-specl:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocStyle", "knitr", "rmarkdown", "seqinr", "specL")
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
    
    # Define input parameters matching the documented code structure
    # Reading exactly the user-specified files from the working directory
    INPUT <- list(
      BLIB_FILTERED_FILE = "BLIB_FILTERED_FILE.sqlite",
      BLIB_REDUNDANT_FILE = "BLIB_REDUNDANT_FILE.sqlite",
      FASTA_FILE = "FASTA_FILE.fasta.gz",
      ANNOTATE = TRUE,
      MZ_ERROR = 0.05,
      MAX_IONS = 6,
      FRAGMENTIONMZRANGE = c(300, 1250),
      FRAGMENTIONRANGE = c(5, 200),
      MASCOTSCORECUTOFF = 17,
      NORMRTPEPTIDES = specL::iRTpeptides,
      OUTPUT_LIBRARY_FILE = "specLibrary_spectronaut.csv",
      RDATA_LIBRARY_FILE = "specLibrary.RData"
    )
    
    # 1. Read the filtered and redundant BiblioSpec SQLite files
    message("Reading BiblioSpec SQLite files...")
    BLIB_FILTERED <- read.bibliospec(INPUT\$BLIB_FILTERED_FILE) 
    BLIB_REDUNDANT <- read.bibliospec(INPUT\$BLIB_REDUNDANT_FILE) 
    
    # 2. Read the FASTA file and 3. Annotate protein IDs to the filtered PSMs
    if(INPUT\$ANNOTATE){
      message("Reading FASTA database and annotating protein IDs...")
      FASTA <- read.fasta(INPUT\$FASTA_FILE, 
                          seqtype = "AA", 
                          as.string = TRUE)
    
      BLIB_FILTERED <- annotate.protein_id(BLIB_FILTERED, 
                                           fasta = FASTA)
    }
    
    # 4. Define the fragment ion function
    fragmentIonFunction_specL <- function (b, y) {
      Hydrogen <- 1.007825
      Oxygen <- 15.994915
      Nitrogen <- 14.003074
      b1_ <- (b )
      y1_ <- (y )
      b2_ <- (b + Hydrogen) / 2
      y2_ <- (y + Hydrogen) / 2 
      return( cbind(b1_, y1_, b2_, y2_) )
    }
    
    # 5. Generate the SWATH ion library
    message("Generating SWATH ion library...")
    specLibrary <- specL::genSwathIonLib(
      data = BLIB_FILTERED,
      data.fit = BLIB_REDUNDANT,
      max.mZ.Da.error = INPUT\$MZ_ERROR,
      topN = INPUT\$MAX_IONS,
      fragmentIonMzRange = INPUT\$FRAGMENTIONMZRANGE,
      fragmentIonRange = INPUT\$FRAGMENTIONRANGE,
      fragmentIonFUN = fragmentIonFunction_specL,
      mascotIonScoreCutOFF = INPUT\$MASCOTSCORECUTOFF,
      iRT = INPUT\$NORMRTPEPTIDES
    )
    
    # 6. Summarize and plot the generated library
    message("Writing summary and generating plots...")
    # Save summary to a text file
    sink("specLibrary_summary.txt")
    summary(specLibrary)
    sink()
    
    # Save plots to a PDF file
    pdf("specLibrary_plots.pdf", width = 11, height = 8.5)
    # Plot the overall library
    plot(specLibrary)
    # Plot the first individual ion library entry if available
    if (length(specLibrary@ionlibrary) > 0) {
      plot(specLibrary@ionlibrary[[1]])
    }
    dev.off()
    
    # 7. Export the library to a Spectronaut-compatible text file and save RData
    message("Exporting spectral library...")
    write.spectronaut(specLibrary, file = INPUT\$OUTPUT_LIBRARY_FILE)
    save(specLibrary, file = INPUT\$RDATA_LIBRARY_FILE)
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY":
        specl: \$(Rscript -e 'cat(as.character(packageVersion("specl")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generate_swath_spectral_library.csv versions.yml
    """
}

workflow BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BLIB_FILTERED_FILE.sqlite, BLIB_REDUNDANT_FILE.sqlite, FASTA_FILE.fasta.gz ] ]

    main:
    BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY(ch_input)

    emit:
    tables   = BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY.out.tables
    plots    = BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY.out.plots
    objects  = BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY.out.objects
    versions = BIOC_SPECL_GENERATE_SWATH_SPECTRAL_LIBRARY.out.versions
}
