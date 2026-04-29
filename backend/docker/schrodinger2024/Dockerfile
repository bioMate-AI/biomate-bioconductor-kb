# Schrödinger 2024 Placeholder
# Schrödinger Glide requires a Schrödinger commercial license.
# Replace with your licensed schrodinger2024:latest image before running schrodinger_glide_docking.
FROM python:3.11-slim
RUN echo '#!/usr/bin/env python3\nimport sys\nprint("ERROR: Schrödinger 2024 commercial license required.")\nprint("This workflow uses Glide docking (Schrödinger Inc.).")\nprint("Provide a licensed schrodinger2024:latest image to run this workflow.")\nsys.exit(1)' > /usr/local/bin/schrodinger_check.py
ENTRYPOINT ["python3", "/usr/local/bin/schrodinger_check.py"]
