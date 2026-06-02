#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomation
// A package for summary and annotation of genomic intervals. Users can visualize and quantify genomic 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomation/inst/doc/GenomationManual.R
// Upstream  : AnnotationHub, GenomicRanges, genomationData, knitr
// Downstream: none
//
// Install: BiocManager::install("genomation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomation:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomation:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genomation)
    library(jsonlite)


    # --- Setup2 [] ---
    # Key functions: set, getwd, list.files, read.table
    library(knitr)
    opts_chunk$set(root.dir=getwd(),fig.align='center',
                   fig.path='Figures', 
                   dev='png',
                   fig.show='hold', 
                   cache=FALSE)
    library(genomation)
    library(genomationData)
    library(GenomicRanges)
    set.seed=10
    list.files(system.file('extdata',package='genomationData'))
    sampleInfo = read.table(system.file('extdata/SamplesInfo.txt',
                                        package='genomationData'),header=TRUE, sep='\t')
    sampleInfo[1:5,1:5]

    # --- Read Generic1 [] ---
    # Key functions: readGeneric, genomation
    library(genomation)
    tab.file1=system.file("extdata/tab1.bed", package = "genomation")
    readGeneric(tab.file1, header=TRUE)
    readGeneric(tab.file1, header=TRUE, keep.all.metadata=TRUE)

    readGeneric(tab.file1, header=TRUE, meta.col = list(CpGnum=4))
    readGeneric(tab.file1, header=TRUE, keep.all.metadata=TRUE)

    # --- Read Generic4 [] ---
    # Key functions: readGeneric, genomation, gffToGRanges, readFeatureFlank
    tab.file2=system.file("extdata/tab2.bed", package = "genomation")
    readGeneric(tab.file2, chr=3, start=2, end=1)
    gff.file=system.file("extdata/chr21.refseq.hg19.gtf", package = "genomation")
    gff = gffToGRanges(gff.file)
    head(gff)
    # reading genes stored as a BED files
    cpgi.file = system.file("extdata/chr21.CpGi.hg19.bed", package = "genomation")
    cpgi.flanks = readFeatureFlank(cpgi.file)
    head(cpgi.flanks$flanks)

    # --- Score Matrix Example [] ---
    # Key functions: ScoreMatrix, ScoreMatrixList, read.table, list.files, match, basename, readBroadPeak
    data(cage)
    data(promoters)
    sm = ScoreMatrix(target=cage, windows=promoters)
    sm
    data(promoters)
    data(cpgi)
    data(cage)

    cage$tpm = NULL
    targets = list(cage=cage, cpgi=cpgi)
    sm = ScoreMatrixList(targets=targets, windows=promoters, bin.num=50)
    sm
    library(genomationData)
    genomationDataPath = system.file('extdata',package='genomationData')
    sampleInfo = read.table(file.path(genomationDataPath, 'SamplesInfo.txt'), 
                            header=TRUE, sep='\t', stringsAsFactors=FALSE)

    peak.files=list.files(genomationDataPath, full.names=TRUE, pattern='broadPeak')
    names(peak.files) = sampleInfo$sampleName[match(basename(peak.files),sampleInfo$fileName)]


    # --- Read All Peaks Annotation [] ---
    # Key functions: annotateWithFeature, readTranscriptFeatures, genomation, annotateWithGeneParts
    data(cpgi)
    peak.annot = annotateWithFeature(ctcf.peaks, cpgi, intersect.chr=TRUE)
    peak.annot
    bed.file=system.file("extdata/chr21.refseq.hg19.bed", package = "genomation")
    gene.parts = readTranscriptFeatures(bed.file)
    ctcf.annot=annotateWithGeneParts(ctcf.peaks, gene.parts, intersect.chr=TRUE)
    ctcf.annot

    # --- Annotate Target List [] ---
    # Key functions: GRangesList, annotateWithGeneParts, list.files, readBroadPeak, seqnames, resize
    peaks = GRangesList(lapply(peak.files, readGeneric))
    names(peaks) = names(peak.files)
    annot.list = annotateWithGeneParts(peaks, gene.parts, intersect.chr=TRUE)
    genomationDataPath = system.file('extdata',package='genomationData')
    bam.files = list.files(genomationDataPath, full.names=TRUE, pattern='bam$')
    bam.files = bam.files[!grepl('Cage', bam.files)]
    ctcf.peaks = readBroadPeak(file.path(genomationDataPath, 
                                         'wgEncodeBroadHistoneH1hescCtcfStdPk.broadPeak.gz'))
    ctcf.peaks = ctcf.peaks[seqnames(ctcf.peaks) == 'chr21']
    ctcf.peaks = ctcf.peaks[order(-ctcf.peaks$signalValue)]
    ctcf.peaks = resize(ctcf.peaks, width=1000, fix='center')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMATION:", paste0("    genomation: ", packageVersion("genomation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomation_results.csv
    touch ${prefix}_genomation_output.rds
    echo "BIOC_GENOMATION:" > versions.yml
    echo "    genomation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMATION(ch_input)

    emit:
    results  = BIOC_GENOMATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMATION.out.versions  // channel: path(versions.yml)
}
