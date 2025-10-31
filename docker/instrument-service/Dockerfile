# Unified Instrument Service - Orchestrator
# Coordinates between SENAITE, OpenELIS, and bioMate Galaxy

FROM python:3.11-slim

LABEL maintainer="bioMate Team"
LABEL description="Unified instrument connection service for bioMate"
LABEL license="MIT"

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY docker/instrument-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY lib/galaxy/instruments/service /app/instrument_service

# Create directories
RUN mkdir -p /uploads /config

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run application
CMD ["uvicorn", "instrument_service.main:app", "--host", "0.0.0.0", "--port", "8000"]
