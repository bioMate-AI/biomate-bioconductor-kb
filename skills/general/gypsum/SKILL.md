---
name: bioconductor-gypsum
description: Client for the gypsum REST API (https://gypsum.artifactdb.com), a cloud-based file store in the ArtifactDB ecosystem. This package provides functions for uploads, downloads, and various adminstrative and management tasks. Check out the docu
when_to_use: Use when: Programmatically downloading files, manifests, and summaries from the gypsum bucket using saveFile, saveVersion, fetchManifest, and fetchSummary.; Uploading files to the gypsum backend using the upload sequence: startUpload, uploadFiles, and completeUpload.; Creating new versions of existing assets efficiently by deduplicating redundant files using cloneVersion and prepareDirectoryUpload.; Validat. Not for: For general-purpose cloud storage interactions (like raw Google Cloud Storage buckets) without an ArtifactDB backend, use packages like googleCloudStorageR instead.; For downloading standard Bioconductor package source files or annotation resources, 
user-invocable: false
---

# gypsum

## When to Use
- Programmatically downloading files, manifests, and summaries from the gypsum bucket using `saveFile`, `saveVersion`, `fetchManifest`, and `fetchSummary`.
- Uploading files to the gypsum backend using the upload sequence: `startUpload`, `uploadFiles`, and `completeUpload`.
- Creating new versions of existing assets efficiently by deduplicating redundant files using `cloneVersion` and `prepareDirectoryUpload`.
- Validating metadata against the Bioconductor JSON schema prior to upload using `validateMetadata`.
- Managing project permissions, probational uploads, and quotas using `setPermissions`, `approveProbation`, and `setQuota`.

## When NOT to Use
- For general-purpose cloud storage interactions (like raw Google Cloud Storage buckets) without an ArtifactDB backend, use packages like `googleCloudStorageR` instead.
- For downloading standard Bioconductor package source files or annotation resources, use `BiocManager` or `AnnotationHub` instead.
- For local-only file management and caching without a REST API backend, use `BiocFileCache` instead.

## Data Requirements
- **Input format**: File paths, directory structures, or metadata lists formatted according to the ArtifactDB JSON schema.
- **Authentication**: Requires a GitHub OAuth token for write operations (uploads, deletions, permission changes), set via `setAccessToken`. Read operations are public.
- **Network**: Requires an active internet connection to communicate with the gypsum REST API endpoint.

## Key Parameters
- **project**: Character; the name of the project on the gypsum server.
- **asset**: Character; the specific asset within the project.
- **version**: Character; the version string of the asset to upload or download.
- **directory**: Character; local directory path containing files for upload in `startUpload` and `uploadFiles`.
- **destination**: Character; local directory path where downloaded files should be saved in `cloneVersion`.
- **links**: Data frame; used in `startUpload` to deduplicate redundant files on the backend by linking to existing files.

## Best Practices
- Wrap the upload sequence (`uploadFiles`, `completeUpload`) in a `tryCatch` block and call `abortUpload` in the error handler to clean up if the upload fails.
- Use `cloneVersion` and `prepareDirectoryUpload` to expedite the creation of new asset versions by linking unmodified files to their counterparts in the previous version.
- Always validate metadata using `validateMetadata` against the schema fetched by `fetchMetadataSchema` to ensure downstream databases can index the files.
- Check the current usage of a project using `fetchUsage` and `fetchQuota` before initiating large uploads to ensure sufficient storage space.

## Common Pitfalls
- **Unauthorized upload attempts**: Attempting to upload or modify assets without setting a valid GitHub token will fail; fix this by authenticating using `setAccessToken` or prompting the user.
- **Modifying symlinks directly**: When using `cloneVersion`, modifying a symlinked file directly will alter the linked source; fix this by deleting the symlink and replacing it with a new file before uploading.
- **Incomplete uploads**: Failing to call `completeUpload` after `uploadFiles` leaves the upload in a pending state; ensure the full upload sequence is executed.

## Alternatives
- **BiocFileCache**: Best for managing local caches of remote files without a dedicated REST API backend.
- **AnnotationHub** / **ExperimentHub**: The standard Bioconductor infrastructure for distributing curated annotation and experimental datasets.

## Citations
- Lun et al. (2024), "Interface to the gypsum REST API", Bioconductor Manual.

## References
- Homepage: https://bioconductor.org/packages/gypsum
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/gypsum/inst/doc/userguide.html
