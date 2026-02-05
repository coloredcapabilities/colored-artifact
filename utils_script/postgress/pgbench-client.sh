#!/bin/sh -xe

# pgbench Client Script - Run this on the HOST machine (169.254.125.248)
# This connects to PostgreSQL server on FPGA and runs benchmarks
#
# Usage: ./pgbench-client.sh <experiment_name>
# Example: ./pgbench-client.sh baseline
#
# Results will be saved to: cheri/Colored_Artifact/postgres/results/<experiment_name>/

# Check for required argument
if [ -z "$1" ]; then
    echo "Usage: $0 <experiment_name>"
    echo "Example: $0 baseline"
    exit 1
fi

EXPERIMENT_NAME="$1"

# Network configuration
# FPGA Server: 169.254.125.247 (PostgreSQL)
# Host Client: 169.254.125.248 (this machine running pgbench)

SERVER_HOST="${PGHOST:-169.254.125.247}"    # FPGA PostgreSQL server
SERVER_PORT="${PGPORT:-5432}"
DATABASE="${PGDATABASE:-pgbench}"
USERNAME="${PGUSER:-root}"

# Benchmark parameters
CLIENTS="${PGBENCH_CLIENTS:-1}"      # Number of concurrent clients
DURATION="${PGBENCH_DURATION:-60}"   # Duration in seconds
NTIMES=4                              # Fixed: run 4 times

# Path to pgbench (adjust if needed)
PGBENCH=pgbench

# Create results directory
RESULTS_DIR="/cheri/Colored_Artifact/postgres/results/${EXPERIMENT_NAME}"
mkdir -p "${RESULTS_DIR}"

echo "=============================================="
echo "pgbench Client Configuration:"
echo "  Server:      ${SERVER_HOST}:${SERVER_PORT}"
echo "  Database:    ${DATABASE}"
echo "  Username:    ${USERNAME}"
echo "  Clients:     ${CLIENTS}"
echo "  Duration:    ${DURATION}s per run"
echo "  Runs:        ${NTIMES}"
echo "  Experiment:  ${EXPERIMENT_NAME}"
echo "  Results dir: ${RESULTS_DIR}"
echo "=============================================="

# # Test connection first
# echo "${0}: Testing connection to server..."
# if ! ${PGBENCH} -h "${SERVER_HOST}" -p "${SERVER_PORT}" -U "${USERNAME}" -c 1 -t 1 "${DATABASE}" 2>/dev/null; then
#     echo "ERROR: Cannot connect to PostgreSQL server at ${SERVER_HOST}:${SERVER_PORT}"
#     echo ""
#     echo "Make sure:"
#     echo "  1. PostgreSQL is running on the server"
#     echo "  2. Server is listening on ${SERVER_HOST}:${SERVER_PORT}"
#     echo "  3. Network connectivity exists between client and server"
#     echo "  4. pg_hba.conf allows connections from this client"
#     exit 1
# fi

# Initialize pgbench tables (only needed once)
# Check if pgbench_accounts table exists to determine if already initialized
echo "${0}: Checking if database is already initialized..."
if psql -h "${SERVER_HOST}" -p "${SERVER_PORT}" -U "${USERNAME}" -d "${DATABASE}" -c "SELECT 1 FROM pgbench_accounts LIMIT 1;" >/dev/null 2>&1; then
    echo "${0}: Database already initialized, skipping initialization."
else
    echo "${0}: Initializing pgbench tables..."
    ${PGBENCH} -i -h "${SERVER_HOST}" -p "${SERVER_PORT}" -U "${USERNAME}" -s 10 "${DATABASE}"
fi

# Run benchmarks
echo "${0}: Running benchmark ${NTIMES} times..."
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SUMMARY_FILE="${RESULTS_DIR}/summary-${TIMESTAMP}.txt"

# Save configuration to results directory
cat > "${RESULTS_DIR}/config-${TIMESTAMP}.txt" << EOF
Experiment: ${EXPERIMENT_NAME}
Timestamp: ${TIMESTAMP}
Server: ${SERVER_HOST}:${SERVER_PORT}
Database: ${DATABASE}
Username: ${USERNAME}
Clients: ${CLIENTS}
Duration: ${DURATION}s
Runs: ${NTIMES}
EOF

for i in $(seq 1 ${NTIMES}); do
    echo ""
    echo "=== Run $i of ${NTIMES} ==="
    RUN_FILE="${RESULTS_DIR}/run-${i}-${TIMESTAMP}.txt"
    LOG_PREFIX="${RESULTS_DIR}/pgbench-log-run${i}"

    pgbench -c "${CLIENTS}" -t 1000 -l --log-prefix="${LOG_PREFIX}" -j 4 -h "${SERVER_HOST}" -p "${SERVER_PORT}" -U "${USERNAME}" "${DATABASE}" 2>&1 | tee "${RUN_FILE}" | tee -a "${SUMMARY_FILE}"
done

echo ""
echo "=============================================="
echo "Benchmark complete!"
echo "Results saved to: ${RESULTS_DIR}/"
echo "  - Summary:    ${SUMMARY_FILE}"
echo "  - Config:     ${RESULTS_DIR}/config-${TIMESTAMP}.txt"
echo "  - Run files:  ${RESULTS_DIR}/run-*-${TIMESTAMP}.txt"
echo "  - Log files:  ${RESULTS_DIR}/pgbench-log-run*"
echo "=============================================="
