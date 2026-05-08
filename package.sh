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
mkdir -p "$APP_DIR/Contents/Frameworks"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

# index.html'i direkt Resources'a kopyala (SwiftPM Bundle.module bypass).
# Bu kasıtlı: SwiftPM auto-generated accessor build-time path'i hardcode
# ediyor, başka bir Mac'te crash ediyordu. Bundle.main ile temiz çalışır.
HTML_SRC="Sources/PomodoroMenubar/Resources/index.html"
if [[ -f "$HTML_SRC" ]]; then
    cp "$HTML_SRC" "$APP_DIR/Contents/Resources/index.html"
else
    echo "Hata: $HTML_SRC bulunamadı" >&2
    exit 1
fi

# Sparkle.framework bundle'a göm + rpath ayarla
SPARKLE_FW="$BUILD_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
    # SwiftPM @rpath'i otomatik eklemiyor — manuel ekle
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP_DIR/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
else
    echo "Uyarı: Sparkle.framework bulunamadı: $SPARKLE_FW" >&2
fi

cp Info.plist "$APP_DIR/Contents/Info.plist"

# Localization marker'ları — Sparkle ve sistem app'in dil destek listesini buradan
# okur. tr.lproj boş olabilir, sadece "Türkçeyi destekliyorum" sinyali gönderiyor.
mkdir -p "$APP_DIR/Contents/Resources/tr.lproj"
mkdir -p "$APP_DIR/Contents/Resources/en.lproj"
cat > "$APP_DIR/Contents/Resources/tr.lproj/InfoPlist.strings" <<'PLIST'
"CFBundleName" = "Pomodoro";
"CFBundleDisplayName" = "Pomodoro";
PLIST
cat > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings" <<'PLIST'
"CFBundleName" = "Pomodoro";
"CFBundleDisplayName" = "Pomodoro";
PLIST

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

# 5) DMG (--dmg) — Türkçe arka plan + sürükle-bırak layout ile
if [[ "$DO_DMG" -eq 1 ]]; then
    DMG_NAME="Pomodoro-${VERSION}.dmg"
    RW_DMG="rw.${VERSION}.dmg"
    STAGING=$(mktemp -d -t pomodoro-dmg)
    trap "rm -rf '$STAGING' '$RW_DMG' 2>/dev/null" EXIT

    rm -f "$DMG_NAME" rw.*.dmg
    hdiutil detach "/Volumes/Pomodoro" -force 2>/dev/null || true

    # Background görseli yoksa üret
    if [[ ! -f "dmg-background.png" || ! -f "dmg-background@2x.png" ]]; then
        echo "==> DMG arka planı üretiliyor (dmg-bg-gen.swift)…"
        swift dmg-bg-gen.swift
    fi

    echo "==> DMG staging hazırlanıyor…"
    cp -R "$APP_DIR" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    mkdir -p "$STAGING/.background"
    cp dmg-background.png "$STAGING/.background/dmg-background.png"
    cp dmg-background@2x.png "$STAGING/.background/dmg-background@2x.png"

    echo "==> RW DMG oluşturuluyor…"
    # APFS default; -size belirtmeden srcfolder'dan otomatik hesaplansın
    if hdiutil create \
        -volname "Pomodoro" \
        -srcfolder "$STAGING" \
        -format UDRW -ov \
        "$RW_DMG" 2>&1; then
        DMG_RW_OK=1
    else
        DMG_RW_OK=0
        echo "Uyarı: RW DMG oluşturulamadı, basit UDZO'ya düşüyorum"
    fi

    if [[ "$DMG_RW_OK" -eq 1 ]]; then
        echo "==> Mount + Finder layout…"
        hdiutil attach "$RW_DMG" -nobrowse -noautoopen >/dev/null 2>&1 || true
        sleep 2

        # AppleScript GitHub Actions runner'da Finder'a bağlanamayabilir.
        # Hata durumunda layout default kalır, background image yine de
        # /.background/ üzerinden DMG'de bulunur.
        osascript <<'APPLESCRIPT' 2>&1 || echo "Uyarı: AppleScript layout başarısız (DMG yine de çalışır)"
tell application "Finder"
    tell disk "Pomodoro"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 940, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:dmg-background.png"
        set position of item "Pomodoro.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

        sync
        sleep 2
        hdiutil detach "/Volumes/Pomodoro" -force 2>/dev/null || true
        sleep 1

        echo "==> Read-only DMG'ye dönüştürülüyor (UDZO sıkıştırma)…"
        hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_NAME" >/dev/null
        rm -f "$RW_DMG"
    else
        # Fallback: tek adımda UDZO yarat (layout yok, ama background image
        # staging içinde .background/ klasöründe yer alır)
        echo "==> Fallback: UDZO DMG (layout yok)"
        hdiutil create \
            -volname "Pomodoro" \
            -srcfolder "$STAGING" \
            -format UDZO -imagekey zlib-level=9 -ov \
            "$DMG_NAME" >/dev/null
    fi

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
