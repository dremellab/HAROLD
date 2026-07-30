# Lightweight container for AWS S3 transfer rule only
FROM python:3.11-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI and boto3
RUN pip install --no-cache-dir \
    awscli==1.32.* \
    boto3==1.28.* \
    botocore==1.31.*

# Set working directory
WORKDIR /project

# Default command: bash
CMD ["/bin/bash"]
