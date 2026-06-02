#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LymphoSeq
// This R package analyzes high-throughput sequencing of T and B cell receptor complementarity determin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LymphoSeq/inst/doc/LymphoSeq.R
// Upstream  : RColorBrewer, ggplot2, grDevices, pheatmap, reshape
// Downstream: none
//
// Install: BiocManager::install("LymphoSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LYMPHOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lymphoseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lymphoseq:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lymphoseq:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lymphoseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lymphoseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lymphoseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LymphoSeq)
    library(jsonlite)


    # --- Results = "hide" [] ---
    # Key functions: readImmunoSeq, extdata, TCRB_sequencing, TRB_Unsorted_0
    library(LymphoSeq)

    TCRB.path <- system.file("extdata", "TCRB_sequencing", package = "LymphoSeq")

    TCRB.list <- readImmunoSeq(path = TCRB.path)
    names(TCRB.list)
    lapply(TCRB.list, dim)
    CMV <- TCRB.list[grep("CMV", names(TCRB.list))]
    names(CMV)
    TRB_Unsorted_0 <- TCRB.list[["TRB_Unsorted_0"]]
    head(TRB_Unsorted_0)

    # --- Comment = "" [] ---
    # Key functions: extdata, TCRB_metadata.csv, samples, productiveSeq, aminoAcid, nucleotide, TRB_Unsorted_0
    TCRB.metadata <- read.csv(system.file("extdata", "TCRB_metadata.csv", package = "LymphoSeq"))
    TCRB.metadata
    selected <- as.character(TCRB.metadata[TCRB.metadata$phenotype == "Unsorted" & 
                                     TCRB.metadata$day > 300, "samples"])
    TCRB.list.selected <- TCRB.list[selected]
    names(TCRB.list.selected)
    productive.TRB.aa <- productiveSeq(file.list = TCRB.list, aggregate = "aminoAcid", 
                                   prevalence = FALSE)
    productive.TRB.nt <- productiveSeq(file.list = TCRB.list, aggregate = "nucleotide", 
                                   prevalence = FALSE)
    head(TCRB.list[["TRB_Unsorted_0"]])

    # --- Comment = "" [] ---
    # Key functions: TRB_Unsorted_0, clonality, readImmunoSeq, extdata, IGH_sequencing
    head(productive.TRB.aa[["TRB_Unsorted_0"]])
    head(productive.TRB.nt[["TRB_Unsorted_0"]])
    clonality(file.list = TCRB.list)
    IGH.path <- system.file("extdata", "IGH_sequencing", package = "LymphoSeq")

    IGH.list <- readImmunoSeq(path = IGH.path)

    # --- Comment = "" [] ---
    # Key functions: clonalRelatedness, productiveSeq, nucleotide, alignSeq, IGH_MVQ92552A_BL, aminoAcid, consule, searchSeq
    clonalRelatedness(list = IGH.list, editDistance = 10)
    productive.IGH.nt <- productiveSeq(file.list = IGH.list, aggregate = "nucleotide")
    alignSeq(list = productive.IGH.nt, sample = "IGH_MVQ92552A_BL", type = "aminoAcid", 
             method = "ClustalW", output = "consule")
    searchSeq(list = productive.TRB.aa, sequence = "CASSPVSNEQFF", type = "aminoAcid", 
              match = "global", editDistance = 0)

    # --- Comment = "" [] ---
    # Key functions: searchPublished, bhattacharyyaMatrix, similarityMatrix, commonSeqs, TRB_Unsorted_0, TRB_Unsorted_32, differentialAbundance, TRB_Unsorted_949
    published <- searchPublished(list = productive.TRB.aa)
    head(published)
    bhattacharyya.matrix <- bhattacharyyaMatrix(productive.seqs = productive.TRB.aa)
    bhattacharyya.matrix
    similarity.matrix <- similarityMatrix(productive.seqs = productive.TRB.aa)
    similarity.matrix
    common <- commonSeqs(samples = c("TRB_Unsorted_0", "TRB_Unsorted_32"), 
                        productive.aa = productive.TRB.aa)
    head(common)
    differentialAbundance(list = productive.TRB.aa, 
                          sample1 = "TRB_Unsorted_949", 
                          sample2 = "TRB_Unsorted_1320", 
                          type = "aminoAcid", q = 0.01)

    # --- Comment = "" [] ---
    # Key functions: uniqueSeqs, seqMatrix, topFreq, geneFreq
    unique.seqs <- uniqueSeqs(productive.aa = productive.TRB.aa)
    head(unique.seqs)
    sequence.matrix <- seqMatrix(productive.aa = productive.TRB.aa, sequences = unique.seqs$aminoAcid)
    head(sequence.matrix)
    top.freq <- topFreq(productive.aa = productive.TRB.aa, percent = 0.1)
    head(top.freq)
    top.freq <- topFreq(productive.aa = productive.TRB.aa, percent = 0)
    top.freq.matrix <- merge(top.freq, sequence.matrix)
    head(top.freq.matrix)
    vGenes <- geneFreq(productive.nt = productive.TRB.nt, locus = "V", family = TRUE)
    head(vGenes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lymphoseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lymphoseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lymphoseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LYMPHOSEQ:", paste0("    lymphoseq: ", packageVersion("LymphoSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lymphoseq_results.csv
    touch ${prefix}_lymphoseq_output.rds
    echo "BIOC_LYMPHOSEQ:" > versions.yml
    echo "    lymphoseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LYMPHOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LYMPHOSEQ(ch_input)

    emit:
    results  = BIOC_LYMPHOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LYMPHOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LYMPHOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LYMPHOSEQ.out.versions  // channel: path(versions.yml)
}
