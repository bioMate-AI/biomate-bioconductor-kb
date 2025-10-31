# SENAITE API Wrapper - GPL-ISOLATED
# This service acts as a network boundary between SENAITE (GPL-2.0) and bioMate
# NO SENAITE CODE IS IMPORTED - ONLY HTTP/REST COMMUNICATION

FROM python:3.11-slim

LABEL maintainer="bioMate Team"
LABEL description="GPL-isolated REST API wrapper for SENAITE instrument parsing"
LABEL license="MIT"

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY docker/senaite-api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY lib/galaxy/instruments/senaite_client /app/senaite_client

# Create upload directory
RUN mkdir -p /uploads

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run application
CMD ["uvicorn", "senaite_client.main:app", "--host", "0.0.0.0", "--port", "8000"]
