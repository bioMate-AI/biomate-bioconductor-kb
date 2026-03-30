#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seq2pathway
// Seq2pathway is a novel tool for functional gene-set (or termed as pathway) analysis of next-generati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seq2pathway/inst/doc/seq2pathwaypackage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seq2pathway")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQ2PATHWAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seq2pathway"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seq2pathway:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seq2pathway:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seq2pathway_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seq2pathway_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seq2pathway_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seq2pathway)
    library(jsonlite)

    # --- Chipseq Peak Demo [] ---
    # Key functions: data, class
    data(Chipseq_Peak_demo)
    class(Chipseq_Peak_demo)
    head(Chipseq_Peak_demo)
    # --- Granges Demo [] ---
    # Key functions: data, class
    data(GRanges_demo)
    class(GRanges_demo)
    GRanges_demo[1:3,]
    # --- Msigdb C5 [] ---
    # Key functions: data, class
    data(MsigDB_C5,package="seq2pathway.data")
    class(MsigDB_C5)
    # --- Chipseq Peak Demo [] ---
    # Key functions: data
    data(Chipseq_Peak_demo)
    head(Chipseq_Peak_demo)
    # --- runseq2gene [] ---
    # Key functions: runseq2gene
    Chipseq_anno <- runseq2gene(
                      inputfile=Chipseq_Peak_demo,
                      genome="hg19", adjacent=FALSE, SNP=FALSE, search_radius=1000,
                      PromoterStop=FALSE,NearestTwoDirection=TRUE)
    class(Chipseq_anno)
    # --- Msigdb C5 [] ---
    # Key functions: data, class
    ## give the previously defined gene-sets
    data(MsigDB_C5,package="seq2pathway.data")
    class(MsigDB_C5)
    ## load the gene-level measurements, here is an example of ChIP-seq scores
    data(dat_chip)
    # --- Dat Gene2Path Chip [] ---
    # Key functions: data, class
    data(dat_gene2path_chip,package="seq2pathway.data")
    names(dat_gene2path_chip)
    class(dat_gene2path_chip$gene2pathway_result.2)
    names(dat_gene2path_chip$gene2pathway_result.2)
    dat_gene2path_chip$gene2pathway_result.2$GO_BP[1:3,]
    # --- Msigdb C5 [] ---
    # Key functions: data, class
    data(MsigDB_C5,package="seq2pathway.data")
    class(MsigDB_C5)
    # --- Dat Chip [] ---
    # Key functions: data
    data(dat_chip)
    head(dat_chip)
    # --- Fishertest Go Bp Mf Cc [] ---
    # Key functions: data
    data(dat_chip)
    head(dat_chip)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seq2pathway_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seq2pathway_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seq2pathway_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQ2PATHWAY:", paste0("    seq2pathway: ", packageVersion("seq2pathway"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seq2pathway_results.csv
    touch ${prefix}_seq2pathway_output.rds
    echo "BIOC_SEQ2PATHWAY:" > versions.yml
    echo "    seq2pathway: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQ2PATHWAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQ2PATHWAY(ch_input)

    emit:
    results  = BIOC_SEQ2PATHWAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQ2PATHWAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQ2PATHWAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQ2PATHWAY.out.versions  // channel: path(versions.yml)
}
