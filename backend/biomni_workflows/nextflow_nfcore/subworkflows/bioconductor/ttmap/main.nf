#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TTMap
// TTMap is a clustering method that groups together samples with the same deviation in comparison to a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TTMap/inst/doc/TTMap.R
// Upstream  : airway, rgl
// Downstream: none
//
// Install: BiocManager::install("TTMap")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TTMAP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ttmap"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ttmap:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ttmap:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ttmap_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ttmap_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ttmap_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TTMap)
    library(jsonlite)

    # --- Loadlibanddata [] ---
    # Key functions: rowSums, assay, make_matrices
    library(airway)
    data(airway)
    airway <- airway[rowSums(assay(airway))>80,]
    assay(airway) <- log(assay(airway)+1,2)
    # --- Part1 [] ---
    # Key functions: control_adjustment
    E=1
    Pw=1.1
    Bw=0
    # --- Part2 [] ---
    # Key functions: hyperrectangle_deviation_assessment
    TTMAP_part1_hda <- TTMap::hyperrectangle_deviation_assessment(x =
    TTMAP_part1prime,k=dim(TTMAP_part1prime$Normal.mat)[2],
    dataname = "The_effect_of_cancer", normalname = "The_healthy_controls");
    head(TTMAP_part1_hda$Dc.Dmat)
    # --- Part3 [] ---
    # Key functions: generate_mismatch_distance
    library(rgl)
    ALPHA <- 1
    annot <- c(paste(colnames(experiment$TEST[,-seq_len(3)]),"Dis",sep=".")
    ,paste(colnames(experiment$CTRL[,-seq_len(3)]),"Dis",sep="."))
    annot <- cbind(annot,annot)
    # --- Part4 [] ---
    # Key functions: ttmap_sgn_genes
    TTMap::ttmap_sgn_genes(TTMAP_part2_gtlmap,
    TTMAP_part1_hda, TTMAP_part1prime,
    annot, n = 2, a = ALPHA,
    filename = "first_trial", annot = TTMAP_part1prime$tag.pcl, col = "NAME",
    path = getwd(), Relaxed = 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ttmap_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ttmap_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ttmap_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TTMAP:", paste0("    ttmap: ", packageVersion("TTMap"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ttmap_results.csv
    touch ${prefix}_ttmap_output.rds
    echo "BIOC_TTMAP:" > versions.yml
    echo "    ttmap: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TTMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TTMAP(ch_input)

    emit:
    results  = BIOC_TTMAP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TTMAP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TTMAP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TTMAP.out.versions  // channel: path(versions.yml)
}
