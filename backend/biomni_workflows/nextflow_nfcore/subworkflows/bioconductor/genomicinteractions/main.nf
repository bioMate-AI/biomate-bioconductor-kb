#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicInteractions
// Utilities for handling genomic interaction data such as ChIA-PET or Hi-C, annotating genomic feature
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicInteractions/inst/doc/chiapet_vignette.R
// Upstream  : GenomicFeatures, GenomicRanges, Gviz, InteractionSet, knitr
// Downstream: none
//
// Install: BiocManager::install("GenomicInteractions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICINTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicinteractions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicinteractions:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicinteractions:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicinteractions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicinteractions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicinteractions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicInteractions)
    library(jsonlite)


    # --- Load Data [] ---
    # Key functions: makeGenomicInteractionsFromFile, chiapet.tool, k562, name, description, interactionCounts
    chiapet.data = system.file("extdata/k562.rep1.cluster.pet3+.txt", 
                               package="GenomicInteractions")

    k562.rep1 = makeGenomicInteractionsFromFile(chiapet.data, 
                                    type="chiapet.tool", 
                                    experiment_name="k562", 
                                    description="k562 pol2 8wg16")
    name(k562.rep1)
    description(k562.rep1) = "PolII-8wg16 Chia-PET for K562"
    head(interactionCounts(k562.rep1))
    head((k562.rep1)$fdr)
    hist(-log10(k562.rep1$p.value))

    # --- Anchor Access [] ---
    # Key functions: anchorOne, anchorTwo, is.trans, calculateDistances, midpoint
    anchorOne(k562.rep1)
    anchorTwo(k562.rep1)
    sprintf("Percentage of trans-chromosomal interactions %.2f", 
            100*sum(is.trans(k562.rep1))/length(k562.rep1))
    head(calculateDistances(k562.rep1, method="midpoint"))

    # --- Subsetting [] ---
    # Key functions: sample, is.cis, calculateDistances, midpoint, as.vector, seqnames, anchorOne, anchorTwo
    k562.rep1[1:10] # first interactions in the dataset
    k562.rep1[sample(length(k562.rep1), 100)] # 100 interactions subsample
    k562.cis = k562.rep1[is.cis(k562.rep1)]
    head(calculateDistances(k562.cis, method="midpoint"))
    k562.short = k562.cis[calculateDistances(k562.cis) < 1e6] # subset shorter interactions
    hist(calculateDistances(k562.short))
    chrom = c("chr17", "chr18")
    sub = as.vector(seqnames(anchorOne(k562.rep1)) %in% chrom & seqnames(anchorTwo(k562.rep1)) %in% chrom)
    k562.rep1 = k562.rep1[sub]

    # --- Load Trascripts [] ---
    # Key functions: hg19.refseq.transcripts, promoters, unlist, strand, ifelse, relist, subsetByFeatures
    data("hg19.refseq.transcripts")
    refseq.transcripts = hg19.refseq.transcripts
    refseq.promoters = promoters(refseq.transcripts, upstream=2500, downstream=2500)
    # unlist object so "strand" is one vector
    refseq.transcripts.ul = unlist(refseq.transcripts) 
    # terminators can be called as promoters with the strand reversed
    strand(refseq.transcripts.ul) = ifelse(strand(refseq.transcripts.ul) == "+", "-", "+") 
    refseq.terminators.ul = promoters(refseq.transcripts.ul, upstream=1000, downstream=1000) 
    # change back to original strand
    strand(refseq.terminators.ul) = ifelse(strand(refseq.terminators.ul) == "+", "-", "+") 
    # `relist' maintains the original names and structure of the list
    refseq.terminators = relist(refseq.terminators.ul, refseq.transcripts)
    subsetByFeatures(k562.rep1, unlist(refseq.promoters))

    # --- Annotation [] ---
    # Key functions: annotateInteractions, annotationFeatures, anchorOne, anchorTwo, promoter, categoriseInteractions
    annotation.features = list(promoter=refseq.promoters, 
                               terminator=refseq.terminators, 
                               gene.body=refseq.transcripts)
    annotateInteractions(k562.rep1, annotation.features)
    annotationFeatures(k562.rep1)
    p.one = anchorOne(k562.rep1)$node.class == "promoter"
    p.two = anchorTwo(k562.rep1)$node.class == "promoter"
    k562.rep1[p.one|p.two]
    categoriseInteractions(k562.rep1)

    # --- Is Interaction Type [] ---
    # Key functions: isInteractionType, terminator, gene.body, plotInteractionAnnotations, promoter
    k562.rep1[isInteractionType(k562.rep1, "terminator", "gene.body")]
    plotInteractionAnnotations(k562.rep1, other=5)
    plotInteractionAnnotations(k562.rep1, other=5, viewpoints="promoter")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicinteractions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicinteractions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicinteractions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICINTERACTIONS:", paste0("    genomicinteractions: ", packageVersion("GenomicInteractions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicinteractions_results.csv
    touch ${prefix}_genomicinteractions_output.rds
    echo "BIOC_GENOMICINTERACTIONS:" > versions.yml
    echo "    genomicinteractions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICINTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICINTERACTIONS(ch_input)

    emit:
    results  = BIOC_GENOMICINTERACTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICINTERACTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICINTERACTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICINTERACTIONS.out.versions  // channel: path(versions.yml)
}
