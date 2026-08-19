# BioMate narrow sandbox launcher — tiny image: docker CLI + python3 stdlib.
# The launcher is the ONLY app-side container with Docker access; the frontend
# (and, later, the backend) reach it over HTTP and can only run validated
# RunSpecs. See launcher.py and docs/20260818_SANDBOX_SOCKET_PROXY_HARDENING.md.
FROM docker:27-cli
RUN apk add --no-cache python3
COPY launcher.py /launcher.py
EXPOSE 8899
ENTRYPOINT ["python3", "/launcher.py"]
