#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bsgenome — variable_length_pattern_search
// Find exact or inexact matches of a set of variable-length nucleotide patterns across both strands of all chromosomes in a genome and write the hits to a tab-del
// Input: ce2dict0.fa
// Container: quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0
// R packages: BSgenome.Celegans.UCSC.ce2, Biostrings, BSgenome, hgu95av2probe
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Celegans.UCSC.ce2", "Biostrings", "BSgenome", "hgu95av2probe")
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
    library(BSgenome)
    library(Biostrings)
    library(BSgenome.Celegans.UCSC.ce2)
    
    # 1. Read the input query patterns from the FASTA file in the working directory
    # (Replacing the demo-data system.file setup with direct file reading)
    ce2dict0_file <- "ce2dict0.fa"
    if (!file.exists(ce2dict0_file)) {
        stop("Required input file 'ce2dict0.fa' not found in the working directory.")
    }
    ce2dict0 <- readDNAStringSet(ce2dict0_file, "fasta")
    
    # 2. Define the documented writeHits function exactly as shown in the vignette
    writeHits <- function(seqname, matches, strand, file="", append=FALSE)
    {
        if (file.exists(file) && !append)
            warning("existing file ", file, " will be overwritten with 'append=FALSE'")
        if (!file.exists(file) && append)
            warning("new file ", file, " will have no header with 'append=TRUE'")
        hits <- data.frame(seqname=rep.int(seqname, length(matches)),
                           start=start(matches),
                           end=end(matches),
                           strand=rep.int(strand, length(matches)),
                           patternID=names(matches),
                           check.names=FALSE)
        write.table(hits, file=file, append=append, quote=FALSE, sep="\t",
                    row.names=FALSE, col.names=!append)
    }
    
    # 3. Define the documented runAnalysis1 function exactly as shown in the vignette
    runAnalysis1 <- function(dict0, outfile="")
    {
        library(BSgenome.Celegans.UCSC.ce2)
        genome <- BSgenome.Celegans.UCSC.ce2
        seqnames <- seqnames(genome)
        seqnames_in1string <- paste(seqnames, collapse=", ")
        cat("Target:", metadata(genome)\$genome,
            "chromosomes", seqnames_in1string, "\n")
        append <- FALSE
        for (seqname in seqnames) {
            subject <- genome[[seqname]]
            cat(">>> Finding all hits in chromosome", seqname, "...\n")
            for (i in seq_len(length(dict0))) {
                patternID <- names(dict0)[i]
                pattern <- dict0[[i]]
                plus_matches <- matchPattern(pattern, subject)
                names(plus_matches) <- rep.int(patternID, length(plus_matches))
                writeHits(seqname, plus_matches, "+", file=outfile, append=append)
                append <- TRUE
                rcpattern <- reverseComplement(pattern)
                minus_matches <- matchPattern(rcpattern, subject)
                names(minus_matches) <- rep.int(patternID, length(minus_matches))
                writeHits(seqname, minus_matches, "-", file=outfile, append=append)
            }
            cat(">>> DONE\n")
        }
    }
    
    # 4. Run the analysis and write hits to the output file
    output_file <- "ce2dict0_ana1.txt"
    runAnalysis1(ce2dict0, outfile=output_file)
    
    # 5. Post-analysis: Read results and generate summary statistics
    if (file.exists(output_file)) {
        hits1 <- read.table(output_file, header=TRUE)
        
        cat("\n--- ANALYSIS SUMMARY ---\n")
        cat("Total hits found:", nrow(hits1), "\n\n")
        
        cat("Hits per chromosome:\n")
        print(table(hits1\$seqname))
        cat("\n")
        
        cat("Hits per pattern:\n")
        print(table(hits1\$patternID))
        cat("\n")
        
        # 6. Define the documented plotGenomeHits function
        plotGenomeHits <- function(bsgenome, seqnames, hits)
        {
            chrlengths <- seqlengths(bsgenome)[seqnames]
            XMAX <- max(chrlengths)
            YMAX <- length(seqnames)
            plot.new()
            plot.window(c(1, XMAX), c(0, YMAX))
            axis(1)
            axis(2, at=seq_len(length(seqnames)), labels=rev(seqnames), tick=FALSE, las=1)
            ## Plot the chromosomes
            for (i in seq_len(length(seqnames)))
                lines(c(1, chrlengths[i]), c(YMAX + 1 - i, YMAX + 1 - i), type="l")
            ## Plot the hits
            for (i in seq_len(nrow(hits))) {
                seqname <- hits\$seqname[i]
                y0 <- YMAX + 1 - match(seqname, seqnames)
                if (hits\$strand[i] == "+") {
                    y <- y0 + 0.05
                    col <- "red"
                } else {
                    y <- y0 - 0.05
                    col <- "blue"
                }
                lines(c(hits\$start[i], hits\$end[i]), c(y, y), type="l", col=col, lwd=3)
            }
        }
        
        # Save the visualization to a PDF file
        pdf_file <- "ce2dict0_hits_plot.pdf"
        pdf(pdf_file, width=10, height=6)
        genome <- BSgenome.Celegans.UCSC.ce2
        plotGenomeHits(genome, seqnames(genome), hits1)
        dev.off()
        cat("Visualization saved to:", pdf_file, "\n")
    } else {
        stop("Output file was not created successfully.")
    }

    writeLines(c(
        '"BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH":',
        paste0('        bsgenome: ', as.character(packageVersion("bsgenome")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variable_length_pattern_search.csv versions.yml
    """
}

workflow BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ce2dict0.fa ] ]

    main:
    BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH(ch_input)

    emit:
    tables   = BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH.out.tables
    plots    = BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH.out.plots
    objects  = BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH.out.objects
    versions = BIOC_BSGENOME_VARIABLE_LENGTH_PATTERN_SEARCH.out.versions
}
