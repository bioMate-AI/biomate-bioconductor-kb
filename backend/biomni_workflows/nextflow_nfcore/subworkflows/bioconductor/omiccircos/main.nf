#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OmicCircos
// OmicCircos is an R application and package for generating high-quality circular plots for omics data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OmicCircos/inst/doc/OmicCircos_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OmicCircos")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICCIRCOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omiccircos"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omiccircos:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omiccircos:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omiccircos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omiccircos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omiccircos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OmicCircos)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    options(stringsAsFactors = FALSE);
    library(OmicCircos);
    ## input hg19 cytogenetic band data
    data(UCSC.hg19.chr);
    head(UCSC.hg19.chr);
    # --- circos [] ---
    # Key functions: circos, sample
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="", main="");
    circos(R=400, cir=db, type="chr",  col=colors, print.chr.lab=TRUE, W=4, scale=TRUE);
    circos(R=360, cir=db, W=40, mapping=seg.v, col.v=3, type="l",   B=TRUE, col=colors[1], lwd=2, scale=TRUE);
    circos(R=320, cir=db, W=40, mapping=seg.v, col.v=3, type="ls",  B=FALSE, col=colors[9], lwd=2, scale=TRUE);
    # --- circos [] ---
    # Key functions: circos, sample, rainbow
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="", main="");
    circos(R=400, type="chr", cir=db, col=colors, print.chr.lab=TRUE, W=4, scale=TRUE);
    circos(R=360, cir=db, W=40, mapping=seg.v, col.v=8, type="quant90", B=FALSE, col=colors, lwd=2, scale=TRUE);
    circos(R=320, cir=db, W=40, mapping=seg.v, col.v=3, type="sv", B=TRUE, col=colors[7],  scale=TRUE);
    # --- circos [] ---
    # Key functions: circos
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="");
    circos(R=400, type="chr", cir="mm10", print.chr.lab=TRUE, W=4, scale=TRUE);
    circos(R=340, cir="mm10", W=60, mapping=cnv.d, type="b3", B=TRUE, col=colors[7]);
    circos(R=340, cir="mm10", W=60, mapping=cnv.d, type="s2", B=FALSE, col=colors[1], cex=0.5);
    # --- Data [] ---
    # Key functions: data, cbind
    options(stringsAsFactors = FALSE);
    library(OmicCircos);
    data("TCGA.PAM50_genefu_hg18");
    data("TCGA.BC.fus");
    data("TCGA.BC.cnv.2k.60");
    # --- circos [] ---
    # Key functions: circos
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="");
    circos(R=300, type="chr", cir="hg18", print.chr.lab=FALSE, W=4);
    circos(R=310, cir="hg18", W=20, mapping=TCGA.PAM50_genefu_hg18, type="label",
           side="out", col=c("black", "blue","red"), cex=0.4);
    # --- Data [] ---
    # Key functions: data, cbind
    options(stringsAsFactors = FALSE);
    library(OmicCircos);
    data("TCGA.PAM50_genefu_hg18");
    data("TCGA.BC.fus");
    data("TCGA.BC.cnv.2k.60");
    # --- circos [] ---
    # Key functions: circos
    par(mar=c(0, 0, 0, 0));
    plot(c(1,800), c(1,800), type="n", axes=FALSE, xlab="", ylab="", main="");
    circos(R=400, cir="hg18", W=4,   type="chr", print.chr.lab=TRUE, scale=TRUE);
    circos(R=300, cir="hg18", W=100, mapping=gene.exp,  col.v=8,  type="heatmap2",
           cluster=TRUE, col.bar=TRUE, lwd=0.1, col="blue");

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omiccircos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omiccircos_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omiccircos_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICCIRCOS:", paste0("    omiccircos: ", packageVersion("OmicCircos"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omiccircos_results.csv
    touch ${prefix}_omiccircos_output.rds
    echo "BIOC_OMICCIRCOS:" > versions.yml
    echo "    omiccircos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICCIRCOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICCIRCOS(ch_input)

    emit:
    results  = BIOC_OMICCIRCOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICCIRCOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICCIRCOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICCIRCOS.out.versions  // channel: path(versions.yml)
}
