#!/bin/sh
# Galaxy container entrypoint — baked into the image at /app/start_biomate.sh.
#
# Skips deps that are pre-installed during image build:
#   --skip-wheels, --skip-eggs, --skip-venv  → Python deps in requirements.txt
#   --skip-client-build                       → no UI builds in this image
#   --skip-tool-dependency-initialization     → tool deps managed elsewhere
#
# After Gravity starts the gunicorn/celery/beat processes, we tail the supervisord
# log so the container's PID 1 stays alive (otherwise Docker would treat startup
# as complete and the container would exit even though workers are healthy).
cd /app
./run.sh \
  --skip-wheels \
  --skip-eggs \
  --skip-venv \
  --skip-client-build \
  --skip-tool-dependency-initialization \
  start
exec galaxyctl follow
