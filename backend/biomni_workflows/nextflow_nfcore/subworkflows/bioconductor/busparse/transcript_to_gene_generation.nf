#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: busparse — transcript_to_gene_generation
// Generate transcript-to-gene (tr2g) mapping files and filtered transcriptomes from various annotation sources (Ensembl, FASTA, GTF, TxDb, EnsDb).
// Input: transcriptome.fasta, annotation.gtf
// Container: quay.io/biocontainers/bioconductor-busparse:1.24.0--r45ha27e39d_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, BUSpaRse, EnsDb.Hsapiens.v86, TxDb.Hsapiens.UCSC.hg38.knownGene
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-busparse:1.24.0--r45ha27e39d_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "BUSpaRse", "EnsDb.Hsapiens.v86", "TxDb.Hsapiens.UCSC.hg38.knownGene")
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
    library(BUSpaRse)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(EnsDb.Hsapiens.v86)
    
    # 1. Download and filter transcriptome using dl_transcriptome
    # Drosophila melanogaster
    tryCatch({
      dl_transcriptome("Drosophila melanogaster", out_path = "fly", 
                       gene_biotype_use = "cellranger", verbose = FALSE)
      list.files("fly")
    }, error = function(e) {
      message("Skipping Drosophila melanogaster download due to error: ", e\$message)
    })
    
    # Caenorhabditis elegans
    tryCatch({
      dl_transcriptome("Caenorhabditis elegans", out_path = "worm", verbose = FALSE,
                       gene_biotype_use = "cellranger", ensembl_version = 115)
      list.files("worm")
    }, error = function(e) {
      message("Skipping Caenorhabditis elegans download due to error: ", e\$message)
    })
    
    # Saccharomyces cerevisiae
    tryCatch({
      dl_transcriptome("Saccharomyces cerevisiae", out_path = "yeast", 
                       type = "fungus", gene_biotype_use = "cellranger", 
                       verbose = FALSE)
      list.files("yeast")
    }, error = function(e) {
      message("Skipping Saccharomyces cerevisiae download due to error: ", e\$message)
    })
    
    # 2. Generate tr2g mapping from Ensembl using tr2g_ensembl
    # Mus musculus
    tryCatch({
      tr2g_mm <- tr2g_ensembl("Mus musculus", ensembl_version = 115, 
                              other_attrs = "description", 
                              gene_biotype_use = "cellranger")
      print(head(tr2g_mm))
      write.csv(tr2g_mm, "tr2g_mm.csv", row.names = FALSE)
    }, error = function(e) {
      message("Skipping Mus musculus Ensembl query due to error: ", e\$message)
    })
    
    # Arabidopsis thaliana
    tryCatch({
      tr2g_at <- tr2g_ensembl("Arabidopsis thaliana", type = "plant")
      print(head(tr2g_at))
      write.csv(tr2g_at, "tr2g_at.csv", row.names = FALSE)
    }, error = function(e) {
      message("Skipping Arabidopsis thaliana Ensembl query due to error: ", e\$message)
    })
    
    # 3. Extract tr2g mapping from a FASTA file using tr2g_fasta
    # User input: transcriptome.fasta
    toy_fasta <- "transcriptome.fasta"
    tr2g_fa <- tr2g_fasta(file = toy_fasta, write_tr2g = FALSE, save_filtered = FALSE)
    print(head(tr2g_fa))
    write.csv(tr2g_fa, "tr2g_fa.csv", row.names = FALSE)
    
    # 4. Extract tr2g mapping and transcriptome from a GTF file and genome using tr2g_gtf
    # User input: annotation.gtf
    toy_gtf <- "annotation.gtf"
    tr2g_tg <- tr2g_gtf(toy_gtf, Genome = BSgenome.Hsapiens.UCSC.hg38,
                        gene_biotype_use = "cellranger",
                        out_path = "gtf")
    print(head(tr2g_tg))
    print(list.files("gtf"))
    write.csv(tr2g_tg, "tr2g_tg.csv", row.names = FALSE)
    
    # 5. Extract tr2g mapping from a TxDb object using tr2g_TxDb
    tr2g_hs <- tr2g_TxDb(TxDb.Hsapiens.UCSC.hg38.knownGene, get_transcriptome = FALSE,
                         write_tr2g = FALSE)
    print(head(tr2g_hs))
    write.csv(tr2g_hs, "tr2g_hs.csv", row.names = FALSE)
    
    # 6. Extract tr2g mapping from an EnsDb object using tr2g_EnsDb
    tr2g_hs86 <- tr2g_EnsDb(EnsDb.Hsapiens.v86, get_transcriptome = FALSE, 
                            write_tr2g = FALSE, gene_biotype_use = "cellranger",
                            use_gene_version = FALSE, use_transcript_version = FALSE)
    print(head(tr2g_hs86))
    write.csv(tr2g_hs86, "tr2g_hs86.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION":',
        paste0('        busparse: ', as.character(packageVersion("busparse")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_to_gene_generation.csv versions.yml
    """
}

workflow BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcriptome.fasta, annotation.gtf ] ]

    main:
    BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION(ch_input)

    emit:
    tables   = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION.out.tables
    plots    = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION.out.plots
    objects  = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION.out.objects
    versions = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_GENERATION.out.versions
}
