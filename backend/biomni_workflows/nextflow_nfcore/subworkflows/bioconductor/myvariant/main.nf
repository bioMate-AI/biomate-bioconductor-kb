#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: myvariant — myvariant_annotation_pipeline
// Annotate genomic variants from a VCF file using MyVariant.info HGVS and rsID query services, and generate an annotation report.
// Input: input.vcf, coldata.csv
// Container: 1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: S4Vectors, VariantAnnotation, myvariant
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("myvariant", "VariantAnnotation", "S4Vectors", "SummarizedExperiment")
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
    
    # Load required libraries    library(SummarizedExperiment)

    library(myvariant)
    library(VariantAnnotation)
    library(S4Vectors)
    
    # --- Read input VCF ---
    message("Reading input VCF file...")
    vcf_file <- "input.vcf"
    if (!file.exists(vcf_file)) {
      stop("Input VCF file 'input.vcf' not found.")
    }
    
    # Read VCF (using hg19 as default/recommended by myvariant docs)
    vcf <- readVcf(vcf_file, genome="hg19")
    message(sprintf("Successfully loaded VCF with %d variants.", nrow(vcf)))
    
    # --- Format HGVS IDs ---
    message("Formatting HGVS IDs...")
    hgvs_snps <- tryCatch({
      formatHgvs(vcf, variant_type="snp")
    }, error = function(e) {
      message("No SNPs formatted or error occurred: ", e\$message)
      character()
    })
    
    hgvs_indels <- tryCatch({
      formatHgvs(vcf, variant_type="indel")
    }, error = function(e) {
      message("No Indels formatted or error occurred: ", e\$message)
      character()
    })
    
    all_hgvs <- unique(c(hgvs_snps, hgvs_indels))
    all_hgvs <- all_hgvs[!is.na(all_hgvs) & all_hgvs != ""]
    
    message(sprintf("Formatted %d unique HGVS IDs.", length(all_hgvs)))
    
    # Helper to flatten/simplify DataFrame for CSV export
    simplify_df <- function(df) {
      if (nrow(df) == 0) return(data.frame())
      df_std <- as.data.frame(df)
      list_cols <- sapply(df_std, is.list)
      for (col in names(list_cols)[list_cols]) {
        df_std[[col]] <- sapply(df_std[[col]], function(x) {
          if (is.null(x)) return(NA)
          paste(as.character(unlist(x)), collapse=";")
        })
      }
      return(df_std)
    }
    
    # --- Retrieve Annotations via HGVS (getVariants) ---
    ann_df <- data.frame()
    if (length(all_hgvs) > 0) {
      message("Querying MyVariant.info using HGVS IDs...")
      # Querying key fields: CADD, dbNSFP, ClinVar
      fields_to_query <- c("cadd.phred", "cadd.consequence", "dbnsfp.genename", "clinvar.rcv.clinical_significance")
      ann_res <- tryCatch({
        getVariants(all_hgvs, fields=fields_to_query)
      }, error = function(e) {
        message("Error querying HGVS variants: ", e\$message)
        NULL
      })
    
      if (!is.null(ann_res)) {
        ann_df <- simplify_df(ann_res)
      }
    }
    
    # --- Query via rsIDs (queryVariants) ---
    rs_df <- data.frame()
    rsids <- c()
    if (!is.null(names(rowRanges(vcf)))) {
      rsids <- names(rowRanges(vcf))
    }
    rsids <- rsids[grepl("^rs[0-9]+", rsids)]
    
    if (length(rsids) == 0 && "RS" %in% colnames(info(vcf))) {
      rsids <- paste0("rs", info(vcf)\$RS)
      rsids <- rsids[grepl("^rs[0-9]+", rsids)]
    }
    rsids <- unique(rsids)
    
    if (length(rsids) > 0) {
      message(sprintf("Querying MyVariant.info for %d rsIDs...", length(rsids)))
      rs_res <- tryCatch({
        queryVariants(q=rsids, scopes="dbsnp.rsid", fields=c("wellderly.vartype", "dbsnp.flags", "clinvar.rcv.clinical_significance"))
      }, error = function(e) {
        message("Error querying rsID variants: ", e\$message)
        NULL
      })
    
      if (!is.null(rs_res)) {
        rs_df <- simplify_df(rs_res)
      }
    }
    
    # --- Write Outputs ---
    message("Writing output CSV files...")
    if (nrow(ann_df) > 0) {
      write.csv(ann_df, "hgvs_annotations.csv", row.names=FALSE)
    } else {
      write.csv(data.frame(Warning="No HGVS annotations retrieved"), "hgvs_annotations.csv", row.names=FALSE)
    }
    
    if (nrow(rs_df) > 0) {
      write.csv(rs_df, "rsid_annotations.csv", row.names=FALSE)
    } else {
      write.csv(data.frame(Warning="No rsID annotations retrieved"), "rsid_annotations.csv", row.names=FALSE)
    }
    
    # --- Generate Visualizations ---
    message("Generating summary PDF...")
    pdf("variant_summary.pdf", width=10, height=6)
    par(mfrow=c(1, 2))
    
    # Plot 1: CADD Phred score distribution
    if (nrow(ann_df) > 0 && "cadd.phred" %in% colnames(ann_df)) {
      phreds <- as.numeric(ann_df\$cadd.phred)
      phreds <- phreds[!is.na(phreds)]
      if (length(phreds) > 0) {
        hist(phreds, main="CADD Phred Scores", xlab="Phred Score", col="skyblue", border="white")
      } else {
        plot.new()
        text(0.5, 0.5, "No CADD Phred scores available", cex=1.2)
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No HGVS annotations available for plotting", cex=1.2)
    }
    
    # Plot 2: Consequence types
    if (nrow(ann_df) > 0 && "cadd.consequence" %in% colnames(ann_df)) {
      conseq <- table(ann_df\$cadd.consequence)
      conseq <- conseq[conseq > 0]
      if (length(conseq) > 0) {
        # Truncate long names for plotting
        names(conseq) <- substr(names(conseq), 1, 20)
        barplot(conseq, las=2, col="salmon", main="Variant Consequences", cex.names=0.7)
      } else {
        plot.new()
        text(0.5, 0.5, "No consequence data available", cex=1.2)
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No consequence column available", cex=1.2)
    }
    
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE":',
        paste0('    myvariant: ', as.character(packageVersion('myvariant')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_myvariant_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_MYVARIANT_MYVARIANT_ANNOTATION_PIPELINE.out.versions
}
