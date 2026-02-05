#!/bin/sh -xe

# PostgreSQL Benchmark with Stats Collection - Run this on the FPGA
# Collects peak RSS and timing stats for the PostgreSQL server

POSTGRES_ROOT="/tmp/riscv64-purecap/postgres"
POSTGRES_DATA="/tmp/postgres/data"
POSTGRES="${POSTGRES_ROOT}/bin/postgres"
INITDB="${POSTGRES_ROOT}/bin/initdb"
PGCTL="${POSTGRES_ROOT}/bin/pg_ctl"
CREATEDB="${POSTGRES_ROOT}/bin/createdb"
PSQL="${POSTGRES_ROOT}/bin/psql"

# Network configuration
SERVER_IP="0.0.0.0"
SERVER_PORT="5432"

# Stats output
STATS_DIR="/tmp/postgres/stats"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TIME_STATS="${STATS_DIR}/postgres_${TIMESTAMP}.time"
MCS_STATS="${STATS_DIR}/postgres_${TIMESTAMP}.mcs"

export LD_LIBRARY_PATH="${POSTGRES_ROOT}/lib"
export LD_CHERI_BIND_NOW=1

mkdir -p "${STATS_DIR}"

echo "${0}: Setting up PostgreSQL server for benchmarking..."

# Initialize database if needed
if [ -e "${POSTGRES_DATA}" ]; then
    echo "${0}: ${POSTGRES_DATA} already exists, initdb not required"
else
    echo "${0}: ${POSTGRES_DATA} does not exist, running initdb..."
    mkdir -p "$(dirname ${POSTGRES_DATA})"
    ${INITDB} -D "${POSTGRES_DATA}" --noclean --nosync --no-locale "$@"

    # Configure PostgreSQL for benchmarking
    cat >> "${POSTGRES_DATA}/postgresql.conf" << 'EOF'
# Network
listen_addresses = '*'
port = 5432

# Performance (benchmarking only - NOT for production!)
fsync = off
full_page_writes = off
synchronous_commit = off

max_parallel_workers_per_gather = 0

# Disable statistics collector
track_activities = off
track_counts = off

# Minimal connections
max_connections = 10
EOF

    # Allow password-less connections
    cat >> "${POSTGRES_DATA}/pg_hba.conf" << 'EOF'
# Allow all connections (INSECURE - for benchmarking only)
host    all    all    0.0.0.0/0    trust
host    all    all    ::/0         trust
EOF
fi

# Create pgbench database using pg_ctl temporarily
echo "${0}: Starting server temporarily to create database..."
${POSTGRES} -D "${POSTGRES_DATA}" -h ${SERVER_IP} -p ${SERVER_PORT} &
PG_PID=$!
sleep 5

# Create benchmark database
${CREATEDB} -h localhost -p ${SERVER_PORT}  pgbench 2>/dev/null || echo "Database pgbench already exists"

# Stop the temporary server
kill -TERM ${PG_PID}
wait ${PG_PID} 2>/dev/null || true

echo ""
echo "=============================================="
echo "PostgreSQL ready for benchmark with stats collection"
echo "Stats will be saved to:"
echo "  Time stats: ${TIME_STATS}"
echo "  MCS stats:  ${MCS_STATS}"
echo ""
echo "Starting server with time -l and minimal_count_stats..."
echo "=============================================="
echo ""

echo "${0}: Starting server in background with time -l and minimal_count_stats..."

# Run with time -l and minimal_count_stats in background
/usr/bin/time -l -o "${TIME_STATS}" \
    minimal_count_stats -o "${MCS_STATS}" \
    ${POSTGRES} -D "${POSTGRES_DATA}" -h ${SERVER_IP} -p ${SERVER_PORT} &

# Wait for postgres to be ready
sleep 5

echo ""
echo "=============================================="
echo "PostgreSQL server is running!"
echo ""
echo "From host (169.254.125.248), run:"
echo "  pgbench -i -h 169.254.125.247 -p ${SERVER_PORT} pgbench"
echo "  pgbench -c 1 -T 60 -h 169.254.125.247 -p ${SERVER_PORT} pgbench"
echo ""
echo "=============================================="
echo ""
echo "Press ENTER when pgbench is done to stop server and collect stats..."
read dummy

echo "${0}: Stopping postgres..."
${PGCTL} stop -w -D "${POSTGRES_DATA}"

# Wait for background process to finish and collect stats
wait

echo ""
echo "=============================================="
echo "=== Time stats (${TIME_STATS}) ==="
echo "=============================================="
cat "${TIME_STATS}"
echo ""
echo "=============================================="
echo "=== Minimal count stats (${MCS_STATS}) ==="
echo "=============================================="
cat "${MCS_STATS}"
