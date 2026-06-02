#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifStack
// The motifStack package is designed for graphic representation of multiple motifs with different simi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifStack/inst/doc/motifStack_HTML.R
// Upstream  : JASPAR2020, MotifDb, RColorBrewer, TFBSTools, ade4
// Downstream: generegulation
//
// Install: BiocManager::install("motifStack")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motifstack"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motifstack:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-motifstack:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motifstack_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motifstack_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motifstack_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAmotifToRNAmotif)
    library(jsonlite)

    # --- Checkplatform [] ---
    # Key functions: set
    library(knitr)
    library(motifStack)
    library(MotifDb)
    library(ade4)
    library(ggplot2)
    # --- Importmatrix [] ---
    # Key functions: importMatrix, getMatrixSet
    library(motifStack)
    library(JASPAR2020)
    motifs <- importMatrix(getMatrixSet(JASPAR2020,
                                        list(species="Mus musculus")))
    plot(motifs[[1]])
    # --- Importfromfiles [] ---
    # Key functions: importMatrix
    RUNX1 <- importMatrix(system.file("extdata", "MA0002.1.jaspar",
                                      package = "motifStack",
                                      mustWork = TRUE))[[1]]
    plot(RUNX1)
    # --- Dnaseqlogo [] ---
    # Key functions: path, package, new
    library(motifStack)
    pcm <- read.table(file.path(find.package("motifStack"),
                                "extdata", "bin_SOLEXA.pcm"))
    pcm <- pcm[,3:ncol(pcm)]
    rownames(pcm) <- c("A","C","G","T")
    # --- Seqlogomarkers [] ---
    # Key functions: new, gpar
    markerRect <- new("marker", type="rect", start=6, stop=7, gp=gpar(lty=2, fill=NA, col="orange"))
    markerLine <- new("marker", type="line", start=2, stop=7, gp=gpar(lwd=2, col="red"))
    markerText <- new("marker", type="text", start=c(1, 5),
                      label=c("*", "core"), gp=gpar(cex=2, col="red"))
    # --- Seqlogoxaxis [] ---
    # Key functions: int
    plot(motif, xaxis=paste0("pos", seq.int(7)+10))
    # --- Aaseqlogo [] ---
    # Key functions: path, package, pcm2pfm, new, colorset
    library(motifStack)
    protein<-read.table(file.path(find.package("motifStack"),"extdata","cap.txt"))
    protein<-t(protein[,1:20])
    motif<-pcm2pfm(protein)
    # --- Affinitylogo [] ---
    # Key functions: new, gpar
    library(motifStack)
    # --- Logostack [] ---
    # Key functions: importMatrix, path, package, motifStack
    library(motifStack)
    #####Input#####
    motifs<-importMatrix(dir(file.path(find.package("motifStack"),
                                       "extdata"),"pcm$",
                             full.names = TRUE))
    # --- Rnalogostack [] ---
    # Key functions: DNAmotifToRNAmotif, motifStack
    rnaMotifs <- DNAmotifToRNAmotif(motifs)
    names(rnaMotifs)
    motifStack(rnaMotifs, layout = "stack",
               reorder=FALSE) ## we can also use reorder=FALSE to keep the order of input.
    # --- Logostack2 [] ---
    # Key functions: motifStack
    motif2 <- motif
    motif2$mat <- motif$mat[, 5:12]
    motif2$name <- "logo2"
    psamMotifs <- list(motif, motif2)
    motifStack(psamMotifs)
    # --- Treestack [] ---
    # Key functions: motifStack
    ## plot stacks with hierarchical tree
    motifStack(motifs, layout="tree")
    # --- Radialstack [] ---
    # Key functions: query, sample
    ## When the number of motifs is too much to be shown in a vertical stack,
    ## motifStack can draw them in a radial style.
    ## random sample from MotifDb
    library("MotifDb")
    matrix.fly <- query(MotifDb, "Dmelanogaster")
    # --- Motifcloud [] ---
    # Key functions: pal, new, clusterMotifs
    ## assign groups for motifs
    groups <- rep(paste("group",1:5,sep=""), each=10)
    names(groups) <- names(pfms)
    ## assign group colors
    group.col <- brewer.pal(5, "Set3")
    # --- Motifradialphylog [] ---
    # Key functions: signatures, sigColor, plotMotifStackWithRadialPhylog
    ## get the signatures from object of motifSignature
    sig <- signatures(motifSig)
    ## set the inner-circle color for each signature
    gpCol <- sigColor(motifSig)
    ## plot the logo stack with radial style.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motifstack_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motifstack_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motifstack_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFSTACK:", paste0("    motifstack: ", packageVersion("motifStack"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motifstack_results.csv
    touch ${prefix}_motifstack_output.rds
    echo "BIOC_MOTIFSTACK:" > versions.yml
    echo "    motifstack: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFSTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFSTACK(ch_input)

    emit:
    results  = BIOC_MOTIFSTACK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFSTACK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFSTACK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFSTACK.out.versions  // channel: path(versions.yml)
}
