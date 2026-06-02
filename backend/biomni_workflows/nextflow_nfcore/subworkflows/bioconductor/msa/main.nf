#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msa
// The 'msa' package provides a unified R/Bioconductor interface to the multiple sequence alignment alg
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msa/inst/doc/msa.R
// Upstream  : seqinr, pwalign, ape
// Downstream: none
//
// Install: BiocManager::install("msa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msa:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msa:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(msa)
    library(jsonlite)


    # --- Load Package To Determine Version [] ---
    # Key functions: packageDescription, substr, msa, readAAStringSet, examples, exampleAA.fasta, complete
    options(width=65)
    set.seed(0)
    library(msa)
    library(seqinr)
    msaVersion <- packageDescription("msa")$Version
    msaDateRaw <- packageDescription("msa")$Date
    msaDateYear <- as.numeric(substr(msaDateRaw, 1, 4))
    msaDateMonth <- as.numeric(substr(msaDateRaw, 6, 7))
    msaDateDay <- as.numeric(substr(msaDateRaw, 9, 10))
    # --- Visualize Pdf [] ---
    # Key functions: msaPrettyPrint, asis, none, msa, complete, IRanges, colmask
    msaPrettyPrint(myFirstAlignment, y=c(164, 213), output="asis",
                   showNames="none", showLogo="none", askForOverwrite=FALSE)
    myClustalWAlignment <- msa(mySequences, "ClustalW")
    myClustalWAlignment
    myClustalOmegaAlignment <- msa(mySequences, "ClustalOmega")
    myClustalOmegaAlignment
    myMuscleAlignment <- msa(mySequences, "Muscle")
    myMuscleAlignment
    print(myFirstAlignment)
    print(myFirstAlignment, show="complete")
    print(myFirstAlignment, showConsensus=FALSE, halfNrow=3)
    print(myFirstAlignment, showNames=FALSE, show="complete")
    myMaskedAlignment <- myFirstAlignment
    colM <- IRanges(start=1, end=100)
    colmask(myMaskedAlignment) <- colM
    myMaskedAlignment

    # --- Unmasked Example [] ---
    # Key functions: unmasked, consensusMatrix, function, getOption, for, substr, printSplitString, msaConsensusSequence
    unmasked(myMaskedAlignment)
    conMat <- consensusMatrix(myFirstAlignment)
    dim(conMat)
    conMat[, 101:110]
    conMat <- consensusMatrix(myMaskedAlignment)
    conMat[, 95:104]
    printSplitString <- function(x, width=getOption("width") - 1)
    {
        starts <- seq(from=1, to=nchar(x), by=width)

        for (i in 1:length(starts))
            cat(substr(x, starts[i], starts[i] + width - 1), "\n")
    }

    printSplitString(msaConsensusSequence(myFirstAlignment))

    # --- Consensus Example4 [] ---
    # Key functions: printSplitString, msaConsensusSequence, upperlower, msaConservationScore
    printSplitString(msaConsensusSequence(myFirstAlignment, type="upperlower",
                                          thresh=c(40, 20)))
    printSplitString(msaConsensusSequence(myMaskedAlignment, type="upperlower",
                                          thresh=c(40, 20)))
    library(pwalign)  # for the BLOSUM62 matrix
    data(BLOSUM62)
    msaConservationScore(myFirstAlignment, BLOSUM62)
    msaConservationScore(myFirstAlignment, BLOSUM62, gapVsGap=0,
                         type="upperlower", thresh=c(40, 20))

    # --- Conservation Example3 [] ---
    # Key functions: msaConservationScore, upperlower, readAAStringSet, msa, msaConvert, dist.alignment, HBA1_Homo_sapiens
    msaConservationScore(myMaskedAlignment, BLOSUM62, gapVsGap=0,
                         type="upperlower", thresh=c(40, 20))
    hemoSeq <- readAAStringSet(system.file("examples/HemoglobinAA.fasta",
                                           package="msa"))
    hemoAln <- msa(hemoSeq)
    hemoAln
    hemoAln2 <- msaConvert(hemoAln, type="seqinr::alignment")
    library(seqinr)

    d <- dist.alignment(hemoAln2, "identity")
    as.matrix(d)[2:5, "HBA1_Homo_sapiens", drop=FALSE]
    library(ape)

    hemoTree <- nj(d)
    plot(hemoTree, main="Phylogenetic Tree of Hemoglobin Alpha Sequences")

    # --- Hemoglobin3 [] ---
    # Key functions: msaConvert, str, msaPrettyPrint, asis, none, top, rasmol, similar
    hemoAln3 <- msaConvert(hemoAln, type="bios2mds::align")
    str(hemoAln3)
    hemoAln4 <- as(hemoAln, "BStringSet")
    hemoAln4
    msaPrettyPrint(myFirstAlignment, output="asis", y=c(164, 213),
                   subset=c(1:6), showNames="none", showLogo="none",
                   consensusColor="ColdHot", showLegend=FALSE,
                   askForOverwrite=FALSE)
    msaPrettyPrint(myFirstAlignment, output="asis", y=c(164, 213),
                   subset=c(1:6), showNames="none", showLogo="top",
                   logoColors="rasmol", shadingMode="similar",
                   showLegend=FALSE, askForOverwrite=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSA:", paste0("    msa: ", packageVersion("msa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msa_results.csv
    touch ${prefix}_msa_output.rds
    echo "BIOC_MSA:" > versions.yml
    echo "    msa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSA(ch_input)

    emit:
    results  = BIOC_MSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSA.out.versions  // channel: path(versions.yml)
}
