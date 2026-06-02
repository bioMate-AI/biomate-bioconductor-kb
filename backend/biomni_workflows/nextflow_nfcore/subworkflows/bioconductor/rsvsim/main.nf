#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RSVSim
// RSVSim is a package for the simulation of deletions, insertions, inversion, tandem-duplications and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RSVSim/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RSVSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSVSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsvsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsvsim:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsvsim:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsvsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsvsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsvsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Toyexample [] ---
    # Key functions: DNAStringSet
    genome = DNAStringSet(
    c("AAAAAAAAAAAAAAAAAAAATTTTTTTTTTTTTTTTTTTT",
    "GGGGGGGGGGGGGGGGGGGGCCCCCCCCCCCCCCCCCCCC"))
    names(genome) = c("chr1","chr2")
    genome
    # --- Genomeecoli [] ---
    # Key functions: DNAStringSet
    ## library(BSgenome.Ecoli.NCBI.20080805)
    ## genome = DNAStringSet(Ecoli[["NC_008253"]])
    ## names(genome) = "NC_008253"
    # --- Deletionexample [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome, dels=3, sizeDels=10,
    bpSeqSize=6, seed=456, verbose=FALSE)
    sim
    metadata(sim)
    # --- Insertionexample [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome, ins=3, sizeIns=5, bpSeqSize=6,
    seed=246, verbose=FALSE)
    sim
    metadata(sim)
    # --- Inversionexample [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome, invs=3, sizeInvs=c(2,4,6),
    bpSeqSize=6, seed=456, verbose=FALSE)
    sim
    metadata(sim)
    # --- Tandemdupexample [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome, dups=1, sizeDups=6, maxDups=3,
    bpSeqSize=6, seed=3456, verbose=FALSE)
    sim
    metadata(sim)
    # --- Translocationexample1 [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome,trans=1, bpSeqSize=6, seed=123, verbose=FALSE)
    sim
    metadata(sim)
    # --- Weightsmechanisms [] ---
    # Key functions: show
    data(weightsMechanisms, package="RSVSim")
    show(weightsMechanisms)
    # --- Weightsrepeats [] ---
    # Key functions: show
    data(weightsRepeats, package="RSVSim")
    show(weightsRepeats)
    # --- Weightsexample [] ---
    # Key functions: frame, simulateSV

    # --- Bpmutationsexample [] ---
    # Key functions: simulateSV, metadata
    sim = simulateSV(output=NA, genome=genome, dels=1, sizeDels=5, bpFlankSize=10,
    percSNPs=0.25, indelProb=1, maxIndelSize=3, bpSeqSize=10, seed=123, verbose=FALSE)
    sim
    metadata(sim)
    # --- Regionsexample1 [] ---
    # Key functions: GRanges, IRanges, simulateSV, metadata
    regions = GRanges(IRanges(c(21,1),c(40,20)), seqnames=c("chr1","chr2"))
    regions
    sim = simulateSV(output=NA, genome=genome, invs=4, sizeInvs=5,
    regionsInvs=regions, bpSeqSize=6, seed=2345, verbose=FALSE)
    sim
    # --- Regionsexample2 [] ---
    # Key functions: makeTxDbFromUCSC, exonsBy, unlist, GRanges, IRanges, start, end, seqnames
    ## transcriptDB = makeTxDbFromUCSC(genome = "hg19",tablename = "knownGene")
    ## exons = exonsBy(transcriptDB)
    ## exons = unlist(exons)
    ## exons = GRanges(IRanges(start=start(exons), end=end(exons)), seqnames=seqnames(exons))
    ## simulateSV(output=NA, dels=100, regionsDels=exons, sizeDels=1000, bpSeqSize=50)
    # --- Regionsexample3 [] ---
    # Key functions: GRanges, IRanges, simulateSV, metadata
    knownDeletion = GRanges(IRanges(16,25), seqnames="chr2")
    names(knownDeletion) = "myDeletion"
    knownDeletion
    sim = simulateSV(output=NA, genome=genome, regionsDels=knownDeletion,
    bpSeqSize=10, random=FALSE, verbose=FALSE)
    # --- Regionsexample4 [] ---
    # Key functions: GRanges, IRanges, simulateSV, metadata
    knownInsertion = GRanges(IRanges(16,25),seqnames="chr1", chrB="chr2", startB=26)
    names(knownInsertion) = "myInsertion"
    knownInsertion
    sim = simulateSV(output=NA, genome=genome, regionsIns=knownInsertion,
    bpSeqSize=10, random=FALSE, verbose=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsvsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsvsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsvsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSVSIM:", paste0("    rsvsim: ", packageVersion("RSVSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsvsim_results.csv
    touch ${prefix}_rsvsim_output.rds
    echo "BIOC_RSVSIM:" > versions.yml
    echo "    rsvsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSVSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSVSIM(ch_input)

    emit:
    results  = BIOC_RSVSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSVSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSVSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSVSIM.out.versions  // channel: path(versions.yml)
}
