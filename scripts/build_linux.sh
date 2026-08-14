#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${1:-${PROJECT_ROOT}/dist}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
ARCH="$(uname -m)"

case "${ARCH}" in
  aarch64|arm64) PACKAGE_ARCH="arm64" ;;
  x86_64)        PACKAGE_ARCH="x64" ;;
  *) echo "Nicht unterstützte Linux-Architektur: ${ARCH}" >&2; exit 1 ;;
esac

cd "${PROJECT_ROOT}"
VERSION="$(${PYTHON_BIN} -c 'import logger_core; print(logger_core.VERSION)')"
if [[ -z "${VERSION}" ]]; then
  echo "Versionsnummer konnte nicht gelesen werden." >&2
  exit 1
fi

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  "${PYTHON_BIN}" selftest.py
fi

# 1. Hamlib für Linux vorbereiten
HAMLIB_DIR="${PROJECT_ROOT}/build/embedded/hamlib/linux-${PACKAGE_ARCH}"
if [[ -f "${SCRIPT_DIR}/prepare-hamlib-linux.sh" ]]; then
  "${SCRIPT_DIR}/prepare-hamlib-linux.sh" "${HAMLIB_DIR}"
fi

# 2. Ordner-Pfade ZUERST definieren
BUILD_DIR="${PROJECT_ROOT}/build/pyinstaller-linux-${PACKAGE_ARCH}"
PACKAGE_DIR="${BUILD_DIR}/package"
SPEC_DIR="${BUILD_DIR}/spec"

# Alte Builds aufräumen & Ordner erstellen
rm -rf "${BUILD_DIR}"
mkdir -p "${PACKAGE_DIR}" "${SPEC_DIR}" "${OUTPUT_DIR}"

# 3. Jetzt die isolierte venv im Beseitigten BUILD_DIR erstellen
VENV_DIR="${BUILD_DIR}/venv"
"${PYTHON_BIN}" -m venv "${VENV_DIR}"
VENV_PYTHON="${VENV_DIR}/bin/python"

# PyInstaller sicher in der venv installieren
"${VENV_PYTHON}" -m pip install --disable-pip-version-check "pyinstaller==6.17.0"

APP_NAME="DA6IT.de Wavelog Offline Logger"

# 4. PyInstaller mit VENV_PYTHON aufrufen
"${VENV_PYTHON}" -m PyInstaller \
  --noconfirm \
  --clean \
  --windowed \
  --name "${APP_NAME}" \
  --add-data "${PROJECT_ROOT}/cty.dat:." \
  --add-data "${HAMLIB_DIR}:hamlib" \
  --distpath "${PACKAGE_DIR}" \
  --workpath "${BUILD_DIR}/work" \
  --specpath "${SPEC_DIR}" \
  app.py

APP_DIST_DIR="${PACKAGE_DIR}/${APP_NAME}"
test -d "${APP_DIST_DIR}"
test -x "${APP_DIST_DIR}/${APP_NAME}"

# 5. Binaries prüfen
BUNDLED_RIGCTLD="$(find "${APP_DIST_DIR}" -path '*/hamlib/rigctld' -type f -print -quit)"
if [[ -z "${BUNDLED_RIGCTLD}" ]]; then
  echo "rigctld fehlt im Build-Verzeichnis." >&2
  exit 1
fi
chmod 755 "${BUNDLED_RIGCTLD}"
"${BUNDLED_RIGCTLD}" --version

ARCH_INFO="$(file "${APP_DIST_DIR}/${APP_NAME}")"
echo "${ARCH_INFO}"

# 6. Packaging mittels tar.gz und sha256sum
TAR_NAME="DA6IT.de-Wavelog-Offline-Logger-v${VERSION}-linux-${PACKAGE_ARCH}.tar.gz"
TAR_PATH="${OUTPUT_DIR}/${TAR_NAME}"
rm -f "${TAR_PATH}" "${TAR_PATH}.sha256"

tar -czf "${TAR_PATH}" -C "${PACKAGE_DIR}" "${APP_NAME}"

(
  cd "${OUTPUT_DIR}"
  sha256sum "${TAR_NAME}" > "${TAR_NAME}.sha256"
)

echo "Linux-Paket erstellt: ${TAR_PATH}"