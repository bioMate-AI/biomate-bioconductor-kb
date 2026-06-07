---
name: bioconductor-experimenthub
description: This package provides a client for the Bioconductor ExperimentHub web resource. ExperimentHub provides a central location where curated data from experiments, publications or training courses can be accessed. Each resource has associated me
when_to_use: Use when: Accessing Curated Datasets: Retrieving large files of curated data from experiments, publications, or training courses via the ExperimentHub web service.; Retrieving R Objects: Downloading specific R data objects like SummarizedExperiment, ExpressionSet, or GAlignmentPairs directly into your session.; Interactive Exploration: Interactively querying and exploring available resources using BiocHubsS. Not for: For accessing reference genome annotations, use AnnotationHub because ExperimentHub is focused exclusively on experimental data.
user-invocable: false
---

# ExperimentHub

## When to Use
- **Accessing Curated Datasets**: Retrieving large files of curated data from experiments, publications, or training courses via the `ExperimentHub` web service.
- **Retrieving R Objects**: Downloading specific R data objects like `SummarizedExperiment`, `ExpressionSet`, or `GAlignmentPairs` directly into your session.
- **Interactive Exploration**: Interactively querying and exploring available resources using `BiocHubsShiny`.

## When NOT to Use
- For accessing reference genome annotations, use `AnnotationHub` because `ExperimentHub` is focused exclusively on experimental data.

## Data Requirements
- Requires an internet connection to download files initially, which are then cached locally.
- Queries use string terms (e.g., "mus musculus" or "alpineData").

## Key Parameters
- **localHub**: Set to `TRUE` in `ExperimentHub` to use only the local cache and avoid internet queries.
- **ask**: Set to `FALSE` in `removeCache` to bypass interactive prompts when deleting the cache.
- **appname**: Used in `rappdirs::user_cache_dir` to specify the package name (e.g., "ExperimentHub").
- **which**: Used in `tools::R_user_dir` to specify the directory type (e.g., "cache").

## Best Practices
- Use `query` to search for specific strings and filter the `ExperimentHub` object before downloading.
- Check `snapshotDate` and use `possibleDates` to ensure reproducibility with older versions of a snapshot.
- Manage the default caching location using `tools::R_user_dir` or by setting the `EXPERIMENT_HUB_CACHE` environment variable.

## Common Pitfalls
- **Proxy Issues**: Operating behind a proxy blocks downloads; fix by setting the `EXPERIMENT_HUB_PROXY` environment variable or using `setExperimentHubOption`.
- **Permission Errors**: Sharing a cache across multiple users causes access failures; fix by changing the group permissions of `BiocFileCache.sqlite` and `BiocFileCache.sqlite.LOCK` to `g+rw`.
- **Lost Cache**: Upgrading to newer versions changes the default cache location; fix by moving files to the new `tools::R_user_dir` location or setting `EXPERIMENT_HUB_CACHE`.

## Alternatives
- **AnnotationHub**: For retrieving annotation resources rather than experiment data.
- **BiocHubsShiny**: For a graphical interface to perform the same queries interactively.

## Citations
- ExperimentHub Package Authors. ExperimentHub: Access the ExperimentHub Web Service. Bioconductor.

## References
- Homepage: https://bioconductor.org/packages/ExperimentHub
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/ExperimentHub/inst/doc/ExperimentHub.html
