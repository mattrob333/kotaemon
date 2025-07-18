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

# Add local libraries to the Python path so they can be imported
ENV PYTHONPATH="${PYTHONPATH}:/app/libs"

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
# STEP 1: Install PyTorch packages from their dedicated server. This is a critical step.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir torch==2.5.1+cpu torchvision==0.20.1+cpu torchaudio==2.5.1+cpu --index-url https://download.pytorch.org/whl/cpu

# STEP 2: Install all other dependencies from the standard PyPI using the fully pinned requirements.txt.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# --- Lite version ---
FROM base AS lite

# Clean up system packages for the lite version
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
    rm -rf ~/.cache

ENTRYPOINT ["sh", "/app/launch.sh"]


# --- Full version ---
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
    rm -rf /var/lib/apt/lists/* \
    rm -rf ~/.cache

ENTRYPOINT ["sh", "/app/launch.sh"]


# --- Ollama-bundled version ---
FROM full AS ollama

# Install ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Download the ollama model during the build
RUN nohup bash -c "ollama serve &" && sleep 4 && ollama pull nomic-embed-text

ENTRYPOINT ["sh", "/app/launch.sh"]
