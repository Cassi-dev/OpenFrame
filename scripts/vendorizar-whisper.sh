#!/bin/bash
# Copia o whisper.cpp (e o ggml) para Sources/CWhisper, o alvo C/C++ do SwiftPM das legendas
# automáticas. Só os arquivos usados no Mac entram: CPU (Accelerate), BLAS (Accelerate) e Metal.
#
#   ./scripts/vendorizar-whisper.sh            # baixa a versão fixada abaixo
#   ./scripts/vendorizar-whisper.sh <pasta>    # usa um checkout local já na versão certa
#
# Não há compilador `metal` nas Command Line Tools: os shaders entram como texto num .c gerado
# (GGML_METAL_EMBED_LIBRARY) e o Metal os compila quando o app roda.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=v1.9.5
COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037
REPO=https://github.com/ggml-org/whisper.cpp

SRC=${1:-}
if [ -z "$SRC" ]; then
    SRC=$(mktemp -d)/whisper.cpp
    git clone -q --depth 1 --branch "$TAG" "$REPO" "$SRC"
fi
GOT=$(git -C "$SRC" rev-parse HEAD)
[ "$GOT" = "$COMMIT" ] || { echo "Esperava $COMMIT ($TAG), achei $GOT" >&2; exit 1; }

DST=Sources/CWhisper
rm -rf "$DST"
mkdir -p "$DST/include" "$DST/whisper" "$DST/ggml/src/ggml-cpu/arch" "$DST/ggml/src/ggml-metal" "$DST/ggml/src/ggml-blas"

# Cabeçalhos públicos (o module.modulemap expõe só o whisper.h ao Swift).
cp "$SRC"/include/whisper.h "$DST/include/"
for h in ggml.h ggml-cpu.h ggml-backend.h ggml-alloc.h ggml-cpp.h ggml-opt.h gguf.h ggml-metal.h ggml-blas.h; do
    cp "$SRC/ggml/include/$h" "$DST/include/"
done
cat > "$DST/include/module.modulemap" <<'EOF'
module CWhisper {
    header "whisper.h"
    export *
}
EOF

cp "$SRC"/src/whisper.cpp "$SRC"/src/whisper-arch.h "$DST/whisper/"
# O whisper.cpp sempre compila o encoder do ANEForge (só é usado com ANEFORGE_ENCODER definido).
cp -R "$SRC/src/aneforge" "$DST/whisper/"

# ggml: base, registro dos backends.
G="$SRC/ggml/src"
for f in ggml.c ggml.cpp ggml-alloc.c ggml-backend.cpp ggml-backend-meta.cpp ggml-opt.cpp ggml-threading.cpp \
         ggml-threading.h ggml-quants.c ggml-quants.h gguf.cpp ggml-backend-reg.cpp ggml-backend-dl.cpp \
         ggml-backend-dl.h ggml-backend-impl.h ggml-common.h ggml-impl.h ggml-feats.h; do
    cp "$G/$f" "$DST/ggml/src/"
done
VERSION=$(sed -n 's/.*set(GGML_VERSION_MAJOR \([0-9]*\)).*/\1/p' "$SRC/ggml/CMakeLists.txt").$(sed -n 's/.*set(GGML_VERSION_MINOR \([0-9]*\)).*/\1/p' "$SRC/ggml/CMakeLists.txt").$(sed -n 's/.*set(GGML_VERSION_PATCH \([0-9]*\)).*/\1/p' "$SRC/ggml/CMakeLists.txt")
cat > "$DST/ggml/src/ggml-version.h" <<EOF
#pragma once

#define GGML_VERSION "$VERSION"
#define GGML_COMMIT  "${COMMIT:0:8}"
EOF

# CPU: os arquivos de cada arquitetura entram por envoltórios (o SwiftPM compila tudo da pasta
# nas duas arquiteturas; cada envoltório escolhe a sua pelo compilador).
C="$G/ggml-cpu"
for f in ggml-cpu.c ggml-cpu.cpp repack.cpp repack.h hbm.cpp hbm.h quants.c quants.h traits.cpp traits.h \
         ggml-cpu-impl.h common.h binary-ops.h binary-ops.cpp unary-ops.h unary-ops.cpp simd-mappings.h \
         simd-gemm.h vec.h vec.cpp ops.h ops.cpp arch-fallback.h; do
    cp "$C/$f" "$DST/ggml/src/ggml-cpu/"
