#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BrowserViz — browserviz_interactive_analysis
// Perform interactive visualization and analysis of feature-by-sample data using BrowserViz websocket communication.
// Input: input.csv
// Container: 2.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BrowserViz
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BrowserViz)
    
    # ----------------------------------------------------------------------
    # Stage 1: Read and Parse Input Data Defensively
    # ----------------------------------------------------------------------
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read the input CSV file
    df <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Determine if the input is a numeric matrix or a single-column list
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      numeric_cols <- sapply(df[, -which(colnames(df) == "feature_id"), drop=FALSE], is.numeric)
      matrix_data <- as.matrix(df[, -which(colnames(df) == "feature_id"), drop=FALSE][, numeric_cols, drop=FALSE])
    } else {
      # Check if the first column contains identifiers
      if (!is.numeric(df[[1]])) {
        rownames(df) <- df[[1]]
        numeric_cols <- sapply(df[, -1, drop=FALSE], is.numeric)
        matrix_data <- as.matrix(df[, -1, drop=FALSE][, numeric_cols, drop=FALSE])
      } else {
        numeric_cols <- sapply(df, is.numeric)
        matrix_data <- as.matrix(df[, numeric_cols, drop=FALSE])
      }
    }
    
    # Compute summary statistics based on the data type
    if (ncol(matrix_data) == 0 || nrow(matrix_data) == 0) {
      # Treat as a single-column list of identifiers
      identifiers <- as.character(df[[1]])
      summary_df <- data.frame(
        Identifier = identifiers,
        Length = nchar(identifiers),
        stringsAsFactors = FALSE
      )
      is_matrix <- FALSE
    } else {
      # Treat as a numeric matrix
      row_means <- rowMeans(matrix_data, na.rm = TRUE)
      row_sds <- apply(matrix_data, 1, sd, na.rm = TRUE)
      summary_df <- data.frame(
        Feature = rownames(matrix_data),
        Mean = row_means,
        SD = row_sds,
        stringsAsFactors = FALSE
      )
      is_matrix <- TRUE
    }
    
    # Write the summary statistics to the output CSV file
    write.csv(summary_df, "summary_stats.csv", row.names = FALSE)
    
    # ----------------------------------------------------------------------
    # Stage 2: Create a Custom HTML/JS Client for BrowserViz
    # ----------------------------------------------------------------------
    # We dynamically generate a lightweight HTML/JS client that implements
    # the BrowserViz WebSocket protocol to handle standard commands.
    html_content <- '
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8"/>
    <title>BrowserViz Analysis</title>
    <script>
    window.onload = function() {
      var urlParams = new URLSearchParams(window.location.search);
      var port = urlParams.get("port");
      if (!port) {
        console.error("No port specified in URL query string.");
        return;
      }
      var ws = new WebSocket("ws://localhost:" + port);
      ws.onopen = function() {
        console.log("Connected to BrowserViz on port " + port);
      };
      ws.onclose = function() {
        console.log("Connection closed.");
      };
      ws.onerror = function(err) {
        console.error("WebSocket error:", err);
      };
      ws.onmessage = function(event) {
        var msg = JSON.parse(event.data);
        console.log("Received message:", msg);
        var responsePayload = msg.payload;
    
        if (msg.cmd === "getBrowserWindowSize") {
          responsePayload = [window.innerWidth, window.innerHeight];
        } else if (msg.cmd === "getBrowserWindowTitle") {
          responsePayload = document.title;
        } else if (msg.cmd === "setBrowserWindowTitle") {
          document.title = msg.payload;
          responsePayload = msg.payload;
        } else if (msg.cmd === "displayHTMLInDiv") {
          var divId = "bvDemoDiv";
          var htmlContent = "";
          if (typeof msg.payload === "string") {
            htmlContent = msg.payload;
          } else if (msg.payload && typeof msg.payload === "object") {
            htmlContent = msg.payload.html || "";
            divId = msg.payload.div || "bvDemoDiv";
          }
          var el = document.getElementById(divId);
          if (el) {
            el.innerHTML = htmlContent;
          }
          responsePayload = "displayed";
        }
    
        // Send response back to R
        if (msg.callback) {
          var response = {
            cmd: msg.callback,
            status: "success",
            callback: "",
            payload: responsePayload
          };
          ws.send(JSON.stringify(response));
        }
      };
    };
    </script>
    </head>
    <body>
      <h2>BrowserViz Interactive Analysis</h2>
      <div id="bvDemoDiv" style="border: 1px solid #ccc; padding: 15px; margin-top: 10px; font-family: sans-serif;">
        Waiting for data from R session...
      </div>
    </body>
    </html>
    '
    
    html_file <- tempfile(fileext = ".html")
    writeLines(html_content, html_file)
    
    # ----------------------------------------------------------------------
    # Stage 3: Initialize BrowserViz and Run Interactive Session
    # ----------------------------------------------------------------------
    session_log <- c(
      "BrowserViz Session Log",
      paste("Timestamp:", Sys.time()),
      paste("Input features processed:", nrow(summary_df))
    )
    
    # Check if a web browser is available for testing/running
    browser_available <- tryCatch({
      BrowserViz::webBrowserAvailableForTesting()
    }, error = function(e) {
      FALSE
    })
    
    if (browser_available) {
      session_log <- c(session_log, "Web browser is available. Starting BrowserViz application...")
      
      # Initialize BrowserViz application using our custom HTML client
      bvApp <- tryCatch({
        BrowserViz::BrowserViz(browserFile = html_file, quiet = TRUE)
      }, error = function(e) {
        session_log <<- c(session_log, paste("Error initializing BrowserViz:", e\$message))
        NULL
      })
      
      if (!is.null(bvApp)) {
        # Allow connection to establish
        Sys.sleep(2)
        
        # 1. Test round trip communication with a subset of the summary data
        test_data <- as.list(summary_df[1:min(5, nrow(summary_df)), ])
        json_returned <- tryCatch({
          BrowserViz::roundTripTest(bvApp, test_data)
        }, error = function(e) {
          session_log <<- c(session_log, paste("Round trip test failed:", e\$message))
          NULL
        })
        
        if (!is.null(json_returned)) {
          session_log <- c(session_log, paste("Round trip test successful. Bytes exchanged:", nchar(json_returned)))
        }
        
        # 2. Set and verify the browser window title
        tryCatch({
          BrowserViz::setBrowserWindowTitle(bvApp, "Interactive Feature Analysis")
          current_title <- BrowserViz::getBrowserWindowTitle(bvApp)
          session_log <- c(session_log, paste("Browser window title successfully set to:", current_title))
        }, error = function(e) {
          session_log <<- c(session_log, paste("Failed to set/get window title:", e\$message))
        })
        
        # 3. Query the browser window size
        tryCatch({
          win_size <- BrowserViz::getBrowserWindowSize(bvApp)
          session_log <- c(session_log, paste("Browser window size:", paste(win_size, collapse = "x")))
        }, error = function(e) {
          session_log <<- c(session_log, paste("Failed to get window size:", e\$message))
        })
        
        # 4. Format and display the summary statistics table in the browser
        html_table <- paste0(
          "<h3>Top Features Summary</h3>",
          "<table border='1' style='border-collapse: collapse; width: 100%; text-align: left;'>",
          "<tr style='background-color: #f2f2f2;'>",
          paste0("<th>", colnames(summary_df)[1], "</th>"),
          paste0("<th>", colnames(summary_df)[2], "</th>"),
          if (ncol(summary_df) > 2) paste0("<th>", colnames(summary_df)[3], "</th>") else "",
          "</tr>",
          paste(apply(summary_df[1:min(10, nrow(summary_df)), ], 1, function(row) {
            paste0(
              "<tr>",
              "<td>", row[1], "</td>",
              "<td>", if (is.numeric(row[2])) round(as.numeric(row[2]), 4) else row[2], "</td>",
              if (length(row) > 2) paste0("<td>", if (is.numeric(row[3])) round(as.numeric(row[3]), 4) else row[3], "</td>") else "",
              "</tr>"
            )
          }), collapse = ""),
          "</table>"
        )
        
        tryCatch({
          BrowserViz::displayHTMLInDiv(bvApp, html_table, "bvDemoDiv")
          session_log <- c(session_log, "HTML summary table successfully rendered in browser div 'bvDemoDiv'.")
        }, error = function(e) {
          session_log <<- c(session_log, paste("Failed to display HTML in div:", e\$message))
        })
        
        # Close the WebSocket connection cleanly
        tryCatch({
          BrowserViz::closeWebSocket(bvApp)
          session_log <- c(session_log, "WebSocket connection closed successfully.")
        }, error = function(e) {
          session_log <<- c(session_log, paste("Error closing WebSocket:", e\$message))
        })
      }
    } else {
      session_log <- c(
        session_log,
        "Web browser is NOT available for testing (headless environment or no browser found).",
        "Skipping interactive browser steps. Summary statistics have been successfully written to CSV."
      )
    }
    
    # Write the session log to file
    writeLines(session_log, "browserviz_session.log")

    writeLines(c(
        '"BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS":',
        paste0('    BrowserViz: ', as.character(packageVersion('BrowserViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_browserviz_interactive_analysis.csv versions.yml
    """
}

workflow BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS.out.tables
    plots    = BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS.out.plots
    objects  = BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS.out.objects
    versions = BIOC_BROWSERVIZ_BROWSERVIZ_INTERACTIVE_ANALYSIS.out.versions
}
