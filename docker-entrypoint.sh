#!/usr/bin/env sh
# Multi-mode entrypoint: supports postgresql, api, or both (default)
# Set MODE environment variable to control behavior:
#   MODE=postgresql - Run only PostgreSQL (for sidecar)
#   MODE=api - Run only Node.js API (connects to PostgreSQL on localhost)
#   MODE=both (default) - Run both PostgreSQL and API in same container

set -e

MODE=${MODE:-both}

case "$MODE" in
  postgresql)
    echo "MODE=postgresql: Starting PostgreSQL only (sidecar mode)..."
    exec su-exec postgres postgres -D /var/lib/postgresql/data
    ;;

  api)
    echo "MODE=api: Starting API only (connecting to PostgreSQL at ${POSTGRES_HOST:-127.0.0.1})..."

    # Wait for PostgreSQL to be ready
    echo "Waiting for PostgreSQL to be ready..."
    timeout=60
    counter=0
    until su-exec postgres pg_isready -h ${POSTGRES_HOST:-127.0.0.1} -p ${POSTGRES_PORT:-5432} -U ${POSTGRES_USER:-postgres} > /dev/null 2>&1; do
      counter=$((counter + 1))
      if [ $counter -gt $timeout ]; then
        echo "ERROR: PostgreSQL at ${POSTGRES_HOST:-127.0.0.1}:${POSTGRES_PORT:-5432} failed to become ready within $timeout seconds"
        exit 1
      fi
      echo "PostgreSQL is unavailable - sleeping (attempt $counter/$timeout)"
      sleep 1
    done

    echo "PostgreSQL is ready! Starting API..."
    exec su-exec infracost npm run start
    ;;

  both|*)
    echo "MODE=both: Starting both PostgreSQL and API in same container..."
    su-exec postgres pg_ctl start -D /var/lib/postgresql/data
    exec su-exec infracost npm run start
    ;;
esac
