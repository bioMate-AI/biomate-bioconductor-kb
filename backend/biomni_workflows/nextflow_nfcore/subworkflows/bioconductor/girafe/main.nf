#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: girafe
// The package 'girafe' deals with the genome-level representation of aligned reads from next-generatio
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/girafe/inst/doc/girafe.R
// Upstream  : RColorBrewer, parallel
// Downstream: none
//
// Install: BiocManager::install("girafe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GIRAFE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-girafe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-girafe:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-girafe:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_girafe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_girafe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_girafe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlignedGenomeIntervals)
    library(jsonlite)

    # --- Loadreads [] ---
    # Key functions: readFastq
    ra23.wa  <- readFastq(dirPath=exDir, pattern=
                          "aravinSRNA_23_plus_adapter_excerpt.fastq")
    # --- Trimadapter [] ---
    # Key functions: trimAdapter, show
    adapter <- "CTGTAGGCACCATCAAT"
    ra23.na  <- trimAdapter(ra23.wa, adapter)
    show(ra23.na)
    # --- Readaligned [] ---
    # Key functions: readAligned, show
    exA   <- readAligned(dirPath=exDir, type="Bowtie",
       pattern="aravinSRNA_23_no_adapter_excerpt_mm9_unmasked.bwtmap")
    show(exA)
    # --- Convertaligned [] ---
    # Key functions: organism
    exAI <- as(exA, "AlignedGenomeIntervals")
    organism(exAI) <- "Mm"
    # --- Tabchromosomes [] ---
    # Key functions: seqnames
    table(seqnames(exAI))
    # --- Showsubset [] ---
    # Key functions: detail, seqnames
    detail(exAI[seqnames(exAI)=="chrMT"])
    # --- Setuptoy [] ---
    # Key functions: AlignedGenomeIntervals, detail

    # --- Showreducedata [] ---
    # Key functions: seqnames, matches, detail
    S <- exAI[seqnames(exAI)=="chrX" & matches(exAI)==1L & exAI[,1]>1e8]
    detail(S)
    # --- Reduceexample3 [] ---
    # Key functions: seqnames, matches, detail, reduce
    S2 <- exAI[seqnames(exAI)=="chr11" & matches(exAI)==1L & exAI[,1]>8e7]
    detail(S2)
    detail(reduce(S2, method="exact"))
    # --- Exampleperwindow [] ---
    # Key functions: perWindow
    exPX  <- perWindow(exAI, chr="chrX", winsize=1e5, step=0.5e5)
    head(exPX[order(exPX$n.overlap, decreasing=TRUE),])
    # --- Exportbed [] ---
    # Key functions: export
    ## export(exAI, con="export.bed",
    ##        format="bed", name="example_reads",
    ##        description="Example reads",
    ##        color="100,100,255", visibility="pack")
    # --- Getintervaloverlap [] ---
    # Key functions: interval_overlap
    exOv <- interval_overlap(exAI, mgi.gi)
    # --- Tableoverlap [] ---
    # Key functions: listLen
    table(listLen(exOv))
    # --- list Len [] ---
    # Key functions: listLen
    mgi.gi$ID[exOv[[which.max(listLen(exOv))]]]
    # --- Computetabov [] ---
    # Key functions: unlist
    (tabOv <- table(as.character(mgi.gi$type)[unlist(exOv)]))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_girafe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_girafe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_girafe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GIRAFE:", paste0("    girafe: ", packageVersion("girafe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_girafe_results.csv
    touch ${prefix}_girafe_output.rds
    echo "BIOC_GIRAFE:" > versions.yml
    echo "    girafe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GIRAFE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GIRAFE(ch_input)

    emit:
    results  = BIOC_GIRAFE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GIRAFE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GIRAFE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GIRAFE.out.versions  // channel: path(versions.yml)
}
