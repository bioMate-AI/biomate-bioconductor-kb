#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VennDetail
// A set of functions to generate high-resolution Venn,Vennpie plot,extract and combine details of thes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VennDetail/inst/doc/VennDetail.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VennDetail")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VENNDETAIL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-venndetail"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-venndetail:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-venndetail:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_venndetail_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_venndetail_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_venndetail_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(VennDetail)
    library(jsonlite)


    # --- Load [] ---
    # Key functions: venndetail
    library(VennDetail)
    data(T2DM)
    ven <- venndetail(list(Cortex = T2DM$Cortex$Entrez, SCN = T2DM$SCN$Entrez,
                        Glom = T2DM$Glom$Entrez))

    # --- Fig1 [] ---
    # Key functions: vennpie
    ##traditional venn diagram
    plot(ven)
    ##Venn-Pie format
    plot(ven, type = "vennpie")

    # --- Fig3 [] ---
    # Key functions: upset, detail, getSet
    ##Upset format
    plot(ven, type = "upset")
    ## List the subsets name
    detail(ven) 
    head(getSet(ven, subset = c("Shared", "SCN")), 10)

    # --- Result [] ---
    # Key functions: result, name, vennpie, lightgrey
    ## long format: the first column lists the subsets name, and the second column
    ## shows the genes included in the subsets
    head(result(ven))
    ## wide format: the first column lists all the genes, the following columns
    ## display the groups name (three tissues) and the last column is the total 
    ## number of the gene shared by groups.
    head(result(ven, wide = TRUE))
    vennpie(ven, any = 1, revcolor = "lightgrey")

    # --- Fig5 [] ---
    # Key functions: vennpie, sample, venndetail
    vennpie(ven, log = TRUE)
    set.seed(123)
    A <- sample(1:1000, 400, replace = FALSE)
    B <- sample(1:1000, 600, replace = FALSE)
    C <- sample(1:1000, 350, replace = FALSE)
    D <- sample(1:1000, 550, replace = FALSE)
    E <- sample(1:1000, 450, replace = FALSE)
    venn <- venndetail(list(A = A, B = B, C= C, D = D, E = E))
    vennpie(venn, min = 4)

    # --- Getfeature [] ---
    # Key functions: getFeature, dplot
    head(getFeature(ven, subset = "Shared", rlist = T2DM))
    dplot(ven, order = TRUE, textsize = 4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_venndetail_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_venndetail_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_venndetail_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VENNDETAIL:", paste0("    venndetail: ", packageVersion("VennDetail"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_venndetail_results.csv
    touch ${prefix}_venndetail_output.rds
    echo "BIOC_VENNDETAIL:" > versions.yml
    echo "    venndetail: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VENNDETAIL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VENNDETAIL(ch_input)

    emit:
    results  = BIOC_VENNDETAIL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VENNDETAIL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VENNDETAIL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VENNDETAIL.out.versions  // channel: path(versions.yml)
}
