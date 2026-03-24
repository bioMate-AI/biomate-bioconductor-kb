#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DECIPHER
// A toolset for deciphering and managing biological sequences.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DECIPHER/inst/doc/ArtOfAlignmentInR.R
// Upstream  : none
// Downstream: AssessORF, sangeranalyseR, SynExtend
//
// Install: BiocManager::install("DECIPHER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECIPHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-decipher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-decipher:3.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-decipher:3.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_decipher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_decipher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_decipher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AdjustAlignment)
    library(AlignDB)
    library(AlignProfiles)
    library(AlignSeqs)
    library(AlignSynteny)
    library(AlignTranslation)
    library(BrowseDB)
    library(BrowseSeqs)
    library(FindSynteny)
    library(RNAStringSet)
    library(jsonlite)

    # --- Expr0 [] ---
    # Key functions: setNames
    library(DECIPHER)
    N0 <- ceiling(2^seq(1, 17))
    N1 <- ceiling(2^seq(1, 12))
    N2 <- ceiling(2^seq(1, 13))
    N3 <- ceiling(2^seq(1, 16))
    # --- Expr1 [] ---
    # Key functions: readDNAStringSet
    library(DECIPHER)
    # specify the path to your sequence file:
    fas <- "<<path to FASTA file>>"
    # OR find the example sequence file used in this tutorial:
    fas <- system.file("extdata", "50S_ribosomal_protein_L2.fas", package="DECIPHER")
    # --- Expr2 [] ---
    # Key functions: AlignTranslation, BrowseSeqs, AlignSeqs, writeXStringSet
    ## AA <- AlignTranslation(dna, type="AAStringSet") # align the translation
    ## BrowseSeqs(AA, highlight=1) # view the alignment
    ##
    ## DNA <- AlignSeqs(dna) # align the sequences directly without translation
    ## DNA <- AlignTranslation(dna) # align the translation then reverse translate
    # --- Expr3 [] ---
    # Key functions: getGeneticCode, AlignTranslation
    ## # using a mixture of standard and non-standard genetic codes
    ## gC1 <- getGeneticCode(id_or_name2="1", full.search=FALSE, as.data.frame=FALSE)
    ## # Mollicutes use an alternative genetic code
    ## gC2 <- getGeneticCode(id_or_name2="4", full.search=FALSE, as.data.frame=FALSE)
    ## w <- grep("Mycoplasma|Ureaplasma", names(dna))
    # --- Expr4 [] ---
    # Key functions: AlignSeqs
    ## u_dna <- unique(dna) # the unique input sequences
    ## index <- match(dna, u_dna) # de-replication index
    ##
    ## U_DNA <- AlignSeqs(u_dna) # align the sequences directly without translation
    ## DNA <- U_DNA[index]
    # --- Expr5 [] ---
    # Key functions: readDNAStringSet, RemoveGaps, RNAStringSet, readRNAStringSet, AlignSeqs
    ## # database containing 16S ribosomal RNA sequences
    ## fas <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")
    ## dna <- readDNAStringSet(fas)
    ## rna <- RemoveGaps(RNAStringSet(dna))
    ## # or if starting with DNA sequences, convert to RNA with:
    # --- Expr6 [] ---
    # Key functions: AlignTranslation, AlignProfiles
    ## half <- floor(length(dna)/2)
    ## dna1 <- dna[1:half] # first half
    ## dna2 <- dna[(half + 1):length(dna)] # second half
    ##
    ## AA1 <- AlignTranslation(dna1, type="AAStringSet")
    # --- Expr7 [] ---
    # Key functions: dbConnect, dbDriver, Seqs2DB, AlignDB, SearchDB, BrowseDB, dbDisconnect
    ## # Align DNA sequences stored in separate tables:
    ## dbConn <- dbConnect(dbDriver("SQLite"), ":memory:")
    ## Seqs2DB(AA1, "DNAStringSet", dbConn, "AA1", tblName="AA1")
    ## Seqs2DB(AA2, "DNAStringSet", dbConn, "AA2", tblName="AA2")
    ## AlignDB(dbConn, tblName=c("AA1", "AA2"), add2tbl="AA",
    # --- Expr8 [] ---
    # Key functions: width, attr
    ## # form a chained guide tree
    ## gT <- lapply(order(width(dna), decreasing=TRUE),
    ## 	function(x) {
    ## 		attr(x, "height") <- 0
    ## 		attr(x, "label") <- names(dna)[x]
    # --- Expr9 [] ---
    # Key functions: BrowseSeqs
    ## BrowseSeqs(DNA, highlight=0)
    # --- Expr10 [] ---
    # Key functions: AdjustAlignment
    ## DNA_adjusted <- AdjustAlignment(DNA)
    # --- Expr11 [] ---
    # Key functions: StaggerAlignment
    ## DNA_staggered <- StaggerAlignment(DNA)
    # --- Expr12 [] ---
    # Key functions: FindSynteny, AlignSynteny, unlist
    ## db <- system.file("extdata", "Influenza.sqlite", package="DECIPHER")
    ## synteny <- FindSynteny(db, verbose=FALSE)
    ## synteny # an object of class `Synteny`
    ## InfluenzaA <- AlignSynteny(synteny, db, verbose=FALSE)
    ## unlist(InfluenzaA[[1]])
    # --- Expr13 [] ---
    # Key functions: pairs
    ## pairs(synteny, boxBlocks=TRUE) # scatterplot matrix
    # --- Sessinfo [] ---
    # Key functions: toLatex
    toLatex(sessionInfo(), locale=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_decipher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_decipher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_decipher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DECIPHER:", paste0("    decipher: ", packageVersion("DECIPHER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decipher_results.csv
    touch ${prefix}_decipher_output.rds
    echo "BIOC_DECIPHER:" > versions.yml
    echo "    decipher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DECIPHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DECIPHER(ch_input)

    emit:
    results  = BIOC_DECIPHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DECIPHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DECIPHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DECIPHER.out.versions  // channel: path(versions.yml)
}
