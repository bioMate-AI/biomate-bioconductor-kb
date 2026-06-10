#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — salmon_import_and_summarization
// Import Salmon transcript quantifications, automatically attach metadata/ranges, and summarize to gene-level for downstream differential expression.
// Input: quant.sf, coldata
// Container: quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0
// R packages: BiocFileCache, DESeq2, devtools, edgeR, org.Dm.eg.db, SummarizedExperiment, tximeta
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0"

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
    .bm_deps <- c("BiocFileCache", "DESeq2", "devtools", "edgeR", "org.Dm.eg.db", "SummarizedExperiment", "tximeta")
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
    library(tximeta)
    library(SummarizedExperiment)
    library(org.Dm.eg.db)
    library(edgeR)
    
    # ==========================================
    # 1. Prepare sample table (coldata)
    # ==========================================
    
    # Locate and read the coldata file from the working directory
    coldata_path <- NULL
    for (f in c("coldata.csv", "coldata.tsv", "coldata")) {
      if (file.exists(f)) {
        coldata_path <- f
        break
      }
    }
    
    if (!is.null(coldata_path)) {
      message("Reading coldata from: ", coldata_path)
      if (grepl("\\\\.csv\$", coldata_path)) {
        coldata <- read.csv(coldata_path, stringsAsFactors = FALSE)
      } else if (grepl("\\\\.tsv\$", coldata_path)) {
        coldata <- read.delim(coldata_path, stringsAsFactors = FALSE)
      } else {
        coldata <- tryCatch(
          read.csv(coldata_path, stringsAsFactors = FALSE),
          error = function(e) read.table(coldata_path, header = TRUE, stringsAsFactors = FALSE)
        )
      }
    } else {
      # Fallback if coldata is missing but quant.sf is present
      if (file.exists("quant.sf")) {
        message("coldata file not found. Creating a default coldata data frame using 'quant.sf'.")
        coldata <- data.frame(files = "quant.sf", names = "sample1", condition = "A", stringsAsFactors = FALSE)
      } else {
        stop("Required input files 'coldata' and 'quant.sf' not found in the working directory.")
      }
    }
    
    # Ensure 'files' column exists and points to valid paths
    if (!"files" %in% colnames(coldata)) {
      if (file.exists("quant.sf")) {
        coldata\$files <- "quant.sf"
      } else {
        stop("The 'files' column is missing from coldata and 'quant.sf' is not in the working directory.")
      }
    } else {
      # Adjust paths if they don't exist but the files are in the working directory
      coldata\$files <- sapply(coldata\$files, function(f) {
        if (file.exists(f)) {
          return(f)
        } else if (file.exists(basename(f))) {
          return(basename(f))
        } else if (file.exists("quant.sf")) {
          return("quant.sf")
        } else {
          return(f)
        }
      })
    }
    
    # Ensure 'names' column exists
    if (!"names" %in% colnames(coldata)) {
      coldata\$names <- paste0("sample", seq_len(nrow(coldata)))
    }
    
    # ==========================================
    # 2. Link custom transcriptome
    # ==========================================
    
    # Locate GTF path in the working directory
    gtf_files <- list.files(pattern = "\\\\.gtf(\\\\.gz)?\$", ignore.case = TRUE)
    if (length(gtf_files) > 0) {
      gtfPath <- gtf_files[1]
      message("Using GTF file: ", gtfPath)
    } else {
      gtfPath <- "Drosophila_melanogaster.BDGP6.22.98.gtf.gz"
      message("GTF file not found in working directory. Defaulting path to: ", gtfPath)
    }
    
    # Locate Salmon index directory
    all_dirs <- list.dirs(recursive = FALSE)
    indexDir <- NULL
    for (d in all_dirs) {
      if (file.exists(file.path(d, "versionInfo.txt")) || file.exists(file.path(d, "header.json"))) {
        indexDir <- d
        break
      }
    }
    if (!is.null(indexDir)) {
      message("Using Salmon index directory: ", indexDir)
    } else {
      indexDir <- "Dm.BDGP6.22.98_salmon-0.14.1"
      message("Salmon index directory not found. Defaulting path to: ", indexDir)
    }
    
    fastaFTP <- c(
      "ftp://ftp.ensembl.org/pub/release-98/fasta/drosophila_melanogaster/cdna/Drosophila_melanogaster.BDGP6.22.cdna.all.fa.gz",
      "ftp://ftp.ensembl.org/pub/release-98/fasta/drosophila_melanogaster/ncrna/Drosophila_melanogaster.BDGP6.22.ncrna.fa.gz"
    )
    
    # Call makeLinkedTxome exactly as documented
    makeLinkedTxome(
      indexDir = indexDir,
      source = "LocalEnsembl",
      organism = "Drosophila melanogaster",
      release = "98",
      genome = "BDGP6.22",
      fasta = fastaFTP,
      gtf = gtfPath,
      write = FALSE
    )
    
    # ==========================================
    # 3. Import data using tximeta
    # ==========================================
    se <- tximeta(coldata)
    
    # ==========================================
    # 4. Retrieve database using retrieveDb
    # ==========================================
    edb <- retrieveDb(se)
    
    # ==========================================
    # 5. Add exons using addExons
    # ==========================================
    se.exons <- addExons(se)
    
    # ==========================================
    # 6. Summarize to gene-level
    # ==========================================
    gse <- summarizeToGene(se)
    
    # ==========================================
    # 7. Add alternative identifiers
    # ==========================================
    gse <- addIds(gse, "REFSEQ", gene = TRUE)
    
    # ==========================================
    # 8. Convert to downstream analysis objects
    # ==========================================
    y <- DGEListFromTximeta(gse)
    
    # ==========================================
    # Write Outputs
    # ==========================================
    message("Saving results...")
    saveRDS(se, "se_transcript.rds")
    saveRDS(se.exons, "se_exons.rds")
    saveRDS(gse, "gse_gene.rds")
    saveRDS(y, "dgelist.rds")
    
    # Export gene counts as CSV
    gene_counts <- assay(gse, "counts")
    write.csv(gene_counts, "gene_counts.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION":
        tximeta: \$(Rscript -e 'cat(as.character(packageVersion("tximeta")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_salmon_import_and_summarization.csv versions.yml
    """
}

workflow BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf, coldata ] ]

    main:
    BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION(ch_input)

    emit:
    tables   = BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION.out.tables
    plots    = BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION.out.plots
    objects  = BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION.out.objects
    versions = BIOC_TXIMETA_SALMON_IMPORT_AND_SUMMARIZATION.out.versions
}
