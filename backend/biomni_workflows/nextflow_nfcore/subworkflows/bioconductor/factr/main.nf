#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: factr — custom_transcriptome_annotation
// Perform functional annotation of a custom-assembled transcriptome by matching gene metadata, filtering for novel transcripts, predicting coding sequences, and a
// Input: custom_assembled_transcriptome.gtf, reference_transcriptome.gtf, genome_sequence
// Container: quay.io/biocontainers/bioconductor-factr:1.8.0--r44hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-factr:1.8.0--r44hdfd78af_0"

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
    .bm_deps <- c("annotationhub", "biostrings", "factr", "genomicfeatures", "lines", "rtracklayer", "tidyverse")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(factR)
    library(rtracklayer)
    
    # 1. Import custom GTF using importGTF
    custom_gtf_path <- "custom_assembled_transcriptome.gtf"
    if (!file.exists(custom_gtf_path)) {
      stop("Required input file 'custom_assembled_transcriptome.gtf' not found in the working directory.")
    }
    custom.gtf <- importGTF(custom_gtf_path)
    
    # Import reference GTF
    ref_gtf_path <- "reference_transcriptome.gtf"
    if (!file.exists(ref_gtf_path)) {
      stop("Required input file 'reference_transcriptome.gtf' not found in the working directory.")
    }
    ref.gtf <- importGTF(ref_gtf_path)
    
    # Load genome sequence
    genome_file <- "genome_sequence"
    if (!file.exists(genome_file)) {
      stop("Required input file 'genome_sequence' not found in the working directory.")
    }
    
    # Robustly load the genome sequence (handles RDS, BSgenome package name, 2bit, or FASTA)
    Mmusculus <- tryCatch({
      # Try reading as RDS (serialized BSgenome or DNAStringSet object)
      readRDS(genome_file)
    }, error = function(e) {
      tryCatch({
        # Check if it's a text file containing a BSgenome package name
        lines <- readLines(genome_file, n = 1, warn = FALSE)
        if (length(lines) > 0 && grepl("^BSgenome\\.", lines)) {
          library(lines, character.only = TRUE)
          get(lines)
        } else {
          stop("Not a BSgenome package name")
        }
      }, error = function(e2) {
        tryCatch({
          # Try loading as 2bit file
          if (grepl("\\.2bit\$", genome_file, ignore.case = TRUE)) {
            rtracklayer::TwoBitFile(genome_file)
          } else {
            factR::importFASTA(genome_file)
          }
        }, error = function(e3) {
          # Fallback to importFASTA
          factR::importFASTA(genome_file)
        })
      })
    })
    
    # 2. Match gene metadata to reference using matchGeneInfo
    custom_matched_2.gtf <- matchGeneInfo(custom.gtf, ref.gtf, primary_gene_id = "gene_id", secondary_gene_id = "ref_gene_id")
    
    # 3. Subset novel transcripts using subsetNewTranscripts
    custom_new.gtf <- subsetNewTranscripts(custom_matched_2.gtf, ref.gtf, refine.by = "intron")
    
    # 4. Build CDS information using buildCDS and a genome sequence
    custom_new_CDS.gtf <- buildCDS(custom_new.gtf, ref.gtf, Mmusculus)
    
    # 5. Predict NMD susceptibility using predictNMD
    NMDprediction.out <- predictNMD(custom_new_CDS.gtf)
    
    # 6. Predict protein domains using predictDomains
    # Wrapped in tryCatch as it requires an active internet connection to query the PFAM database
    domains.out <- tryCatch({
      predictDomains(custom_new_CDS.gtf, Mmusculus, progress_bar = FALSE)
    }, error = function(e) {
      warning("predictDomains failed (possibly due to network or PFAM server issues): ", e\$message)
      NULL
    })
    
    # 7. Export annotated GTF and prediction tables using rtracklayer::export and write.table
    rtracklayer::export(custom_new_CDS.gtf, "Custom_new.gtf", format = "GTF")
    
    write.table(NMDprediction.out, "Custom_new_NMD.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    if (!is.null(domains.out)) {
      write.table(domains.out, "Custom_new_domains.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    } else {
      # Write a placeholder file if domain prediction failed to ensure output file exists
      write.table(data.frame(Message = "Domain prediction failed or was skipped due to connectivity issues"), 
                  "Custom_new_domains.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION":
        factr: \$(Rscript -e 'cat(as.character(packageVersion("factr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_transcriptome_annotation.csv versions.yml
    """
}

workflow BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ custom_assembled_transcriptome.gtf, reference_transcriptome.gtf, genome_sequence ] ]

    main:
    BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION.out.tables
    plots    = BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION.out.plots
    objects  = BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION.out.objects
    versions = BIOC_FACTR_CUSTOM_TRANSCRIPTOME_ANNOTATION.out.versions
}
