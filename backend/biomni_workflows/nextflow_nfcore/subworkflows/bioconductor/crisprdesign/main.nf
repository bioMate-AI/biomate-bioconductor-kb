#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: crisprDesign
// Provides a comprehensive suite of functions to design and annotate CRISPR guide RNA (gRNAs) sequence
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/crisprDesign/inst/doc/intro.R
// Upstream  : Rbowtie, crisprBase
// Downstream: crisprViz
//
// Install: BiocManager::install("crisprDesign")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRDESIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprdesign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprdesign:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprdesign:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprdesign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprdesign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprdesign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(crisprBase)
    data(SpCas9, package="crisprBase")
    SpCas9
    # --- Prototypesequence [] ---
    # Key functions: prototypeSequence
    ---------------------------------------------------------------------
    prototypeSequence(SpCas9)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(grListExample, package="crisprDesign")
    # --- Spacers [] ---
    # Key functions: spacers, protospacers, pams, pamSites, cutSites
    ---------------------------------------------------------------------
    spacers(guideSet)
    protospacers(guideSet)
    pams(guideSet)
    head(pamSites(guideSet))
    # --- Alignments [] ---
    # Key functions: alignments
    ---------------------------------------------------------------------
    alignments(guideSet)
    # --- Head [] ---
    # Key functions: alignments
    ---------------------------------------------------------------------
    head(alignments(guideSet))
    # --- Head [] ---
    # Key functions: enzymeAnnotation
    ---------------------------------------------------------------------
    head(enzymeAnnotation(guideSet))
    # --- Geneannotation [] ---
    # Key functions: geneAnnotation
    ---------------------------------------------------------------------
    geneAnnotation(guideSet)
    # --- Data [] ---
    # Key functions: addTssAnnotation, tssAnnotation
    ---------------------------------------------------------------------
    data(tssObjectExample, package="crisprDesign")
    guideSet <- addTssAnnotation(guideSet,
                                 tssObject=tssObjectExample)
    tssAnnotation(guideSet)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(BE4max, package="crisprBase")
    BE4max
    # --- Editingweights [] ---
    # Key functions: editingWeights
    ---------------------------------------------------------------------
    crisprBase::editingWeights(BE4max)["C2T",]
    # --- Querytxobject [] ---
    # Key functions: queryTxObject, findSpacers
    ---------------------------------------------------------------------
    gr <- queryTxObject(txObject=grListExample,
                        featureType="cds",
                        queryColumn="gene_symbol",
                        queryValue="IQSEC3")
    # --- Gettxinfodataframe [] ---
    # Key functions: getTxInfoDataFrame
    ---------------------------------------------------------------------
    txid <- "ENST00000538872"
    txTable <- getTxInfoDataFrame(tx_id=txid,
                                  txObject=grListExample,
                                  bsgenome=bsgenome)
    # --- Editedalleles [] ---
    # Key functions: editedAlleles
    ---------------------------------------------------------------------
    alleles <- editedAlleles(gs)[[1]]
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(alleles)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprdesign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprdesign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprdesign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRDESIGN:", paste0("    crisprdesign: ", packageVersion("crisprDesign"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprdesign_results.csv
    touch ${prefix}_crisprdesign_output.rds
    echo "BIOC_CRISPRDESIGN:" > versions.yml
    echo "    crisprdesign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRDESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRDESIGN(ch_input)

    emit:
    results  = BIOC_CRISPRDESIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRDESIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRDESIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRDESIGN.out.versions  // channel: path(versions.yml)
}
