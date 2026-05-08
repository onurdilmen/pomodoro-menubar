#!/usr/bin/env bash
# Pomodoro.app build / bundle / install / DMG aracı
#
# Kullanım:
#   ./package.sh              -> release build + .app bundle
#   ./package.sh debug        -> debug build + .app bundle
#   ./package.sh --install    -> build + bundle + /Applications/'a kopya + yeniden başlat
#   ./package.sh --icon       -> ikonu yeniden üret (AppIcon.icns)
#   ./package.sh --dmg        -> build + bundle + Pomodoro.dmg installer
#   ./package.sh --all        -> ikon + build + install + dmg

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
DO_INSTALL=0
DO_DMG=0
DO_ICON=0

# Argümanları ayrıştır
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --install) DO_INSTALL=1 ;;
        --dmg) DO_DMG=1 ;;
        --icon) DO_ICON=1 ;;
        --all) DO_ICON=1; DO_INSTALL=1; DO_DMG=1 ;;
        -h|--help)
            grep -E "^# " "$0" | sed 's/^# //'
            exit 0
            ;;
    esac
done

APP_NAME="Pomodoro"
APP_DIR="${APP_NAME}.app"
BIN_NAME="Pomodoro"
TARGET_NAME="PomodoroMenubar"
INSTALL_PATH="/Applications/${APP_DIR}"

# Version: env var > git tag > fallback. CI tag push'larında VERSION=0.2.0 olarak çağırır.
if [[ -z "${VERSION:-}" ]]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.1.0")
fi
echo "==> VERSION=$VERSION"

# 1) İkon (gerekirse veya --icon ise)
if [[ "$DO_ICON" -eq 1 || ! -f "AppIcon.icns" ]]; then
    echo "==> İkon üretiliyor (icon-gen.swift)…"
    swift icon-gen.swift
fi

# 2) Build
echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"

BUILD_DIR=".build/$CONFIG"
BIN_PATH="$BUILD_DIR/$TARGET_NAME"
RES_BUNDLE="$BUILD_DIR/${TARGET_NAME}_${TARGET_NAME}.bundle"

if [[ ! -f "$BIN_PATH" ]]; then
    echo "Hata: binary bulunamadı: $BIN_PATH" >&2
    exit 1
fi

# 3) .app bundle
echo "==> Bundle yapılıyor: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

if [[ -d "$RES_BUNDLE" ]]; then
    cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
else
    echo "Uyarı: resource bundle bulunamadı: $RES_BUNDLE" >&2
fi

cp Info.plist "$APP_DIR/Contents/Info.plist"

# Bundle içindeki version string'lerini gerçek VERSION ile güncelle
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true

if [[ -f "AppIcon.icns" ]]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Lokal kullanım için ad-hoc imza
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> Bundle tamam: $(pwd)/$APP_DIR"

# 4) Install (--install)
if [[ "$DO_INSTALL" -eq 1 ]]; then
    echo "==> Çalışan instance kapatılıyor…"
    pkill -f "${INSTALL_PATH}/Contents/MacOS/${BIN_NAME}" 2>/dev/null || true
    sleep 1

    echo "==> /Applications/'a kopyalanıyor…"
    rm -rf "$INSTALL_PATH"
    cp -R "$APP_DIR" "$INSTALL_PATH"

    # Finder'a ikon değiştiğini söyle (cache temizle)
    touch "$INSTALL_PATH"

    echo "==> Yeniden başlatılıyor…"
    open "$INSTALL_PATH"
    echo "    Kuruldu: $INSTALL_PATH"
fi

# 5) DMG (--dmg) — hdiutil ile (Mac yerli, AppleScript yok)
if [[ "$DO_DMG" -eq 1 ]]; then
    DMG_NAME="Pomodoro-${VERSION}.dmg"
    STAGING=$(mktemp -d -t pomodoro-dmg)
    trap "rm -rf '$STAGING'" EXIT

    rm -f "$DMG_NAME" rw.*.dmg
    hdiutil detach "/Volumes/Pomodoro" -force 2>/dev/null || true

    echo "==> DMG staging hazırlanıyor…"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    echo "==> DMG üretiliyor: $DMG_NAME"
    hdiutil create \
        -volname "Pomodoro" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_NAME" >/dev/null

    # Code-sign DMG (ad-hoc)
    codesign --force --sign - "$DMG_NAME" 2>/dev/null || true

    echo "==> DMG tamam: $(pwd)/$DMG_NAME"
    echo "    Boyut: $(du -h "$DMG_NAME" | cut -f1)"
fi

echo
echo "Çalıştır: open $APP_DIR"
if [[ "$DO_INSTALL" -eq 1 ]]; then
    echo "Ya da: open $INSTALL_PATH"
fi
if [[ "$DO_DMG" -eq 1 ]]; then
    echo "DMG paylaş: $(pwd)/Pomodoro-${VERSION}.dmg"
fi
