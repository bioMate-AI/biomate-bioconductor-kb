#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: treeio
// 'treeio' is an R package to make it easier to import and store phylogenetic tree with associated dat
//
// Source : https://yulab-smu.top/treedata-book/chapter1.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("treeio")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREEIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treeio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treeio:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treeio:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treeio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treeio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treeio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(treeio)
    library(jsonlite)

    # --- Parsing BEAST output [] ---
    # Key functions: read.beast
    file <- system.file("extdata/BEAST", "beast_mcc.tree", package="treeio")
    beast <- read.beast(file)
    beast
    # --- Parsing MEGA output [] ---
    # Key functions: read.mega, read.mega_tabular
    file <- system.file("extdata/MEGA7", "mtCDNA_timetree.nex",
                        package = "treeio")
    read.mega(file)
    
    file <- system.file("extdata/MEGA7", "mtCDNA_timetree_tabular.txt",
                        package = "treeio")
    read.mega_tabular(file)
    # --- Parsing MrBayes output [] ---
    # Key functions: read.mrbayes
    file <- system.file("extdata/MrBayes", "Gq_nxs.tre", package="treeio")
    read.mrbayes(file)
    # --- Parsing PAML output [] ---
    # Key functions: read.paml_rst, read.codeml_mlc, read.codeml
    brstfile <- system.file("extdata/PAML_Baseml", "rst", package="treeio")
    brst <- read.paml_rst(brstfile)
    brst
    
    crstfile <- system.file("extdata/PAML_Codeml", "rst", package="treeio")
    ## type can be one of "Marginal" or "Joint"
    crst <- read.paml_rst(crstfile, type = "Joint")
    crst
    
    mlcfile <- system.file("extdata/PAML_Codeml", "mlc", package="treeio")
    mlc <- read.codeml_mlc(mlcfile)
    mlc
    # --- Parsing HyPhy output [] ---
    # Key functions: read.hyphy.seq, read.hyphy
    ancseq <- system.file("extdata/HYPHY", "ancseq.nex", package="treeio")
    read.hyphy.seq(ancseq)
    
    nwk <- system.file("extdata/HYPHY", "labelledtree.tree", package="treeio")
    tipfas <- system.file("extdata", "pa.fas", package="treeio")
    hy <- read.hyphy(nwk, ancseq, tipfas)
    hy
    # --- Parsing r8s output [] ---
    # Key functions: read.r8s
    r8s <- read.r8s(system.file("extdata/r8s", "H3_r8s_output.log", package="treeio"))
    r8s
    # --- Parsing output of RAxML bootstrap analysis [] ---
    # Key functions: read.raxml
    raxml_file <- system.file("extdata/RAxML",
                              "RAxML_bipartitionsBranchLabels.H3",
                              package="treeio")
    raxml <- read.raxml(raxml_file)
    raxml
    # --- Parsing NHX tree [] ---
    # Key functions: read.nhx
    nhxfile <- system.file("extdata/NHX", "phyldog.nhx", package="treeio")
    nhx <- read.nhx(nhxfile)
    nhx
    # --- Parsing Phylip tree [] ---
    # Key functions: read.phylip
    phyfile <- system.file("extdata", "sample.phy", package="treeio")
    phylip <- read.phylip(phyfile)
    phylip
    # --- Parsing EPA and pplacer output [] ---
    # Key functions: read.jplace
    jpf <- system.file("extdata/EPA.jplace",  package="treeio")
    jp <- read.jplace(jpf)
    print(jp)
    # --- Parsing jtree format [] ---
    # Key functions: tempfile, write.jtree, read.jtree
    jtree_file <- tempfile(fileext = '.jtree')
    write.jtree(beast, file = jtree_file)
    read.jtree(file = jtree_file)
    # --- Converting other tree-like objects to phylo or treedata objects [] ---
    # Key functions: read.tree, read.phyDat, pml, optim.pml, pml.control, as.treedata, ggtree, geom_text
    library(phangorn)
    treefile <- system.file("extdata", "pa.nwk", package="treeio")
    tre <- read.tree(treefile)
    tipseqfile <- system.file("extdata", "pa.fas", package="treeio")
    tipseq <- read.phyDat(tipseqfile,format="fasta")
    fit <- pml(tre, tipseq, k=4)
    fit <- optim.pml(fit, optNni=FALSE, optBf=T, optQ=T,
                     optInv=T, optGamma=T, optEdge=TRUE,
                     optRooted=FALSE, model = "GTR",
                     control = pml.control(trace =0))
    
    pmltree <- as.treedata(fit)
    # --- Getting information from treedata object [] ---
    # Key functions: read.beast, as.phylo, get.fields, get.data
    beast_file <- system.file("examples/MCC_FluA_H3.tree", package="ggtree")
    beast_tree <- read.beast(beast_file)
    # or get.tree
    as.phylo(beast_tree)
    
    beast_file <- system.file("examples/MCC_FluA_H3.tree", package="ggtree")
    beast_tree <- read.beast(beast_file)
    # or get.tree
    print(as.phylo(beast_tree), printlen=3)
    
    get.fields(beast_tree)
    

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treeio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treeio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treeio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREEIO:", paste0("    treeio: ", packageVersion("treeio"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treeio_results.csv
    touch ${prefix}_treeio_output.rds
    echo "BIOC_TREEIO:" > versions.yml
    echo "    treeio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREEIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREEIO(ch_input)

    emit:
    results  = BIOC_TREEIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREEIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREEIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREEIO.out.versions  // channel: path(versions.yml)
}
