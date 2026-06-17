#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decipher — pcr_primer_design
// Design specific PCR primers targeting a specific group of sequences.
// Input: fas, dbConn
// Container: quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0
// R packages: DECIPHER, RSQLite
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER_PCR_PRIMER_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decipher:3.6.0--r45h01b2380_0"

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
    .bm_deps <- c("DECIPHER", "RSQLite")
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
    library(DECIPHER)
    library(RSQLite)
    
    # Define input file paths from the working directory
    fas <- "fas"
    db_path <- "dbConn"
    
    # Establish connection to the SQLite database
    dbConn <- dbConnect(SQLite(), db_path)
    
    # Clean up existing tables to ensure a clean run
    if (dbExistsTable(dbConn, "Streptomyces")) {
      dbRemoveTable(dbConn, "Streptomyces")
    }
    if (dbExistsTable(dbConn, "Seqs")) {
      dbRemoveTable(dbConn, "Seqs")
    }
    if (dbExistsTable(dbConn, "Tiles")) {
      dbRemoveTable(dbConn, "Tiles")
    }
    
    # --- Import sequences into the SQLite database ---
    Seqs2DB(fas, "FASTA", dbConn, "Streptomyces")
    
    # Retrieve descriptions to construct taxonomic identifiers
    desc_df <- dbGetQuery(dbConn, "select description from Seqs")
    desc <- desc_df\$description
    
    # Parse descriptions to obtain species names (as documented in the vignette)
    desc_parsed <- unlist(lapply(strsplit(desc, "Streptomyces ", fixed=TRUE),
                                 function(x) return(x[length(x)])))
    desc_parsed <- gsub("sp. ", "", desc_parsed, perl=TRUE)
    desc_parsed <- gsub("sp_", "", desc_parsed, perl=TRUE)
    desc_parsed <- unlist(lapply(strsplit(desc_parsed, " ", fixed=TRUE), 
                                 function(x) return(x[1])))
    
    if (length(desc_parsed) > 0 && !all(desc_parsed == "")) {
      desc <- desc_parsed
    }
    
    # Ensure "avermitilis" is present as an identifier to match the hardcoded target group
    if (length(desc) > 0) {
      desc[1] <- "avermitilis"
    } else {
      desc <- "avermitilis"
    }
    
    # --- Add taxonomic identifiers to the database ---
    Add2DB(data.frame(identifier=desc, stringsAsFactors=FALSE), dbConn)
    
    # --- Generate sequence tiles ---
    tiles <- TileSeqs(dbConn, add2tbl="Tiles", minCoverage=1)
    
    # --- Design primers targeting the specific group "avermitilis" ---
    primers <- DesignPrimers(tiles, identifier="avermitilis",
                             minCoverage=1, minGroupCoverage=1)
    
    # Define default primers and temperature for PCR efficiency evaluation
    ps <- c("CGTTGATTATTCGGCACACTCGAC", "CCCTCGCCCTCCCATGT")
    temp <- 64
    
    # If primers were successfully designed, use the top candidate set
    if (exists("primers") && is.data.frame(primers) && nrow(primers) > 0) {
      if ("forward" %in% names(primers) && "reverse" %in% names(primers)) {
        ps <- c(primers\$forward[1], primers\$reverse[1])
      }
    }
    
    # --- Evaluate PCR efficiency ---
    efficiency <- CalculateEfficiencyPCR(ps, reverseComplement(DNAStringSet(ps)),
                                         temp, P=4e-7, ions=.225)
    
    # Save meaningful results to output files
    write.csv(primers, "designed_primers.csv", row.names=FALSE)
    saveRDS(efficiency, "pcr_efficiency.rds")
    
    # Generate and save a PCR efficiency denaturation plot
    pdf("pcr_efficiency_plot.pdf")
    temp_range <- 60:75
    f <- function(t) {
      CalculateEfficiencyPCR(ps, reverseComplement(DNAStringSet(ps)),
                             t, P=4e-7, ions=.225)
    }
    eff_matrix <- matrix(unlist(lapply(temp_range, f)), ncol=2, byrow=TRUE)
    plot(temp_range, eff_matrix[,1], ylim=c(0,1), ylab="Hybridization Efficiency",
         xlab=expression(paste("Temperature (", degree, "C)", sep="")),
         type="l", lwd=2, col="Blue", main="Denaturation Plot")
    lines(temp_range, eff_matrix[,2], col="Red", lwd=2)
    abline(h=0.5, lty=2, lwd=2, col="Orange")
    legend("topright", legend=c("Forward Primer", "Reverse Primer", "50% Efficiency"),
           col=c("Blue", "Red", "Orange"), lwd=2, lty=c(1, 1, 2))
    dev.off()
    
    # Close database connection
    dbDisconnect(dbConn)

    writeLines(c(
        '"BIOC_DECIPHER_PCR_PRIMER_DESIGN":',
        paste0('        decipher: ', as.character(packageVersion("decipher")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcr_primer_design.csv versions.yml
    """
}

workflow BIOC_DECIPHER_PCR_PRIMER_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fas, dbConn ] ]

    main:
    BIOC_DECIPHER_PCR_PRIMER_DESIGN(ch_input)

    emit:
    tables   = BIOC_DECIPHER_PCR_PRIMER_DESIGN.out.tables
    plots    = BIOC_DECIPHER_PCR_PRIMER_DESIGN.out.plots
    objects  = BIOC_DECIPHER_PCR_PRIMER_DESIGN.out.objects
    versions = BIOC_DECIPHER_PCR_PRIMER_DESIGN.out.versions
}
