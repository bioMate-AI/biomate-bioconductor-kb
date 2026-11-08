"""Task images an nf-core pipeline declares that cannot run on BioMate's AWS Batch setup as published, with the rebuilt image the executor substitutes (per process, via withName). Built by scripts/build_nfcore_compat_images.sh from infra/nfcore-compat/Dockerfile.<fix>. Each entry carries its evidence; drop an entry once upstream fixes the image.

A Python module (not JSON) because scripts/sync_to_dev.sh deploys backend/lib *.py files only.
"""

REPOSITORY = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/nfcore-compat'

IMAGES = [{'source': 'docker.io/quirinmanz/biopax-validator:6.0.0-SNAPSHOT',
  'fix': 'alpine-glibc',
  'tag': 'biopax-validator-6.0.0-SNAPSHOT-glibc',
  'uses': [{'pipeline': 'diseasemodulediscovery', 'process': 'BIOPAX_VALIDATOR'}],
  'evidence': "Alpine (musl) image: Batch's host-mounted AWS CLI v2 (glibc) fails 'cannot execute: required "
              "file not found' (test profile, 2026-11-06). gcompat is not enough (dladdr1); glibc 2.35 + a "
              "glibc libz in /usr/glibc-compat/lib runs the CLI while the image's musl Java keeps working."},
 {'source': 'docker.io/cellprofiler/cellprofiler:3.1.9',
  'fix': 'clear-entrypoint',
  'tag': 'cellprofiler-3.1.9-noentry',
  'uses': [{'pipeline': 'imcyto', 'process': 'PREPROCESS_FULL_STACK'},
           {'pipeline': 'imcyto', 'process': 'PREPROCESS_ILASTIK_STACK'},
           {'pipeline': 'imcyto', 'process': 'SEGMENTATION'},
           {'pipeline': 'imcyto', 'process': 'get_software_versions'}],
  'evidence': 'ENTRYPOINT ["/init","cellprofiler"]: AWS Batch runs the image entrypoint, so CellProfiler ran '
              "instead of the task script ('You must specify a pipeline filename to run', test profile "
              '2026-11-06).'}]
