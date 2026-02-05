#!/usr/bin/env python3
import os, re, sys
from pathlib import Path

# --- Configuration via command-line args ---
# Usage:
#   python3 instrument_spec_tests.py /path/to/External_fpga/SPEC/CINT2006 [TIME_CMD]
# where TIME_CMD defaults to 'time'. If you use GNU time, pass 'gtime'.

if len(sys.argv) < 2:
    print("Usage: instrument_spec_tests.py BASE_DIR [TIME_CMD]", file=sys.stderr)
    print("Example: instrument_spec_tests.py /data/.../External_fpga/SPEC/CINT2006 time", file=sys.stderr)
    sys.exit(2)

BASE_DIR = Path(sys.argv[1]).resolve()
TIME_CMD = sys.argv[2] if len(sys.argv) >= 3 else "time"

if not BASE_DIR.exists():
    print(f"[ERROR] Base directory does not exist: {BASE_DIR}", file=sys.stderr)
    sys.exit(1)

print(f"[INFO] BASE_DIR={BASE_DIR}")
print(f"[INFO] TIME_CMD={TIME_CMD}")

# Pattern to find run lines that execute a binary under ${scriptdir}/APP and redirect to a file
# We capture:
#  group1: optional 'cd ... ; ' prefix
#  group2: full command starting with ${scriptdir}/APP up to before '>'
#  group3: APP name (e.g., 401.bzip2)
#  group4: output path ending in a filename with an extension (e.g., .out, .log, .sca)
#  group5: trailing text on the line (e.g., extra args after redirection)
run_line_re = re.compile(r"^\s*((?:cd [^;]+;\s*)?)(\$\{scriptdir\}/([A-Za-z0-9._-]+)\b[^>]*?)\s*>\s*([^\s;]+\.[A-Za-z0-9._-]+)(.*)$")


def instrument_file(src_path: Path, time_cmd: str) -> bool:
    """Create a sibling .test.fpga.sh from src .test.sh and instrument its run lines.
    Returns True if a file was written.
    """
    if not src_path.name.endswith('.test.sh'):
        return False
    dst_path = src_path.with_name(src_path.name.replace('.test.sh', '.test.fpga.sh'))

    try:
        text = src_path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"[WARN] Cannot read {src_path}: {e}")
        return False

    lines = text.splitlines()

    # Determine insertion index: after toolsdir= line if present
    toolsdir_idx = None
    shebang_idx = None
    for i, ln in enumerate(lines):
        if ln.strip().startswith('toolsdir=') or 'toolsdir="' in ln:
            toolsdir_idx = i
        if ln.startswith('#!') and shebang_idx is None:
            shebang_idx = i

    out_lines = lines.copy()

    def ensure_insert_after(idx: int, content: str, presence_token: str):
        nonlocal out_lines
        if any(presence_token in l for l in out_lines):
            return
        insert_at = idx + 1 if idx is not None else 0
        out_lines.insert(insert_at, content)

    # Insert headers once
    anchor = toolsdir_idx if toolsdir_idx is not None else (shebang_idx if shebang_idx is not None else -1)
    ensure_insert_after(anchor, 'export CC_DEBUG=""', 'export CC_DEBUG=')
    ensure_insert_after(anchor, f'TIME_CMD="{time_cmd}"', 'TIME_CMD=')

    apps_mkdir_emitted = set()
    new_out_lines = []

    for ln in out_lines:
        m = run_line_re.match(ln)
        if not m:
            new_out_lines.append(ln)
            continue
        cdprefix, cmdprefix, appname, outpath, tail = m.groups()
        # Derive base name from the output file (strip directories and extension)
        base_file = Path(outpath).name
        base_no_ext = base_file.rsplit('.', 1)[0]
        app_out_dir = f'${{scriptdir}}/{appname}_OUTPUT'

        if appname not in apps_mkdir_emitted:
            new_out_lines.append(f'mkdir -p {app_out_dir}')
            apps_mkdir_emitted.add(appname)

        new_cmd = (f"{cdprefix}${{TIME_CMD}} -l -o {app_out_dir}/{base_no_ext}.time "
                   f"minimal_count_stats -o {app_out_dir}/{base_no_ext}.mcs "
                   f"{cmdprefix} > {outpath}{tail}")
        new_out_lines.append(new_cmd)

    try:
        dst_path.write_text('\n'.join(new_out_lines) + '\n', encoding='utf-8')
        try:
            os.chmod(dst_path, 0o755)
        except Exception:
            pass
        print(f"[OK ] Wrote {dst_path}")
        return True
    except Exception as e:
        print(f"[ERROR] Cannot write {dst_path}: {e}")
        return False

written = 0
for dirpath, dirnames, filenames in os.walk(BASE_DIR):
    for fn in filenames:
        if fn.endswith('.test.sh'):
            src = Path(dirpath) / fn
            if instrument_file(src, TIME_CMD):
                written += 1

print(f"[SUMMARY] Instrumented files: {written}")

