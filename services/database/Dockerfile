# Build: podman build -t hdb -f Containerfile .   (or docker build -t hdb -f Containerfile .)
# Run:   podman run -p 8080:8080 -v hdb-data:/app/data -e ADMIN_PASSWORD=... -e SYSTEM_ADMIN_PASSWORD=... hdb
FROM docker.io/dlanguage/ldc:latest AS builder
WORKDIR /workspace
COPY backend/ backend/
RUN cd backend && dub build --build=release --config=application --compiler=ldc2 \
 && dub build --build=release --config=cli --compiler=ldc2

FROM docker.io/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 ca-certificates && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /app hdb
WORKDIR /app
COPY --from=builder /workspace/backend/build/hdb /workspace/backend/build/hdb-cli /app/
COPY backend/config/ /app/config/
COPY backend/public/ /app/public/
COPY frontend/ /app/frontend/
RUN rm -rf /app/frontend/test /app/frontend/localService && mkdir -p /app/data && chown -R hdb /app/data
USER hdb
ENV FRONTEND_DIR=/app/frontend
EXPOSE 8080
VOLUME ["/app/data"]
HEALTHCHECK CMD ["/bin/sh", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /health HTTP/1.0\\r\\n\\r\\n' >&3 && grep -q UP <&3"]
CMD ["/app/hdb"]
