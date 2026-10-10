# File previews and structured quality

The data hub opened files as DatasetObject, but its Preview tab rendered only profiler-provided table rows. JSON/YAML had neither a text-content renderer nor a structured profiler; comma-containing JSON could be misclassified as a table. This is an implementation gap.

The file preview resolves the existing permission-checked project file URL, reads at most 256 KiB of text, cancels larger streams, and displays text without executing HTML. JSON is formatted only after a complete successful parse. YAML and other supported text formats render verbatim. PNG/JPEG/GIF/WebP and PDF use native previews. Unsupported formats retain an explicit download instruction.

The backend recognizes JSON/YAML before delimiter sniffing. Files under the bounded parse limit receive syntax validation and structural counts (keys, values, null values, nesting depth). YAML safe_load and a visited-object set prevent arbitrary constructors and repeated traversal of recursive aliases. These counts replace table dimensions in Quality. Structural validity does not imply scientific quality; the panel explicitly says this.

Review expectation: authenticated JSON/YAML project files show their actual contents and structural statistics. Invalid structured files show parse failure. CSV table preview and profiling remain unchanged. A denied URL request shows an error, never a blank pane. Large text previews show a truncation notice.

Validation in progress: Python 3.9 standalone profiler tests pass (13 tests). The full API import succeeds in the repository's dependency-complete Python 3.13 venv; the default local Python 3.9 environment lacks Beaker. The full perception API import and YAML dependency check also passed in dev’s dependency-complete Python 3.9 container before deployment. Frontend typecheck passed. Full frontend suite passed: 148 suites, 1,821 tests, 7 skipped. Initial sandboxed route tests could not bind loopback sockets; the complete rerun with loopback permission passed. Deployed browser verification pending.

Interactive launcher: removed an exact duplicate session-polling effect. Availability and sessions endpoints respond on dev; the reported viewer error remains to be reproduced and is not claimed fixed.
