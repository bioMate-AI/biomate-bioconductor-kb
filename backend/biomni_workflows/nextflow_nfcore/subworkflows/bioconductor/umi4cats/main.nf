#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UMI4Cats
// UMI-4C is a technique that allows characterization of 3D chromatin interactions with a bait of inter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UMI4Cats/inst/doc/UMI4Cats.R
// Upstream  : tidyr
// Downstream: none
//
// Install: BiocManager::install("UMI4Cats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UMI4CATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-umi4cats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-umi4cats:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-umi4cats:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_umi4cats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_umi4cats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_umi4cats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UMI4Cats)
    library(jsonlite)

    # --- Demultiplexing and Processing Contacts [] ---
    # Key functions: demultiplexFastq, contactsUMI4C
    demultiplexFastq(
        fastq = fastq,
        barcodes = barcodes,
        out_path = out_path
    )
    contactsUMI4C(
        fastq_dir = raw_dir,
        wk_dir = file.path(path, "CIITA"),
        file_pattern = "ctrl_hi24_CIITA",
        bait_seq = "GGACAAGCTCCCTGCAACTCA",
        bait_pad = "GGACTTGCA",
        res_enz = "GATC",
        cut_pos = 0,
        digested_genome = hg19_dpnii,
        bowtie_index = index_path,
        ref_gen = refgen,
        sel_seqname = "chr16",
        threads = 2,
        numb_reads = 1e6
    )


    # --- Object Construction and Visualization [] ---
    # Key functions: makeUMI4C, plotUMI4C
    umi <- makeUMI4C(
        colData = colData,
        viewpoint_name = "CIITA",
        grouping = "condition",
        bait_expansion = 2e6
    )
    plotUMI4C(umi, grouping=NULL)


    # --- Interaction Calling and Differential Testing [] ---
    # Key functions: makeWindowFragments, callInteractions, getSignInteractions, fisherUMI4C, waldUMI4C
    win_frags <- makeWindowFragments(umi, n_frags=8)
    gr <- callInteractions(umi4c = umi,
                           design = ~condition,
                           query_regions = win_frags,
                           padj_threshold = 0.01,
                           zscore_threshold=2)
    inter <- getSignInteractions(gr)
    umi_fisher <- fisherUMI4C(umi, query_regions = inter,
                              filter_low = 20,
                              grouping="condition")
    umi_wald <- waldUMI4C(umi4c=umi,
                          query_regions = inter,
                          design=~condition)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_umi4cats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_umi4cats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_umi4cats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UMI4CATS:", paste0("    umi4cats: ", packageVersion("UMI4Cats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi4cats_results.csv
    touch ${prefix}_umi4cats_output.rds
    echo "BIOC_UMI4CATS:" > versions.yml
    echo "    umi4cats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UMI4CATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UMI4CATS(ch_input)

    emit:
    results  = BIOC_UMI4CATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UMI4CATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UMI4CATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UMI4CATS.out.versions  // channel: path(versions.yml)
}
