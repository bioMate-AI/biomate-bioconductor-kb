#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: crisprBase
// Provides S4 classes for general nucleases, CRISPR nucleases, CRISPR nickases, and base editors.Sever
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/crisprBase/inst/doc/crisprBase.R
// Upstream  : none
// Downstream: crisprDesign, crisprViz
//
// Install: BiocManager::install("crisprBase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprbase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprbase:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprbase:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(crisprBase)
    library(BaseEditor)
    library(Cas12a)
    library(Cas9)
    library(CrisprNickase)
    library(CrisprNuclease)
    library(GACGC)
    library(Nuclease)
    library(TTTV)
    library(jsonlite)

    # --- CRISPR Nuclease Definition [] ---
    # Key functions: CrisprNuclease, cutSites
    SpCas9 <- CrisprNuclease(
        "SpCas9",
        targetType = "DNA",
        pams = c("(3/3)NGG", "(3/3)NAG", "(3/3)NGA"),
        weights = c(1, 0.2593, 0.0694),
        metadata = list(description = "SpCas9 nuclease"),
        pam_side = "3prime",
        spacer_length = 20
    )
    cs_plus <- cutSites(SpCas9, strand = "+")
    cs_minus <- cutSites(SpCas9, strand = "-")


    # --- Target and Protospacer Extraction [] ---
    # Key functions: extractPamFromTarget, extractProtospacerFromTarget
    targets <- c("AGGTGCTGATTGTAGTGCTGCGG", "AGGTGCTGATTGTAGTGCTGAGG")
    pams <- extractPamFromTarget(targets, SpCas9)
    spacers <- extractProtospacerFromTarget(targets, SpCas9)


    # --- Genomic Range Mapping [] ---
    # Key functions: getPamRanges, getProtospacerRanges, getTargetRanges
    chr <- rep("chr7", 2)
    pam_site <- rep(200, 2)
    strand <- c("+", "-")
    gr_pam <- getPamRanges(
        seqnames = chr, pam_site = pam_site,
        strand = strand, nuclease = SpCas9
    )
    gr_proto <- getProtospacerRanges(
        seqnames = chr, pam_site = pam_site,
        strand = strand, nuclease = SpCas9
    )
    gr_target <- getTargetRanges(
        seqnames = chr, pam_site = pam_site,
        strand = strand, nuclease = SpCas9
    )


    # --- Base Editor Design and Visualisation [] ---
    # Key functions: BaseEditor, plotEditingWeights
    ws_matrix <- matrix(0.1, nrow = 4, ncol = 20)
    rownames(ws_matrix) <- c("A", "C", "G", "T")
    colnames(ws_matrix) <- 1:20
    BE4max <- BaseEditor(
        SpCas9,
        baseEditorName = "BE4max",
        editingStrand = "original",
        editingWeights = ws_matrix
    )
    plotEditingWeights(BE4max)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprbase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprbase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRBASE:", paste0("    crisprbase: ", packageVersion("crisprBase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprbase_results.csv
    touch ${prefix}_crisprbase_output.rds
    echo "BIOC_CRISPRBASE:" > versions.yml
    echo "    crisprbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRBASE(ch_input)

    emit:
    results  = BIOC_CRISPRBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRBASE.out.versions  // channel: path(versions.yml)
}
