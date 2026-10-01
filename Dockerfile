# ── Stage 1: Builder ──────────────────────────────────────────────────────────
# Install dependencies in a separate stage so the final image does not
# include build tools — keeps the image smaller and cleaner.
FROM python:3.12-slim AS builder

WORKDIR /build

# Copy requirements first — Docker caches each layer, so dependency
# installation is only re-run when requirements.txt changes, not on
# every code change. Faster builds.
COPY app/requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: Final image ───────────────────────────────────────────────────────
FROM python:3.12-slim

# Run as a non-root user — standard security practice for containers.
# If something breaks out of the app layer, it cannot do much as a
# non-root user with no home directory.
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy installed packages from the builder stage
COPY --from=builder /install /usr/local

# Copy application code — set ownership to appuser so the non-root
# user can actually read and execute the files.
COPY --chown=appuser:appgroup app/ .

# Switch to non-root user
USER appuser

# Port the app listens on
EXPOSE 8000

# Health check — Docker marks the container unhealthy if this fails.
# The ALB has its own health check too, but this gives visibility
# in docker ps and the ECS console.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Start the app.
# --host 0.0.0.0 makes it listen on all interfaces (required in a container).
# --workers 1 is correct for Fargate — scale by adding tasks, not workers.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
