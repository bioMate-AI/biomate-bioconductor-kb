#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Streamer — stream_large_matrix_processing
// Stream and process large feature-by-sample matrices or identifier lists chunk-by-chunk to compute summary statistics without loading the entire file into memory
// Input: input.csv
// Container: 1.56.0--r45h01b2380_0
// R packages: GenomicAlignments, Streamer
// Bioconductor: 3.20 | R: 4.4
// Requires: Streamer
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("GenomicAlignments", "Streamer")
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
    library(Streamer)
    
    # Input file
    input_file <- "input.csv"
    
    # Output files
    output_csv <- "feature_stats.csv"
    output_pdf <- "feature_stats_plot.pdf"
    
    # Defensive check for file existence and size
    if (!file.exists(input_file) || file.info(input_file)\$size == 0) {
        write.csv(data.frame(error="Input file is empty or missing"), output_csv, row.names=FALSE)
        pdf(output_pdf)
        plot.new()
        text(0.5, 0.5, "No data available")
        dev.off()
        quit(status=0)
    }
    
    # Open connection to read header and determine structure
    con <- file(input_file, "r")
    
    # Read header
    header_line <- readLines(con, n=1)
    
    if (length(header_line) == 0 || header_line == "") {
        close(con)
        write.csv(data.frame(error="Empty header"), output_csv, row.names=FALSE)
        pdf(output_pdf)
        plot.new()
        text(0.5, 0.5, "Empty header")
        dev.off()
        quit(status=0)
    }
    
    # Parse header
    header_cols <- strsplit(header_line, ",")[[1]]
    header_cols <- gsub('^"|"\$', '', header_cols) # strip quotes
    is_matrix <- length(header_cols) > 1
    
    # Define the chunk processing function
    process_chunk <- function(lines) {
        if (length(lines) == 0) return(NULL)
        
        # Use tryCatch to handle any parsing errors on malformed lines
        res <- tryCatch({
            tc <- textConnection(lines)
            df <- read.csv(tc, header=FALSE, stringsAsFactors=FALSE)
            close(tc)
            
            if (is_matrix) {
                # Ensure we don't exceed the header length
                if (ncol(df) > length(header_cols)) {
                    df <- df[, 1:length(header_cols), drop=FALSE]
                } else if (ncol(df) < length(header_cols)) {
                    # Pad with NA if columns are missing
                    for (i in (ncol(df)+1):length(header_cols)) {
                        df[[i]] <- NA
                    }
                }
                colnames(df) <- header_cols
                
                feature_ids <- df[[1]]
                # Extract numeric matrix safely
                mat_cols <- df[, -1, drop=FALSE]
                mat_list <- lapply(mat_cols, as.numeric)
                mat <- do.call(cbind, mat_list)
                if (!is.matrix(mat)) {
                    mat <- matrix(mat, nrow=nrow(df))
                }
                
                # Compute statistics
                row_means <- rowMeans(mat, na.rm=TRUE)
                row_sds <- apply(mat, 1, sd, na.rm=TRUE)
                
                data.frame(
                    feature_id = feature_ids,
                    mean = row_means,
                    sd = row_sds,
                    stringsAsFactors = FALSE
                )
            } else {
                colnames(df) <- header_cols[1]
                data.frame(
                    feature_id = df[[1]],
                    stringsAsFactors = FALSE
                )
            }
        }, error = function(e) {
            warning("Error processing chunk: ", e\$message)
            return(NULL)
        })
        
        return(res)
    }
    
    # Reducer function to combine data frames
    reduce_fun <- function(x, y) {
        if (is.null(x)) return(y)
        if (is.null(y)) return(x)
        rbind(x, y)
    }
    
    # Create Streamer components
    # We use a chunksize of 50 to demonstrate streaming capability
    prod <- ConnectionProducer(con, chunksize=50)
    cons <- ReduceConsumer(reduce_fun, init=NULL)
    
    # Construct the Streamer pipeline
    # Streamer takes components in order: Producer -> [Functions/Transformers] -> Consumer
    stream <- Streamer(prod, process_chunk, cons)
    
    # Run the stream and yield the final reduced result
    final_result <- tryCatch({
        yield(stream)
    }, error = function(e) {
        message("Error during streaming: ", e\$message)
        NULL
    })
    
    # Clean up connection and stream
    close(stream) 
    tryCatch(close(con), error=function(e) NULL)
    
    # Check if we got any results
    if (is.null(final_result) || nrow(final_result) == 0) {
        write.csv(data.frame(error="No data processed"), output_csv, row.names=FALSE)
        pdf(output_pdf)
        plot.new()
        text(0.5, 0.5, "No data processed")
        dev.off()
        quit(status=0)
    }
    
    # Write the final results
    write.csv(final_result, output_csv, row.names=FALSE)
    
    # Generate diagnostic visualization
    pdf(output_pdf, width=8, height=6)
    if (is_matrix && "mean" %in% colnames(final_result)) {
        par(mfrow=c(1, 2))
        # Histogram of means
        hist(final_result\$mean, 
             main="Distribution of Feature Means", 
             xlab="Mean Expression", 
             col="skyblue", 
             border="white")
        
        # Scatter plot of Mean vs SD
        plot(final_result\$mean, final_result\$sd, 
             main="Mean vs Standard Deviation", 
             xlab="Mean Expression", 
             ylab="Standard Deviation (SD)", 
             pch=19, 
             col=rgb(0, 0, 0, 0.5))
        abline(h=median(final_result\$sd, na.rm=TRUE), col="red", lty=2)
    } else {
        # Single column list visualization
        plot.new()
        text(0.5, 0.6, paste("Processed", nrow(final_result), "identifiers"), cex=1.2, font=2)
        text(0.5, 0.4, "No numeric matrix columns available for plotting.", cex=1)
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING":',
        paste0('    Streamer: ', as.character(packageVersion('Streamer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stream_large_matrix_processing.csv versions.yml
    """
}

workflow BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING(ch_input)

    emit:
    tables   = BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING.out.tables
    plots    = BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING.out.plots
    objects  = BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING.out.objects
    versions = BIOC_STREAMER_STREAM_LARGE_MATRIX_PROCESSING.out.versions
}