done
cp -R "$C/amx" "$C/tiled" "$DST/ggml/src/ggml-cpu/"
cp -R "$C/arch/arm" "$C/arch/x86" "$DST/ggml/src/ggml-cpu/arch/"
rm -f "$DST"/ggml/src/ggml-cpu/arch/*/cpu-feats.cpp
for f in quants.c repack.cpp; do
    cat > "$DST/ggml/src/ggml-cpu/arch-${f}" <<EOF
// Gerado por scripts/vendorizar-whisper.sh: escolhe a implementação da arquitetura compilada.
#if defined(__aarch64__)
#include "arch/arm/${f}"
#elif defined(__x86_64__)
#include "arch/x86/${f}"
#endif
EOF
done

# BLAS do Accelerate.
cp "$G/ggml-blas/ggml-blas.cpp" "$DST/ggml/src/ggml-blas/"

# Metal, com os shaders embutidos.
M="$G/ggml-metal"
cp "$M"/*.cpp "$M"/*.m "$M"/*.h "$DST/ggml/src/ggml-metal/"
python3 - "$M" "$G/ggml-common.h" "$DST/ggml/src/ggml-metal/ggml-metal-embed.c" <<'PY'
import os, re, sys
metal_dir, common_h, out = sys.argv[1:]
cmake = open(os.path.join(metal_dir, "CMakeLists.txt")).read()
block = re.search(r"set\(METALLIB_KERNEL_SOURCES(.*?)\)", cmake, re.S).group(1)
kinds = re.findall(r"kernels/([A-Za-z0-9_\-]+)\.metal", block)
k = os.path.join(metal_dir, "kernels")
read = lambda p: open(p, encoding="utf-8").read()

def source(kind):
    # Mesmos passos do CMake (GGML_METAL_EMBED_LIBRARY): cabeçalhos comuns + kernel, sem os
    # #include internos, com ggml-common.h e ggml-metal-impl.h colados no lugar.
    src = read(os.path.join(k, kind + ".metal"))
    parts = [os.path.join(k, "common.h")]
    if '#include "dequantize.h"' in src: parts.append(os.path.join(k, "dequantize.h"))
    if '#include "quantize.h"' in src: parts.append(os.path.join(k, "quantize.h"))
    if '#include "fa_common.metal"' in src: parts.append(os.path.join(k, "fa_common.metal"))
    if '#include "fa_vec_common.metal"' in src: parts.append(os.path.join(k, "fa_vec_common.metal"))
    text = "".join(read(p) for p in parts) + src
    drop = ['#include "common.h"', '#include "dequantize.h"', '#include "quantize.h"',
            '#include "fa_common.metal"', '#include "fa_vec_common.metal"', '#pragma once']
    lines = []
    for line in text.splitlines(keepends=True):
        if any(d in line for d in drop):
            continue
        if "__embed_ggml-common.h__" in line:
            lines.append(read(common_h))
            continue
        if '#include "ggml-metal-impl.h"' in line:
            lines.append(read(os.path.join(metal_dir, "ggml-metal-impl.h")))
            continue
        lines.append(line)
    return "".join(lines)

def asm_string(data):
    out = []
    for b in data:
        c = chr(b)
        if c == '"': out.append('\\\\\\"')
        elif c == '\\': out.append('\\\\\\\\')
        elif c == '\n': out.append('\\\\n')
        elif c == '\t': out.append('\\\\t')
        elif 32 <= b < 127: out.append(c)
        else: out.append('\\\\%03o' % b)
    return "".join(out)

with open(out, "w") as f:
    f.write("// Gerado por scripts/vendorizar-whisper.sh a partir de ggml/src/ggml-metal/kernels.\n")
    f.write("// Código-fonte dos shaders Metal, compilado pelo Metal quando o app roda (não há compilador\n")
    f.write("// `metal` nas Command Line Tools). Símbolos ggml_metallib_<tipo>_start/_end, como os do CMake.\n\n")
    for kind in kinds:
        sym = kind.replace("-", "_")
        data = source(kind).encode("utf-8")
        f.write('__asm__(\n    ".section __DATA,__ggml_metallib\\n"\n')
        f.write(f'    ".globl _ggml_metallib_{sym}_start\\n"\n    "_ggml_metallib_{sym}_start:\\n"\n')
        for line in data.splitlines(keepends=True):
            f.write(f'    ".ascii \\"{asm_string(line)}\\"\\n"\n')
        f.write(f'    ".globl _ggml_metallib_{sym}_end\\n"\n    "_ggml_metallib_{sym}_end:\\n"\n')
        f.write('    ".byte 0\\n"\n    ".text\\n");\n\n')
print(f"{len(kinds)} bibliotecas Metal embutidas")
PY

cp "$SRC/LICENSE" "$DST/LICENSE"
cat > "$DST/VERSAO.md" <<EOF
# whisper.cpp vendorizado

- Origem: $REPO
- Versão: $TAG (commit $COMMIT)
- Licença: MIT (LICENSE nesta pasta), compatível com a GPL do OpenFrame.
- Gerado por \`scripts/vendorizar-whisper.sh\`. Não edite à mão: rode o script de novo.
- Só entram os arquivos usados no Mac: whisper, ggml (base), CPU (com Accelerate), BLAS (Accelerate) e
  Metal, com os shaders embutidos em \`ggml/src/ggml-metal/ggml-metal-embed.c\`.
- Os arquivos de \`ggml/src/ggml-cpu/arch\` entram pelos envoltórios \`arch-quants.c\` e \`arch-repack.cpp\`.
EOF
echo "Pronto: $DST ($TAG)"
