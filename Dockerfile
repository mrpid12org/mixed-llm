# Use a slim Python image for the final runtime environment
FROM python:3.11-slim-bookworm

# Set environment variables for clarity
ENV WEBUI_VERSION=0.6.23

# ✅ FIX: Install rsync, curl, and tar.
# These are essential runtime and setup dependencies.
RUN apt-get update && apt-get install -y \
    rsync \
    curl \
    tar \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# This ARG will receive the artifact URL from the GitHub Actions workflow
ARG WEBUI_ARTIFACT_URL

# Download and extract the pre-built artifact from the URL
RUN curl -L -o webui.tar.gz "${WEBUI_ARTIFACT_URL}" && \
    tar -xzvf webui.tar.gz && \
    rm webui.tar.gz

# --- Add the rest of your Dockerfile logic below ---
# For example, installing Python dependencies for the backend
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
#
# Set up the entrypoint and default command
# COPY ./entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh
#
# CMD ["tini", "--", "/entrypoint.sh"]
