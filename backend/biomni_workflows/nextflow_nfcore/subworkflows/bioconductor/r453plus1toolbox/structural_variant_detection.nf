#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r453plus1toolbox — structural_variant_detection
// Preprocess raw reads, filter chimeric alignments, and detect genomic breakpoints.
// Input: 1.TCA.454Reads.fna, N01.bam, CaptureArray_hg19.bed
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
// R packages: Biostrings, R453Plus1Toolbox, Rsamtools, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biostrings", "R453Plus1Toolbox", "Rsamtools", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(R453Plus1Toolbox)
    library(Biostrings)
    library(Rsamtools)
    library(rtracklayer)
    
    # 1. Demultiplex raw reads using multiplex identifiers (MIDs)
    fnaFile = "1.TCA.454Reads.fna"
    seqs = readDNAStringSet(fnaFile, format="fasta")
    MIDSeqs = genomeSequencerMIDs(c("MID1", "MID2", "MID3"))
    dmReads = demultiplexReads(seqs, MIDSeqs, numMismatches=2, trim=TRUE)
    
    # 2. Remove sequencing linkers and filter by minimum read length
    minReadLength = 15
    gSel3 = sequenceCaptureLinkers("gSel3")[[1]]
    trimReads = lapply(dmReads, function (reads) {
      reads = reads[width(reads) >= minReadLength]
      reads = removeLinker(reads, gSel3)
      reads = reads[width(reads) >= minReadLength]
      readsRev = reverseComplement(reads)
      readsRev = removeLinker(readsRev, gSel3)
      reads = reverseComplement(readsRev)
      reads = reads[width(reads) >= minReadLength]
      return(reads)
    })
    
    # Save preprocessed reads for MID1
    write.XStringSet(trimReads[["MID1"]], file="N01.fasta", format="fasta")
    
    # 3. Filter chimeric reads using target regions and linker sequences
    bamFile = "N01.bam"
    parameters = ScanBamParam(what=scanBamWhat())
    bam = scanBam(bamFile, param=parameters)
    
    bedFile = "CaptureArray_hg19.bed"
    chip = import.ucsc(bedFile, subformat="bed")
    chip = split(ranges(chip[[1]]), seqnames(chip[[1]]))
    names(chip) = gsub("chr", "", names(chip))
    
    linker = sequenceCaptureLinkers("gSel3")[[1]]
    filterReads = filterChimericReads(bam, targetRegion=chip, linkerSeq=linker)
    
    # Save filtering log
    write.csv(filterReads\$log, file="filter_chimeric_reads_log.csv", row.names=FALSE)
    
    # 4. Cluster chimeric reads to detect putative breakpoints
    bp = detectBreakpoints(filterReads, minClusterSize=1)
    saveRDS(bp, file="detected_breakpoints.rds")
    
    # 5. Merge related pathogenic and reciprocal breakpoints
    mbp = mergeBreakpoints(bp)
    saveRDS(mbp, file="merged_breakpoints.rds")
    
    # Save summary of merged breakpoints
    sink("merged_breakpoints_summary.txt")
    print(summary(mbp))
    sink()
    
    # 6. Visualize breakpoint regions and aligned reads
    pdf("chimeric_reads_plot.pdf", width=11, height=8.5)
    plotChimericReads(mbp[1], legend=TRUE)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION":
        r453plus1toolbox: \$(Rscript -e 'cat(as.character(packageVersion("r453plus1toolbox")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structural_variant_detection.csv versions.yml
    """
}

workflow BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 1.TCA.454Reads.fna, N01.bam, CaptureArray_hg19.bed ] ]

    main:
    BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION(ch_input)

    emit:
    tables   = BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION.out.tables
    plots    = BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION.out.plots
    objects  = BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION.out.objects
    versions = BIOC_R453PLUS1TOOLBOX_STRUCTURAL_VARIANT_DETECTION.out.versions
}
