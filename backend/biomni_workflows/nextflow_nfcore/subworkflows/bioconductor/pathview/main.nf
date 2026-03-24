#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pathview
// Pathview is a tool set for pathway based data integration and visualization. It maps and renders a w
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pathview/inst/doc/pathview.R
// Upstream  : gage
// Downstream: EGSEA, SBGNview
//
// Install: BiocManager::install("pathview")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHVIEW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathview"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathview:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathview:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathview_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathview_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathview_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pathview)
    library(jsonlite)

    # --- Synopsis1 [] ---
    # Key functions: pathview
    ## library(pathview)
    ## data(gse16873.d)
    ## pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = "04110",
    ##                    species = "hsa", out.suffix = "gse16873")
    # --- <Install [] ---
    # Key functions: packages
    ## install.packages("/your/local/directory/XML_3.95-0.2.zip", repos = NULL)
    # --- Readin [] ---
    # Key functions: delim
    ## filename=system.file("extdata/gse16873.demo", package = "pathview")
    ## gse16873=read.delim(filename, row.names=1)
    ## gse16873.d=gse16873[,2*(1:6)]-gse16873[,2*(1:6)-1]
    # --- data [] ---
    # Key functions: data
    data(paths.hsa)
    head(paths.hsa,3)
    # --- pathview [] ---
    # Key functions: pathview, files
    i <- 1
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873", kegg.native = T)
    list.files(pattern="hsa04110", full.names=T)
    str(pv.out)
    # --- Kegg.Native 2Layer [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873.2layer", kegg.native = T,
                       same.layer = F)
    # --- Graphviz [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873", kegg.native = F,
                       sign.pos = demo.paths$spos[i])
    #pv.out remains the same
    dim(pv.out$plot.data.gene)
    # --- pathview [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
        species = "hsa", out.suffix = "gse16873.2layer", kegg.native = F,
        sign.pos = demo.paths$spos[i], same.layer = F)
    # --- Split [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
        species = "hsa", out.suffix = "gse16873.split", kegg.native = F,
        sign.pos = demo.paths$spos[i], split.group = T)
    dim(pv.out$plot.data.gene)
    head(pv.out$plot.data.gene)
    # --- Expanded [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths$sel.paths[i],
        species = "hsa", out.suffix = "gse16873.split.expanded", kegg.native = F,
        sign.pos = demo.paths$spos[i], split.group = T, expand.node = T)
    dim(pv.out$plot.data.gene)
    head(pv.out$plot.data.gene)
    # --- data [] ---
    # Key functions: data
    sim.cpd.data=sim.mol.data(mol.type="cpd", nmol=3000)
    data(cpd.simtypes)
    # --- Gene Cpd.Data [] ---
    # Key functions: pathview
    i <- 3
    print(demo.paths$sel.paths[i])
    pv.out <- pathview(gene.data = gse16873.d[, 1], cpd.data = sim.cpd.data,
        pathway.id = demo.paths$sel.paths[i], species = "hsa", out.suffix = "gse16873.cpd",
        keys.align = "y", kegg.native = T, key.pos = demo.paths$kpos1[i])
    # --- Graphviz.Gene Cpd.Data [] ---
    # Key functions: pathview
    pv.out <- pathview(gene.data = gse16873.d[, 1], cpd.data = sim.cpd.data,
        pathway.id = demo.paths$sel.paths[i], species = "hsa", out.suffix = "gse16873.cpd",
        keys.align = "y", kegg.native = F, key.pos = demo.paths$kpos2[i],
        sign.pos = demo.paths$spos[i], cpd.lab.offset = demo.paths$offs[i])
    # --- sample [] ---
    # Key functions: sample
    set.seed(10)
    sim.cpd.data2 = matrix(sample(sim.cpd.data, 18000,
        replace = T), ncol = 6)
    rownames(sim.cpd.data2) = names(sim.cpd.data)
    colnames(sim.cpd.data2) = paste("exp", 1:6, sep = "")
    # --- Multisample.Gene Cpd.Data [] ---
    # Key functions: pathview
    #KEGG view
    pv.out <- pathview(gene.data = gse16873.d[, 1:3],
        cpd.data = sim.cpd.data2[, 1:2], pathway.id = demo.paths$sel.paths[i],
        species = "hsa", out.suffix = "gse16873.cpd.3-2s", keys.align = "y",
        kegg.native = T, match.data = F, multi.state = T, same.layer = T)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathview_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathview_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathview_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHVIEW:", paste0("    pathview: ", packageVersion("pathview"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathview_results.csv
    touch ${prefix}_pathview_output.rds
    echo "BIOC_PATHVIEW:" > versions.yml
    echo "    pathview: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHVIEW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHVIEW(ch_input)

    emit:
    results  = BIOC_PATHVIEW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHVIEW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHVIEW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHVIEW.out.versions  // channel: path(versions.yml)
}
