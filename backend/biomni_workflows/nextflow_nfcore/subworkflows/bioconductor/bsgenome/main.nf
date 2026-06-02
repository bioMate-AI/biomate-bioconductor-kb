#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BSgenome
// Infrastructure shared by all the Biostrings-based genome data packages.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BSgenome/inst/doc/GenomeSearching.R
// Upstream  : hgu95av2probe
// Downstream: bambu, BSgenomeForge, ChIPanalyser, GOTHiC, HelloRanges
//
// Install: BiocManager::install("BSgenome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSGENOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bsgenome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bsgenome:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bsgenome:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(bsgenome)

    output:
    tuple val(meta), path("${meta.id}_bsgenome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bsgenome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bsgenome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSgenome)
    library(jsonlite)


    # --- B1 [] ---
    # Key functions: class, metadata, seqnames, seqinfo, alphabetFrequency
    library(BSgenome.Celegans.UCSC.ce2)
    ls("package:BSgenome.Celegans.UCSC.ce2")
    genome <- BSgenome.Celegans.UCSC.ce2
    genome
    class(genome)
    metadata(genome)
    seqnames(genome)
    seqinfo(genome)
    genome$chrI
    chrI <- genome$chrI
    length(chrI)
    afI <- alphabetFrequency(chrI)
    afI
    sum(afI) == length(chrI)

    # --- B7 [] ---
    # Key functions: countPattern, matchPattern, class, mismatch, DNAString
    p1 <- "ACCCAGGGC"
    countPattern(p1, chrI)
    countPattern(p1, chrI, max.mismatch=1)
    m1 <- matchPattern(p1, chrI, max.mismatch=1)
    m1[4:6]
    class(m1)
    mismatch(p1, m1[4:6])
    p2 <- DNAString("AAGCCTAAGCCTAAGCCTAA")
    m2 <- matchPattern(p2, chrI, max.mismatch=2)
    m2[1:4]
    p2 == m2[1:4]
    mismatch(p2, m2[1:4])
    m2[p2 == m2]
    m2[p2 != m2]

    # --- C1 [] ---
    # Key functions: readDNAStringSet, extdata, ce2dict0.fa, fasta, function, file.exists, rep.int, start
    ce2dict0_file <- system.file("extdata", "ce2dict0.fa", package="BSgenome")
    ce2dict0 <- readDNAStringSet(ce2dict0_file, "fasta")
    ce2dict0
    writeHits <- function(seqname, matches, strand, file="", append=FALSE)
    # --- C7 [] ---
    # Key functions: pattern, function, seqlengths, plot.new, plot.window, axis, for, match
    hits1_table[hits1_table == max(hits1_table)] # pattern(s) with more hits
    setdiff(names(ce2dict0), hits1$patternID) # pattern(s) with no hits
    plotGenomeHits <- function(bsgenome, seqnames, hits)
    # --- F3 [] ---
    # Key functions: active, masks, alphabetFrequency, unmasked, gaps, width
    active(masks(chrY)) <- FALSE
    active(masks(chrY))["AGAPS"] <- TRUE
    alphabetFrequency(unmasked(chrY))
    alphabetFrequency(chrY)
    as(chrY, "XStringViews")
    gaps(as(chrY, "XStringViews"))
    width(gaps(as(chrY, "XStringViews")))
    gaps(chrY)
    alphabetFrequency(gaps(chrY))
    af0 <- alphabetFrequency(unmasked(chrY))
    af1 <- alphabetFrequency(chrY)
    af2 <- alphabetFrequency(gaps(chrY))
    all(af0 == af1 + af2)

    # --- F9 [] ---
    # Key functions: active, masks, alphabetFrequency, gaps, countPattern, function, metadata, reverseComplement
    active(masks(chrY)) <- TRUE
    af1 <- alphabetFrequency(chrY)
    af1
    gaps(chrY)
    af2 <- alphabetFrequency(gaps(chrY))
    af2
    all(af0 == af1 + af2)
    Ebox <- "CANNTG"
    active(masks(chrY)) <- FALSE
    countPattern(Ebox, chrY, fixed=FALSE)
    countPattern(Ebox, chrY, fixed=c(pattern=FALSE,subject=TRUE))
    active(masks(chrY))[c("AGAPS", "AMB")] <- TRUE
    alphabetFrequency(chrY, baseOnly=TRUE)  # no ambiguities
    countPattern(Ebox, chrY, fixed=FALSE)
    chr2 <- genome$chr2
    active(masks(chr2))[-2] <- FALSE
    alphabetFrequency(gaps(chr2))
    runOneStrandAnalysis <- function(dict0, bsgenome, seqnames, strand,
                                     outfile="", append=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bsgenome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bsgenome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bsgenome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BSGENOME:", paste0("    bsgenome: ", packageVersion("BSgenome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsgenome_results.csv
    touch ${prefix}_bsgenome_output.rds
    echo "BIOC_BSGENOME:" > versions.yml
    echo "    bsgenome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BSGENOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(bsgenome) ]

    main:
    BIOC_BSGENOME(ch_input)

    emit:
    results  = BIOC_BSGENOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BSGENOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BSGENOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BSGENOME.out.versions  // channel: path(versions.yml)
}
