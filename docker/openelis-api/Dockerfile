# OpenELIS API Wrapper - MPL-2.0 Commercial Friendly
# This service wraps OpenELIS instrument parsing capabilities
# MPL-2.0 allows code linking, but we use REST API for consistency

FROM python:3.11-slim

LABEL maintainer="bioMate Team"
LABEL description="REST API wrapper for OpenELIS instrument parsing"
LABEL license="MIT"

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY docker/openelis-api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY lib/galaxy/instruments/openelis_client /app/openelis_client

# Create upload directory
RUN mkdir -p /uploads

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run application
CMD ["uvicorn", "openelis_client.main:app", "--host", "0.0.0.0", "--port", "8000"]
