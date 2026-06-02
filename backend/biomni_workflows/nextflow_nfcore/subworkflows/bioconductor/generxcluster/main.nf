#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geneRxCluster
// Detect Differential Clustering of Genomic Sites such as gene therapy integrations.  The package prov
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geneRxCluster/inst/doc/tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("geneRxCluster")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENERXCLUSTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-generxcluster"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-generxcluster:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-generxcluster:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_generxcluster_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_generxcluster_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_generxcluster_plots.pdf"),    emit: plots, optional: true
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

    # --- Chromos [] ---
    # Key functions: structure
    chr.lens <- structure(c(247249719L, 242951149L, 199501827L,
        191273063L, 180857866L, 170899992L, 158821424L, 146274826L,
        140273252L, 135374737L, 134452384L, 132349534L, 114142980L,
        106368585L, 100338915L, 88827254L, 78774742L, 76117153L,
        63811651L, 62435964L, 46944323L, 49691432L, 154913754L,
    # --- Chr Samples [] ---
    # Key functions: factor, sample
    set.seed(13245)
    chr.names <- names(chr.lens)
    chr.factor <- factor(chr.names,chr.names)
    chrs <- sample(chr.factor,40000,repl=TRUE,
    	       prob=chr.lens)
    # --- Grp Samp [] ---
    # Key functions: rbinom
    df$grp <-
        rbinom(40000, 1, 0.5)==1
    # --- Null Run [] ---
    # Key functions: gRxCluster, frame
    require(geneRxCluster,quietly=TRUE)
    null.results <-
        gRxCluster(df$chromo,df$pos,df$grp,15L:30L,nperm=100L)
    as.data.frame(null.results)[,c(-4,-5)]
    # --- Grxsmry [] ---
    # Key functions: gRxSummary
    gRxSummary( null.results )
    # --- Sim True [] ---
    # Key functions: sample
    clump.chrs <- sample(chr.factor,30,repl=TRUE,
    		 prob=chr.lens)
    # --- Sapply [] ---
    # Key functions: pos
    clump.chr.pos.bound <-
        sapply(chr.lens[clump.chrs], function(y) sample.pos(1,y))
    # --- Rep [] ---
    # Key functions: rep
    clump.site.ns <- rep(c(15,25,40),each=10)
    # --- Lapply [] ---
    # Key functions: sample
    clump.sites <-
        lapply(seq_along(clump.chrs),
    	   function(x) {
    	       chromo <- clump.chrs[x]
    	       n <- clump.site.ns[x]
    # --- Rep [] ---
    # Key functions: rep
    clump.grps <- rep(0:1,15)==1
    # --- Frame [] ---
    # Key functions: frame, unlist
    df2 <- data.frame(
        chromo=rep(clump.chrs,clump.site.ns),
        pos=unlist(clump.sites),
        grp=rep(clump.grps,clump.site.ns)
        )
    # --- Alt Clumps [] ---
    # Key functions: gRxCluster, gRxSummary
    alt.results <-
        gRxCluster(df3$chromo,df3$pos,df3$grp,
    	       15L:30L, nperm=100L)
    gRxSummary(alt.results)
    # --- Torf Disc [] ---
    # Key functions: GRanges, IRanges
    df2.GRanges <-
        GRanges(seqnames=df2$chromo,IRanges(start=df2$pos,width=1),
    	    clump=rep(1:30,clump.site.ns))
    # --- Subjecthits [] ---
    # Key functions: subjectHits, findOverlaps
    clumps.found <- subjectHits(findOverlaps(alt.results,df2.GRanges))
    # --- Matrix [] ---
    # Key functions: factor
    matrix(
        table(factor(df2.GRanges$clump[ clumps.found ],1:30)),
        nrow=10,dimnames=list(clump=NULL,site.ns=c(15,25,40)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_generxcluster_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_generxcluster_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_generxcluster_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENERXCLUSTER:", paste0("    generxcluster: ", packageVersion("geneRxCluster"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generxcluster_results.csv
    touch ${prefix}_generxcluster_output.rds
    echo "BIOC_GENERXCLUSTER:" > versions.yml
    echo "    generxcluster: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENERXCLUSTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENERXCLUSTER(ch_input)

    emit:
    results  = BIOC_GENERXCLUSTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENERXCLUSTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENERXCLUSTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENERXCLUSTER.out.versions  // channel: path(versions.yml)
}
