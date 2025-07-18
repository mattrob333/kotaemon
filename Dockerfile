# Base stage for both Lite and Full versions
FROM python:3.10-slim AS base

# Common system dependencies
RUN apt-get update -qqy && \
    apt-get install -y --no-install-recommends \
        ssh \
        git \
        gcc \
        g++ \
        poppler-utils \
        libpoppler-dev \
        unzip \
        curl \
        cargo

# Setup args for platform and architecture
ARG TARGETPLATFORM
ARG TARGETARCH

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONIOENCODING=UTF-8
ENV TARGETARCH=${TARGETARCH}

# Create working directory
WORKDIR /app

# Download pdfjs
COPY scripts/download_pdfjs.sh /app/scripts/download_pdfjs.sh
RUN chmod +x /app/scripts/download_pdfjs.sh
ENV PDFJS_PREBUILT_DIR="/app/libs/ktem/ktem/assets/prebuilt/pdfjs-dist"
RUN bash scripts/download_pdfjs.sh $PDFJS_PREBUILT_DIR

# Copy application code and requirements file first
COPY . /app
COPY launch.sh /app/launch.sh
COPY .env.example /app/.env
COPY requirements.txt .

# --- CONSOLIDATED PYTHON INSTALLATION ---
# Install all Python dependencies from the requirements file in a single step.
# This ensures pip's resolver can create a compatible environment for the full application.
# It also includes PyTorch, which is needed for the full and ollama versions.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# --- Lite version ---
# The 'lite' version is now a slimmed-down final stage that pulls from the 'base'
FROM base AS lite

# Clean up system packages for the lite version
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf ~/.cache

ENTRYPOINT ["sh", "/app/launch.sh"]


# --- Full version ---
# This stage builds on the 'base' stage which already has all python packages installed
FROM base AS full

# Install additional system dependencies needed for the 'full' version
RUN apt-get update -qqy && \
    apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-jpn \
        libsm6 \
        libxext6 \
        libreoffice \
        ffmpeg \
        libmagic-dev

# Download NLTK data required by a dependency
RUN python -c "from llama_index.core.readers.base import BaseReader"

# Clean up system packages
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf ~/.cache

ENTRYPOINT ["sh", "/app/launch.sh"]


# --- Ollama-bundled version ---
# This builds on the 'full' stage
FROM full AS ollama

# Install ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Download the ollama model during the build
RUN nohup bash -c "ollama serve &" && sleep 4 && ollama pull nomic-embed-text

ENTRYPOINT ["sh", "/app/launch.sh"]
