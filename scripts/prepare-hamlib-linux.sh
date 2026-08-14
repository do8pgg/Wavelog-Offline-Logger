#!/bin/bash
set -euo pipefail

HAMLIB_VERSION="4.7.2"
HAMLIB_SHA256="ae1fcf2dbc80ea0786ea8f047b09399c3f7737d1930442f61a031708ed33e88f"
ARCHIVE_NAME="hamlib-${HAMLIB_VERSION}.tar.gz"
ARCHIVE_URL="https://github.com/Hamlib/Hamlib/releases/download/${HAMLIB_VERSION}/${ARCHIVE_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARCH="$(uname -m)"
OUTPUT_DIR="${1:-${PROJECT_ROOT}/build/embedded/hamlib/linux-${ARCH}}"
BUILD_ROOT="$(mktemp -d)"
trap 'rm -rf "${BUILD_ROOT}"' EXIT

ARCHIVE_PATH="${BUILD_ROOT}/${ARCHIVE_NAME}"
SOURCE_DIR="${BUILD_ROOT}/hamlib-${HAMLIB_VERSION}"
INSTALL_DIR="${BUILD_ROOT}/install"

echo "Hamlib ${HAMLIB_VERSION} für Linux (${ARCH}) laden ..."
curl --fail --location --retry 5 --retry-all-errors \
  --output "${ARCHIVE_PATH}" "${ARCHIVE_URL}"

# 1. sha256sum statt shasum
echo "${HAMLIB_SHA256}  ${ARCHIVE_PATH}" | sha256sum --check

tar -xzf "${ARCHIVE_PATH}" -C "${BUILD_ROOT}"
pushd "${SOURCE_DIR}" >/dev/null

./configure \
  --prefix="${INSTALL_DIR}" \
  --disable-shared \
  --enable-static \
  --without-libusb \
  --without-readline \
  --without-cxx-binding \
  --without-indi \
  --without-libnova \
  --disable-winradio

# 2. nproc statt sysctl
make -j"$(nproc)"
make install
popd >/dev/null

RIGCTLD="${INSTALL_DIR}/bin/rigctld"
test -x "${RIGCTLD}"
"${RIGCTLD}" --version

# 3. ldd statt otool -L zur Prüfung dynamischer Abhängigkeiten.
# Wir prüfen, ob ungewöhnliche Abhängigkeiten (außer libc, libm, libpthread, ld-linux) vorhanden sind.
UNEXPECTED_LINKS="$(
  ldd "${RIGCTLD}" | awk '{print $1}' | \
#    grep -Ev '^(linux-vdso\.so|libc\.so|libm\.so|libpthread\.so|libdl\.so|ld-linux.*\.so)' || true
    grep -Ev '(linux-vdso|libc\.so|libm\.so|libpthread\.so|libdl\.so|ld-linux)' || true
)"
if [[ -n "${UNEXPECTED_LINKS}" ]]; then
  echo "Achtung: Nicht standardmäßige Bibliotheksabhängigkeiten in rigctld:" >&2
  echo "${UNEXPECTED_LINKS}" >&2
  # Hinweis: Falls hier Warnungen auftreten, die auf deinem System unkritisch sind,
  # kannst du den nachfolgenden exit-1-Befehl auskommentieren.
  exit 1
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
cp "${RIGCTLD}" "${OUTPUT_DIR}/rigctld"
cp "${SOURCE_DIR}/LICENSE" "${OUTPUT_DIR}/LICENSE.txt"
cp "${SOURCE_DIR}/COPYING" "${OUTPUT_DIR}/COPYING.txt"
cp "${SOURCE_DIR}/COPYING.LIB" "${OUTPUT_DIR}/COPYING.LIB.txt"
printf 'Hamlib %s (Linux %s)\nSource: %s\n' \
  "${HAMLIB_VERSION}" "${ARCH}" "${ARCHIVE_URL}" \
  > "${OUTPUT_DIR}/HAMLIB_VERSION.txt"
chmod 755 "${OUTPUT_DIR}/rigctld"

echo "Hamlib wurde vorbereitet: ${OUTPUT_DIR}"