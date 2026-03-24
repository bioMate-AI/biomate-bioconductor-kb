#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEDIPS
// MEDIPS was developed for analyzing data derived from methylated DNA immunoprecipitation (MeDIP) expe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEDIPS/inst/doc/MEDIPS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MEDIPS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEDIPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-medips"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-medips:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-medips:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_medips_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_medips_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_medips_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CpGenrich)
    library(jsonlite)

    # --- Genomes [] ---
    # Key functions: genomes
    ## available.genomes()
    # --- Createset [] ---
    # Key functions: createSet
    ## hESCs_MeDIP = MEDIPS.createSet(file=bam.file.hESCs.Rep1.MeDIP, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    # --- Data [] ---
    # Key functions: data
    data(hESCs_MeDIP)
    data(DE_MeDIP)
    # --- Createset [] ---
    # Key functions: createSet
    hESCs_Input = MEDIPS.createSet(file=bam.file.hESCs.Input, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    DE_Input = MEDIPS.createSet(file=bam.file.DE.Input, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    # --- Couplingvector [] ---
    # Key functions: couplingVector
    CS = MEDIPS.couplingVector(pattern="CG", refObj=hESCs_MeDIP[[1]])
    # --- Meth [] ---
    # Key functions: meth
    mr.edgeR = MEDIPS.meth(MSet1=DE_MeDIP, MSet2=hESCs_MeDIP, CSet=CS, ISet1=DE_Input, ISet2=hESCs_Input, p.adj="bonferroni", diff.method="edgeR", MeDIP=T, CNV=F, minRowSum=10)
    # --- Selectsig [] ---
    # Key functions: selectSig
    mr.edgeR.s = MEDIPS.selectSig(results=mr.edgeR, p.value=0.1, adj=T, ratio=NULL, bg.counts=NULL, CNV=F)
    # --- Mergeframes [] ---
    # Key functions: mergeFrames
    mr.edgeR.s.gain.m = MEDIPS.mergeFrames(frames=mr.edgeR.s.gain, distance=1)
    # --- Selectrois [] ---
    # Key functions: selectROIs
    ## rois.s=MEDIPS.selectROIs(results=mr.edgeR, rois=mr.edgeR.s.gain.m, columns=columns, summarize="avg")
    # --- Saturation [] ---
    # Key functions: saturation
    sr=MEDIPS.saturation(file=bam.file.hESCs.Rep1.MeDIP, BSgenome=BSgenome, uniq=uniq, extend=extend, shift=shift, window_size=ws, chr.select=chr.select, nit=10, nrit=1, empty_bins=TRUE, rank=FALSE)
    # --- Saturationplot [] ---
    # Key functions: plotSaturation
    MEDIPS.plotSaturation(sr)
    # --- Correlation [] ---
    # Key functions: correlation
    ## cor.matrix=MEDIPS.correlation(MSets=c(hESCs_MeDIP, DE_MeDIP, hESCs_Input, DE_Input), plot=T, method="pearson")
    # --- Seqcoverage [] ---
    # Key functions: seqCoverage
    cr=MEDIPS.seqCoverage(file=bam.file.hESCs.Rep1.MeDIP, pattern="CG", BSgenome=BSgenome, chr.select=chr.select, extend=extend, shift=shift, uniq=uniq)
    # --- Coverageplot [] ---
    # Key functions: plotSeqCoverage
    MEDIPS.plotSeqCoverage(seqCoverageObj=cr, type="pie", cov.level = c(0,1, 2, 3, 4, 5))
    # --- Coverageplothist [] ---
    # Key functions: plotSeqCoverage
    MEDIPS.plotSeqCoverage(seqCoverageObj=cr, type="hist", t = 15, main="Sequence pattern coverage, histogram")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_medips_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_medips_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_medips_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEDIPS:", paste0("    medips: ", packageVersion("MEDIPS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_medips_results.csv
    touch ${prefix}_medips_output.rds
    echo "BIOC_MEDIPS:" > versions.yml
    echo "    medips: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEDIPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEDIPS(ch_input)

    emit:
    results  = BIOC_MEDIPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEDIPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEDIPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEDIPS.out.versions  // channel: path(versions.yml)
}
