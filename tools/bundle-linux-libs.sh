#!/usr/bin/env bash
#
# Copies the shared libraries the app needs but a plain desktop install does not
# already carry into the bundle, then points every library in the bundle at its
# own directory so the copies are the ones that get loaded.
#
# Without this the tray plugin drags in the ayatana and dbusmenu stack, which
# ubuntu has and fedora, arch and opensuse do not.

set -euo pipefail
shopt -s nullglob

bundle=${1:?usage: bundle-linux-libs.sh <bundle directory>}
libs="$bundle/lib"

if [ ! -d "$libs" ]; then
  echo "there is no lib directory under $bundle" >&2
  exit 1
fi

# Part of every desktop already, and taking our own copy would fight the system
# gtk stack rather than help.
system_libraries="
ld-linux ld-linux-x86-64 libc libm libdl libpthread librt libresolv libnsl
libgcc_s libstdc++ libatomic libcrypt libpthread
libglib-2.0 libgobject-2.0 libgio-2.0 libgmodule-2.0 libgthread-2.0
libgtk-3 libgdk-3 libgdk_pixbuf-2.0 libatk-1.0 libatk-bridge-2.0 libatspi
libpango-1.0 libpangocairo-1.0 libpangoft2-1.0 libcairo libcairo-gobject
libharfbuzz libfribidi libthai libdatrie libgraphite2
libfontconfig libfreetype libpixman-1 libpng16 libjpeg libtiff libwebp librsvg-2
libX11 libXext libXi libXrender libXrandr libXcursor libXfixes libXdamage
libXcomposite libXinerama libXtst libXau libXdmcp libxcb libxcb-shm
libxcb-render libxkbcommon libwayland-client libwayland-cursor libwayland-egl
libepoxy libGL libGLX libGLdispatch libEGL libgbm libdrm
libz libzstd liblzma libbz2 libbrotlicommon libbrotlidec libexpat libffi
libpcre libpcre2-8 libselinux libmount libblkid libuuid libsystemd libcap
libdbus-1 libgcrypt libgpg-error libcrypto libssl libgnutls libcups
"

# Never take a copy of these even if the list above misses one. Shipping our own
# glibc or libstdc++ is how a bundle stops working on the next distro.
never_copy="ld-linux ld-linux-x86-64 libc libm libdl libpthread librt libgcc_s libstdc++"

soname_of() {
  basename "$1" | sed 's/\.so\..*/.so/;s/\.so$//'
}

listed_in() {
  local needle=$1 haystack=$2 entry
  for entry in $haystack; do
    [ "$entry" = "$needle" ] && return 0
  done
  return 1
}

needed_by() {
  objdump -p "$1" 2>/dev/null | awk '/NEEDED/ {print $2}'
}

resolve() {
  ldd "$1" 2>/dev/null | awk -v want="$2" '$1 == want && $2 == "=>" {print $3}' | head -1
}

queue=("$libs"/*.so*)
for candidate in "$bundle"/*; do
  [ -f "$candidate" ] || continue
  if file -b "$candidate" | grep -q 'ELF.*executable'; then
    queue+=("$candidate")
  fi
done

copied=()
seen=""

while [ ${#queue[@]} -gt 0 ]; do
  current=${queue[0]}
  queue=("${queue[@]:1}")

  [ -f "$current" ] || continue

  for soname in $(needed_by "$current"); do
    stem=$(soname_of "$soname")

    listed_in "$stem" "$system_libraries" && continue
    listed_in "$stem" "$never_copy" && continue
    listed_in "$soname" "$seen" && continue
    [ -e "$libs/$soname" ] && continue

    origin=$(resolve "$current" "$soname")
    if [ -z "$origin" ] || [ ! -f "$origin" ]; then
      echo "::warning::$soname is needed by $(basename "$current") but could not be resolved"
      continue
    fi

    cp -L "$origin" "$libs/$soname"
    chmod u+w "$libs/$soname"
    seen="$seen $soname"
    copied+=("$soname")
    queue+=("$libs/$soname")
  done
done

for library in "$libs"/*.so*; do
  [ -f "$library" ] || continue
  patchelf --set-rpath '$ORIGIN' "$library"
done

for library in "$libs"/*.so*; do
  [ -f "$library" ] || continue
  runpath=$(patchelf --print-rpath "$library")
  case "$runpath" in
    ''|'$ORIGIN'*) ;;
    *)
      echo "::error::$(basename "$library") still looks for libraries in $runpath"
      exit 1
      ;;
  esac
done

if [ ${#copied[@]} -eq 0 ]; then
  echo "nothing outside the usual desktop stack was needed"
else
  printf 'took a copy of %d libraries the bundle cannot count on:\n' "${#copied[@]}"
  printf '  %s\n' "${copied[@]}"
fi
