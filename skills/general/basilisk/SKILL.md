---
name: bioconductor-basilisk
description: Installs a self-contained conda instance that is managed by the R/Bioconductor installation machinery. This aims to provide a consistent Python environment that can be used reliably by Bioconductor packages. Functions are also provided to e
when_to_use: Use when: Developing Bioconductor packages that require a reliable, self-contained Python environment using BasiliskEnvironment to freeze dependencies.; Executing Python-based calculations (e.g., scikit-learn's TruncatedSVD) on R matrices safely in an isolated process via basiliskRun.; Managing multiple, isolated Python environments within a single R session using createLocalBasiliskEnv and basiliskRun to p. Not for: For interactive, ad-hoc Python development where you want to use your pre-existing global environment, use reticulate directly because basilisk is primarily intended for package developers to freeze dependencies.; For simple R-native tasks, use nativ
user-invocable: false
---

# basilisk

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.24.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** reticulate
- **Imports:** dir.expiry
- **Install:** `BiocManager::install("basilisk")`

## When to Use
- Developing Bioconductor packages that require a reliable, self-contained Python environment using `BasiliskEnvironment` to freeze dependencies.
- Executing Python-based calculations (e.g., `scikit-learn`'s TruncatedSVD) on R matrices safely in an isolated process via `basiliskRun`.
- Managing multiple, isolated Python environments within a single R session using `createLocalBasiliskEnv` and `basiliskRun` to prevent dependency clashes.

## When NOT to Use
- For interactive, ad-hoc Python development where you want to use your pre-existing global environment, use `reticulate` directly because `basilisk` is primarily intended for package developers to freeze dependencies.
- For simple R-native tasks, use native R implementations because provisioning custom Python virtual environments adds installation overhead.

## Data Requirements
- **Input format**: Pure R objects (e.g., matrices like `matrix(rnorm(1000), ncol=10)`) that are amenable to serialization.
- **Structure**: Variables must be explicitly passed as arguments to the function supplied to `basiliskRun`.
- **Normalization state**: Not explicitly constrained by `basilisk`; depends entirely on the downstream Python module being called.

## Key Parameters
- **envname** (no default): The unique name of the basilisk environment to create or load in `BasiliskEnvironment`.
- **pkgname** (no default): The name of the client package defining the environment in `BasiliskEnvironment`.
- **packages** (no default): A character vector of Python packages (with explicit version constraints like `"pandas==2.2.3"`) to install.
- **fun** (no default): The R function containing the Python code to execute inside the isolated environment via `basiliskRun`.
- **persist** (FALSE): Logical indicating whether to persist variables across multiple calls to `basiliskRun` by passing a `store` environment.
- **obsolete.only** (TRUE): Logical in `clearExternalDir` to remove only obsolete environments.

## Best Practices
- Always specify exact version numbers for all Python packages (e.g., `"scikit-learn==1.6.1"`) in `BasiliskEnvironment` to future-proof the installation.
- Use `basiliskStart` and `basiliskStop` (via `on.exit()`) to manage the process context when executing `basiliskRun`.
- Ensure the return value of the function passed to `basiliskRun` is a pure R object, not a `reticulate` binding or pointer to external memory.
- Explicitly import non-base R functions via their namespace (using `::`) inside the function passed to `basiliskRun`.

## Common Pitfalls
- Relying on closures capturing the R environment in which the function was defined causes failures; fix this by explicitly passing variables as arguments to the function in `basiliskRun`.
- Returning `reticulate` bindings to Python objects causes invalid pointer errors when transferred back to the parent process; fix this by returning only pure R objects.
- Deeply nested directories on Windows exceeding the 260-character file path limit cause installation to silently fail; fix this by setting the `BASILISK_EXTERNAL_DIR` environment variable to a shorter path.
- Low disk usage quotas causing incomplete installations; fix this by running `clearExternalDir` to forcibly clear obsolete environments.

## Alternatives
- **reticulate**: The underlying framework for R-to-Python interoperability, suitable for interactive use but lacks the Bioconductor-managed freezing of Python versions.
- **renv**: Manages R package dependencies and Python virtualenvs at the project level rather than the package level.
- **herper**: Manages Conda environments from R but does not isolate execution in a separate process like `basilisk`.

## Citations
- Lun A (2025). Freezing Python versions inside Bioconductor packages. Package basilisk vignette.

## References
- Homepage: https://bioconductor.org/packages/basilisk
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/basilisk/inst/doc/motivation.html
