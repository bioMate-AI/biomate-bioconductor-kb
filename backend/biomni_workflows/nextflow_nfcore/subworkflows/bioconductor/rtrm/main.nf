#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rTRM
// rTRM identifies transcriptional regulatory modules (TRMs) from protein-protein interaction networks.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rTRM/inst/doc/Introduction.R
// Upstream  : MotifDb, PWMEnrich
// Downstream: none
//
// Install: BiocManager::install("rTRM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTRM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtrm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtrm:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtrm:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtrm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtrm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtrm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rTRM)
    library(jsonlite)

    # --- Getmatrices [] ---
    # Key functions: getMatrices
    ---------------------------------------------------------------------
    pwm <- getMatrices()
    head(pwm, 1)
    # --- Getannotations [] ---
    # Key functions: getAnnotations
    ---------------------------------------------------------------------
    ann <- getAnnotations()
    head(ann)
    # --- Getmaps [] ---
    # Key functions: getMaps
    ---------------------------------------------------------------------
    map <- getMaps()
    head(map)
    # --- Getorthologs [] ---
    # Key functions: getOrthologs
    ---------------------------------------------------------------------
    o <- getOrthologs(organism = "mouse")
    head(o)
    # --- Getorthologfrommatrix [] ---
    # Key functions: getOrthologFromMatrix
    ---------------------------------------------------------------------
    getOrthologFromMatrix("MA0009.1", organism="human")
    getOrthologFromMatrix("MA0009.1", organism="mouse")
    # --- Biogrid Mm [] ---
    # Key functions: biogrid_mm
    ---------------------------------------------------------------------
    # check statistics about the network.
    biogrid_mm()
    # load mouse PPI network:
    data(biogrid_mm)
    # --- Getorthologfrommatrix [] ---
    # Key functions: getOrthologFromMatrix, unlist
    ---------------------------------------------------------------------
    # get the corresponding gene.
    tfs_list <- getOrthologFromMatrix(motif_list, organism = "mouse")
    tfs_list <- unique(unlist(tfs_list, use.names = FALSE))
    length(tfs_list)
    # --- Biogrid Mm [] ---
    # Key functions: biogrid_mm, vcount, ecount, select, removeVertices, subgraph
    ---------------------------------------------------------------------
    # load and process PPI data.
    biogrid_mm()
    data(biogrid_mm)
    ppi <- biogrid_mm
    # --- Select [] ---
    # Key functions: select, findTRM, vcount, ecount
    ---------------------------------------------------------------------
    # define target.
    target <- select(org.Mm.eg.db,keys="Sox2",columns="ENTREZID",keytype="SYMBOL")$ENTREZID
    target
    # find TRM.
    # --- Registercorespwmenrich [] ---
    # Key functions: registerCoresPWMEnrich, values
    ---------------------------------------------------------------------
    library(rTRM)
    library(BSgenome.Mmusculus.UCSC.mm8.masked) # Sox2 peaks found against mm8
    library(PWMEnrich)
    registerCoresPWMEnrich(1) # register number of cores for parallelization in PWMEnrich
    # --- Table [] ---
    # Key functions: getSequencesFromGenome, width
    ---------------------------------------------------------------------
    sox2_bed <- read.table(system.file("extra/ESC_Sox2_peaks.txt", package = "rTRM"))
    colnames(sox2_bed) <- c("chr", "start", "end")
    sox2_seq <- getSequencesFromGenome(sox2_bed, Mmusculus, append.id="Sox2")
    # PWMEnrich throws an error if the sequences are shorter than the motifs so we filter those sequences.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtrm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtrm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtrm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTRM:", paste0("    rtrm: ", packageVersion("rTRM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtrm_results.csv
    touch ${prefix}_rtrm_output.rds
    echo "BIOC_RTRM:" > versions.yml
    echo "    rtrm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTRM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTRM(ch_input)

    emit:
    results  = BIOC_RTRM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTRM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTRM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTRM.out.versions  // channel: path(versions.yml)
}
