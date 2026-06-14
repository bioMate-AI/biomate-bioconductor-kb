#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monalisa — annotate_genomic_regions
// Scan genomic sequences for predicted transcription factor binding motif hits.
// Input: promoters.bed, motifs.jaspar
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, BiocParallel, TFBSTools, monaLisa, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "BiocParallel", "TFBSTools", "monaLisa", "rtracklayer")
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
    library(rtracklayer)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(TFBSTools)
    library(monaLisa)
    library(BiocParallel)
    
    # --- Define genomic regions and extract sequences ---
    # Read genomic coordinates from the user-provided BED file
    gr <- trim(import("promoters.bed", format = "bed"))
    
    # Extract genomic sequences using the mm10 BSgenome object
    seqs <- getSeq(BSgenome.Mmusculus.UCSC.mm10, gr)
    
    # Ensure the sequences have names so that seqnames(res) matches the levels correctly
    if (is.null(names(seqs))) {
      if (!is.null(gr\$name)) {
        names(seqs) <- gr\$name
      } else {
        names(seqs) <- paste0("region_", seq_along(seqs))
      }
    }
    
    # --- Load motifs and convert to PWMs ---
    # Read transcription factor binding motifs from the user-provided JASPAR file
    pfms <- readJASPARMatrix("motifs.jaspar", matrixClass = "PFM")
    pwms <- toPWM(pfms)
    
    # --- Scan sequences for motif hits using findMotifHits ---
    res <- findMotifHits(query = pwms, subject = seqs, min.score = 6.0, method = "matchPWM", BPPARAM = BiocParallel::SerialParam())
    
    # --- Create a motif hit matrix (counts of motifs per sequence) ---
    m <- table(factor(seqnames(res), levels = names(seqs)), factor(res\$pwmname, levels = name(pwms)))
    
    # Save meaningful results to output files
    saveRDS(res, "motif_hits.rds")
    write.table(as.data.frame(res), "motif_hits.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
    write.csv(as.matrix(m), "motif_hit_matrix.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS":',
        paste0('        monalisa: ', as.character(packageVersion("monalisa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotate_genomic_regions.csv versions.yml
    """
}

workflow BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ promoters.bed, motifs.jaspar ] ]

    main:
    BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS(ch_input)

    emit:
    tables   = BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS.out.tables
    plots    = BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS.out.plots
    objects  = BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS.out.objects
    versions = BIOC_MONALISA_ANNOTATE_GENOMIC_REGIONS.out.versions
}
