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
# The sidecar always supplies MACRO names (agbcc cannot emit macro info at all), and supplies
# the type DWARF too whenever the build itself did not — see the graft below. -g3 records macro definitions;
# -gdwarf-2 -gstrict-dwarf emits them as ONE self-contained .debug_macinfo with inline strings,
# where DWARF-5 .debug_macro would split across COMDAT groups and reference .debug_str —
# neither of which survives a section graft. Kept separate so the type DWARF above is
# byte-for-byte the same as before this was added.
arm-none-eabi-gcc \
  -iquote include -nostdinc -I tools/agbcc/include \
  -D EUROPE -D PLATFORM_GBA=1 -D PLATFORM_SDL=0 -D PLATFORM_WIN32=0 \
  -D CPU_ARCH_X86=0 -D CPU_ARCH_ARM=1 -D DEBUG=0 \
  -std=gnu89 -mabi=apcs-gnu -w \
  -gdwarf-2 -g3 -gstrict-dwarf \
  -c build/asmlift-ctx.c -o build/asmlift-ctx-macros.o

cp sa3.elf sa3-syms.elf

# The type DWARF is grafted ONLY when the build did not already produce its own
# (ASMLIFT_DINFO=1, see the Makefile). Adding a second .debug_info would duplicate a section
# name a reader resolves first-wins, silently shadowing the richer agbcc DWARF; omitting it
# when agbcc emitted none would leave the map with no declaration shapes at all.
if LC_ALL=C grep -q '\.debug_info' sa3.elf; then
  echo "sa3.elf carries its own DWARF — grafting the macro table only"
else
  for sec in .debug_info .debug_abbrev .debug_str .debug_line .debug_aranges; do
    arm-none-eabi-objcopy -O binary --only-section=$sec \
      --set-section-flags $sec=alloc build/asmlift-ctx.o build/asmlift-ctx$sec.bin
    arm-none-eabi-objcopy --add-section $sec=build/asmlift-ctx$sec.bin sa3-syms.elf
    rm -f build/asmlift-ctx$sec.bin
  done
fi
# debug sections are non-alloc; objcopy -O binary dumps only alloc sections, so flag first
arm-none-eabi-objcopy -O binary --only-section=.debug_macinfo \
  --set-section-flags .debug_macinfo=alloc build/asmlift-ctx-macros.o build/asmlift-ctx.macinfo.bin
arm-none-eabi-objcopy --add-section .debug_macinfo=build/asmlift-ctx.macinfo.bin sa3-syms.elf
rm -f build/asmlift-ctx.macinfo.bin

echo "built sa3-syms.elf"
