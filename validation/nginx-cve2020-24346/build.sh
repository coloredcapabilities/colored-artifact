#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="${SCRIPT_DIR}/../ccc"
ARCH="${ARCH:-riscv64-purecap}"
CHERI_SDK="${HOME}/cheri/output/sdk"
CHERI_SYSROOT="${CHERI_SDK}/sysroot-riscv64-purecap"

# Build PCRE first (njs dependency)
if [ ! -f "${SCRIPT_DIR}/pcre-install/lib/libpcre.a" ]; then
    cd /tmp
    wget -q https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz/download -O pcre-8.45.tar.gz
    tar -xzf pcre-8.45.tar.gz
    cd pcre-8.45
    CC="${CCC} ${ARCH}" ./configure \
        --host=riscv64-unknown-freebsd \
        --enable-static --disable-shared --disable-cpp \
        --prefix="${SCRIPT_DIR}/pcre-install"
    make -j"$(nproc)" && make install
    cd /tmp && rm -rf pcre-8.45 pcre-8.45.tar.gz
fi

PCRE_DIR="${SCRIPT_DIR}/pcre-install"

# Download njs source (hg.nginx.org is decommissioned, use GitHub)
# Original hg commit b409e86fd02a corresponds to git tag 0.4.3 (vulnerable version)
if [ ! -d "${SCRIPT_DIR}/njs" ]; then
    cd /tmp
    git clone https://github.com/nginx/njs.git njs-cve2020
    cd njs-cve2020
    git checkout 0.4.3
    cd /tmp
    mv njs-cve2020 "${SCRIPT_DIR}/njs"
fi

cd "${SCRIPT_DIR}/njs"
mkdir -p build

# Patch njs_types.h for CHERI 16-byte pointers
if ! grep -q "__CHERI__" src/njs_types.h; then
    sed -i 's/#define NJS_PTR_SIZE    8/#if defined(__CHERI__)\n#define NJS_PTR_SIZE    16\n#else\n#define NJS_PTR_SIZE    8\n#endif/' src/njs_types.h
fi

# Create readline compat shim for CheriBSD libedit
mkdir -p build/editline
cat > build/editline/readline.h << 'SHIMEOF'
#ifndef _EDITLINE_READLINE_H
#define _EDITLINE_READLINE_H
#include <stdio.h>
typedef char **rl_completion_func_t(const char *, int, int);
typedef char *rl_compentry_func_t(const char *, int);
char *readline(const char *prompt);
void add_history(const char *line);
char **rl_completion_matches(const char *text, rl_compentry_func_t *entry_func);
extern rl_completion_func_t *rl_attempted_completion_function;
extern int rl_attempted_completion_over;
extern const char *rl_basic_word_break_characters;
extern int rl_completion_append_character;
#endif
SHIMEOF

# Hand-crafted config for CHERI purecap riscv64
cat > build/njs_auto_config.h << 'CFGEOF'
#define NJS_INT_SIZE  4
#define NJS_UINT_SIZE  4
#define NJS_UINTPTR_T_SIZE  16
#define NJS_SIZE_T_SIZE  8
#define NJS_OFF_T_SIZE  8
#define NJS_TIME_T_SIZE  8
#define NJS_HAVE_UNSIGNED_INT128  1
#define NJS_HAVE_BUILTIN_EXPECT  1
#define NJS_HAVE_BUILTIN_UNREACHABLE  1
#define NJS_HAVE_BUILTIN_PREFETCH  1
#define NJS_HAVE_BUILTIN_CLZ  1
#define NJS_HAVE_BUILTIN_CLZLL  1
#define NJS_HAVE_GCC_ATTRIBUTE_VISIBILITY  1
#define NJS_HAVE_GCC_ATTRIBUTE_MALLOC  1
#define NJS_HAVE_GCC_ATTRIBUTE_ALIGNED  1
#define NJS_HAVE_CLOCK_MONOTONIC  1
#define NJS_HAVE_TM_GMTOFF  1
#define NJS_HAVE_POSIX_MEMALIGN  1
#define NJS_HAVE_GETRANDOM  1
#define NJS_HAVE_EXPLICIT_BZERO  1
#define NJS_HAVE_PCRE  1
#define NJS_CLANG  1
#define NJS_HAVE_EDITLINE  1
CFGEOF

NJS_SRCS="src/njs_diyfp.c src/njs_dtoa.c src/njs_dtoa_fixed.c src/njs_strtod.c
src/njs_murmur_hash.c src/njs_djb_hash.c src/njs_utf8.c src/njs_arr.c
src/njs_rbtree.c src/njs_lvlhsh.c src/njs_trace.c src/njs_random.c
src/njs_md5.c src/njs_sha1.c src/njs_sha2.c src/njs_pcre.c src/njs_time.c
src/njs_file.c src/njs_malloc.c src/njs_mp.c src/njs_sprintf.c src/njs_utils.c
src/njs_chb.c src/njs_value.c src/njs_vm.c src/njs_vmcode.c src/njs_boolean.c
src/njs_number.c src/njs_symbol.c src/njs_string.c src/njs_object.c
src/njs_object_prop.c src/njs_array.c src/njs_json.c src/njs_function.c
src/njs_regexp.c src/njs_date.c src/njs_error.c src/njs_math.c src/njs_timer.c
src/njs_module.c src/njs_event.c src/njs_fs.c src/njs_crypto.c
src/njs_extern.c src/njs_variable.c src/njs_builtin.c src/njs_lexer.c
src/njs_lexer_keyword.c src/njs_parser.c src/njs_generator.c
src/njs_disassembler.c src/njs_array_buffer.c src/njs_typed_array.c
src/njs_promise.c src/njs_encoding.c src/njs_query_string.c src/njs_utf16.c
src/njs_shell.c"

for f in $NJS_SRCS; do
    obj="build/$(basename ${f%.c}.o)"
    ${CCC} ${ARCH} -c -pipe -fPIC -fvisibility=hidden -O -W -Wall -Wextra \
        -Wno-unused-parameter -Wwrite-strings -Wno-error -g \
        -I src -I build -I "$PCRE_DIR/include" \
        -o "$obj" "$f"
done

${CCC} ${ARCH} -o build/njs build/*.o \
    "$PCRE_DIR/lib/libpcre.a" -lm -lpthread -ledit -lncursesw

echo ""
echo "Build complete:"
file "${SCRIPT_DIR}/njs/build/njs"
