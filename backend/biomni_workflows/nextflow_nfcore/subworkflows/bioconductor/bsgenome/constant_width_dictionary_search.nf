#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bsgenome — constant_width_dictionary_search
// Efficiently find exact matches for a dictionary of constant-width nucleotide patterns across both strands of all chromosomes using matchPDict.
// Input: ce2dict0.fa
// Container: quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH {
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
    .bm_deps <- c("BSgenome", "BSgenome.Celegans.UCSC.ce2", "Biostrings")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(Biostrings)
    library(BSgenome)
    library(BSgenome.Celegans.UCSC.ce2)
    
    # 1. Read the input query patterns from the working directory
    ce2dict0 <- readDNAStringSet("ce2dict0.fa", "fasta")
    
    # 2. Define the writeHits function exactly as documented
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
    
    # 3. Define the runOneStrandAnalysis function exactly as documented
    runOneStrandAnalysis <- function(dict0, bsgenome, seqnames, strand,
                                     outfile="", append=FALSE)
    {
        cat("\nTarget: strand", strand, "of", metadata(bsgenome)\$genome,
            "chromosomes", paste(seqnames, collapse=", "), "\n")
        if (strand == "-")
            dict0 <- reverseComplement(dict0)
        pdict <- PDict(dict0)
        for (seqname in seqnames) {
            subject <- bsgenome[[seqname]]
            cat(">>> Finding all hits in strand", strand, "of chromosome", seqname, "...\n")
            mindex <- matchPDict(pdict, subject)
            matches <- extractAllMatches(subject, mindex)
            writeHits(seqname, matches, strand, file=outfile, append=append)
            append <- TRUE
            cat(">>> DONE\n")
        }
    }
    
    # 4. Define the runAnalysis2 function exactly as documented
    runAnalysis2 <- function(dict0, outfile="")
    {
        library(BSgenome.Celegans.UCSC.ce2)
        genome <- BSgenome.Celegans.UCSC.ce2
        seqnames <- seqnames(genome)
        runOneStrandAnalysis(dict0, genome, seqnames, "+", outfile=outfile, append=FALSE)
        runOneStrandAnalysis(dict0, genome, seqnames, "-", outfile=outfile, append=TRUE)
    }
    
    # 5. Truncate the patterns to a constant width of 15
    ce2dict0cw15 <- DNAStringSet(ce2dict0, end=15)
    
    # 6. Run the analysis
    runAnalysis2(ce2dict0cw15, outfile="ce2dict0cw15_ana2.txt")
    
    # 7. Export additional meaningful outputs
    if (file.exists("ce2dict0cw15_ana2.txt")) {
        hits <- read.table("ce2dict0cw15_ana2.txt", header=TRUE, sep="\t")
        write.csv(hits, "ce2dict0cw15_ana2_summary.csv", row.names=FALSE)
        saveRDS(hits, "ce2dict0cw15_ana2.rds")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH":
        bsgenome: \$(Rscript -e 'cat(as.character(packageVersion("bsgenome")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_constant_width_dictionary_search.csv versions.yml
    """
}

workflow BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ce2dict0.fa ] ]

    main:
    BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH(ch_input)

    emit:
    tables   = BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH.out.tables
    plots    = BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH.out.plots
    objects  = BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH.out.objects
    versions = BIOC_BSGENOME_CONSTANT_WIDTH_DICTIONARY_SEARCH.out.versions
}
