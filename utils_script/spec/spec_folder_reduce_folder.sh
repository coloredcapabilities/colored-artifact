
#!/bin/sh
set -eu

# Base directory (adjust if needed)
BASE_DIR="$HOME/cheri/build/spec2006-riscv64-purecap-build"

SRC="${BASE_DIR}/External"
DST="${BASE_DIR}/External_fpga"

echo "[INFO] Source:      ${SRC}"
echo "[INFO] Destination: ${DST}"

# 1) Sanity checks
if [ ! -d "${SRC}" ]; then
  echo "[ERROR] Source directory not found: ${SRC}" >&2
  exit 1
fi

# 2) Create a fresh copy of External -> External_fpga
#    Use rsync to preserve permissions, links, times, and be efficient.
#    If you prefer cp: cp -a "${SRC}" "${DST}"
if [ -d "${DST}" ]; then
  echo "[WARN] Destination already exists. Re-creating..."
  rm -rf "${DST}"
fi

# Copy (trailing slash on SRC/External is important to copy contents into DST)
rsync -a --delete "${SRC}/" "${DST}/"
echo "[INFO] Copy completed."

# 3) Remove selected data/ref directories from the *copied* tree
TO_DELETE="
${DST}/SPEC/CINT2006/483.xalancbmk/data/ref
${DST}/SPEC/CINT2006/483.xalancbmk/CMakeFiles
${DST}/SPEC/CINT2006/401.bzip2/data/ref
${DST}/SPEC/CINT2006/401.bzip2/CMakeFiles
${DST}/SPEC/CINT2006/464.h264ref/data/ref
${DST}/SPEC/CINT2006/456.hmmer/data/ref
${DST}/SPEC/CINT2006/456.hmmer/CMakeFiles
${DST}/SPEC/CINT2006/403.gcc/data/ref
${DST}/SPEC/CINT2006/403.gcc/CMakeFiles
${DST}/SPEC/CINT2006/400.perlbench/CMakeFiles
${DST}/SPEC/CINT2006/445.gobmk/CMakeFiles
${DST}/SPEC/CINT2006/458.sjeng/CMakeFiles
"

echo "[INFO] Deleting selected data/ref directories in ${DST}:"
for d in ${TO_DELETE}; do
  if [ -d "${d}" ]; then
    echo "  - rm -rf ${d}"
    rm -rf "${d}"
  else
    echo "  - [SKIP] Not found: ${d}"
  fi
done

echo "[DONE] External_fpga prepared at: ${DST}"
