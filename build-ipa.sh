#!/bin/bash
# Baut eine unsignierte .ipa zum Sideloaden (AltStore/SideStore signieren sie mit deiner Apple-ID neu).
# Ergebnis: build-ipa/HomeRoll.ipa
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate -q
rm -rf build-ipa
xcodebuild -project HomeRoll.xcodeproj -scheme HomeRoll -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build-ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -quiet build
APP="build-ipa/Build/Products/Release-iphoneos/HomeRoll.app"
[ -d "$APP" ] || { echo "FEHLER: $APP nicht gefunden"; exit 1; }
rm -rf Payload; mkdir Payload; cp -R "$APP" Payload/
# Ad-hoc mit Berechtigungen signieren: Sideload-Werkzeuge lesen daraus die App-Gruppe (Widget + Teilen-Erweiterung)
P=Payload/HomeRoll.app
codesign -f -s - --entitlements Widget/FotosWidget.entitlements "$P/PlugIns/FotosWidget.appex"
codesign -f -s - --entitlements Share/FotosShare.entitlements "$P/PlugIns/FotosShare.appex"
codesign -f -s - --entitlements App/HomeRoll.entitlements "$P"
zip -qr build-ipa/HomeRoll.ipa Payload; rm -rf Payload
echo "Fertig: build-ipa/HomeRoll.ipa"
