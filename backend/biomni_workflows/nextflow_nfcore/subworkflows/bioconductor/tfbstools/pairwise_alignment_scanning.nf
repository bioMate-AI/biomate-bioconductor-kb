#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tfbstools — pairwise_alignment_scanning
// Scan a pairwise sequence alignment with a PWM to identify conserved TFBSs.
// Input: alignment_seq1.fasta, alignment_seq2.fasta
// Container: quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0
// R packages: Biostrings, JASPAR2014, TFBSTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0"

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
    .bm_deps <- c("Biostrings", "JASPAR2014", "TFBSTools")
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
    
    library(TFBSTools)
    library(JASPAR2014)
    library(Biostrings)
    
    # 1. Convert PFM to PWM
    # Query the JASPAR2014 database to retrieve the PFMatrix for MA0003.2 (TFAP2A)
    pfm <- getMatrixByID(JASPAR2014, ID="MA0003.2")
    pwm <- toPWM(pfm)
    
    # 2. Read input alignment sequences from user-provided FASTA files
    seq1_set <- readDNAStringSet("alignment_seq1.fasta")
    seq2_set <- readDNAStringSet("alignment_seq2.fasta")
    aln1 <- seq1_set[[1]]
    aln2 <- seq2_set[[1]]
    
    # 3. Scan pairwise alignment
    sitePairSet <- searchAln(pwm, aln1, aln2, seqname1="seq1", seqname2="seq2",
                             min.score="50%", cutoff=0.5,
                             strand="*", type="any")
    
    # 4. Export conserved sites to GFF and save results
    gff3_df <- writeGFF3(sitePairSet)
    gff2_df <- writeGFF2(sitePairSet)
    
    # Print heads to stdout as shown in the documented code
    print(head(gff3_df))
    print(head(gff2_df))
    
    # Write outputs to files
    write.csv(gff3_df, "sitePairSet_gff3.csv", row.names=FALSE)
    write.csv(gff2_df, "sitePairSet_gff2.csv", row.names=FALSE)
    saveRDS(sitePairSet, "sitePairSet.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING":
        tfbstools: \$(Rscript -e 'cat(as.character(packageVersion("tfbstools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_alignment_scanning.csv versions.yml
    """
}

workflow BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ alignment_seq1.fasta, alignment_seq2.fasta ] ]

    main:
    BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING(ch_input)

    emit:
    tables   = BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING.out.tables
    plots    = BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING.out.plots
    objects  = BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING.out.objects
    versions = BIOC_TFBSTOOLS_PAIRWISE_ALIGNMENT_SCANNING.out.versions
}
