#!/bin/sh
# Build asmlift's symbol-source ELF: sa3-syms.elf — a copy of the built ELF with the DWARF
# of the declarations-only sidecar TU (build/asmlift-ctx.c) merged in. asmlift reads
# names/addresses from its .symtab and declaration shapes (arrays, struct layouts, …) from
# the merged DWARF. The real build outputs are untouched.
#
# Needs a HOST arm-none-eabi toolchain (gcc + objcopy) — no Docker. Any modern version
# works: it only emits debug info, never code, so it needn't match the game's agbcc.
# -mabi=apcs-gnu is load-bearing: agbcc (gcc 2.9) follows the old APCS, which rounds every
# struct up to a word multiple — modern AAPCS does not — and the shapes must describe the
# layout agbcc actually baked into the ROM.
#
# Usage: make asmlift-elf
set -eu

cd "$(dirname "$0")/.."

[ -f sa3.elf ] || { echo "sa3.elf missing — run make first" >&2; exit 1; }
[ -f build/asmlift-ctx.c ] || { echo "build/asmlift-ctx.c missing — run 'make asmlift-elf'" >&2; exit 1; }

if ! command -v arm-none-eabi-gcc >/dev/null 2>&1 || ! command -v arm-none-eabi-objcopy >/dev/null 2>&1; then
  echo "arm-none-eabi-gcc/objcopy not found — install a host Arm GNU toolchain" >&2
  exit 1
fi

# Flags mirror the project Makefile's GBA/EUROPE configuration (the benchmarked build).
arm-none-eabi-gcc \
  -iquote include -nostdinc -I tools/agbcc/include \
  -D EUROPE -D PLATFORM_GBA=1 -D PLATFORM_SDL=0 -D PLATFORM_WIN32=0 \
  -D CPU_ARCH_X86=0 -D CPU_ARCH_ARM=1 -D DEBUG=0 \
  -std=gnu89 -mabi=apcs-gnu -w \
  -g -fno-eliminate-unused-debug-types \
  -c build/asmlift-ctx.c -o build/asmlift-ctx.o

cp sa3.elf sa3-syms.elf
for sec in .debug_info .debug_abbrev .debug_str .debug_line .debug_aranges; do
  # debug sections are non-alloc; objcopy -O binary dumps only alloc sections, so flag first
  arm-none-eabi-objcopy -O binary --only-section=$sec \
    --set-section-flags $sec=alloc build/asmlift-ctx.o build/asmlift-ctx$sec.bin
  arm-none-eabi-objcopy --add-section $sec=build/asmlift-ctx$sec.bin sa3-syms.elf
  rm -f build/asmlift-ctx$sec.bin
done

echo "built sa3-syms.elf"
