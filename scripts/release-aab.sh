#!/usr/bin/env bash
# =============================================================================
# The ENTIRE release process, one command, every time — from a fresh terminal
# with no android/ project yet, or from one that's already there. Same command
# either way:
#
#   bash scripts/release-aab.sh
#
# What it does, in order:
#   1. Rebuild the data bundle + web app, run the invariant checks (npm run verify)
#   2. Create the (gitignored) android/ project if it's missing, else sync it
#   3. Stamp API 36 + the version — versionName from package.json, versionCode
#      always +1 from whatever's already there (see prep-android-api36.sh; this
#      is the fix for "the version code never updated" — it no longer depends
#      on anyone remembering to bump package.json first)
#   4. Build the signed release bundle
#
# Output: android/app/build/outputs/bundle/release/app-release.aab
#
# One-time prerequisite this script does NOT do for you: release signing.
# The first time you ever run `./gradlew bundleRelease` from the CLI (as
# opposed to Android Studio's "Generate Signed Bundle" wizard), android/app/
# build.gradle needs a signingConfigs block pointing at your keystore. If
# you've only ever built through Android Studio's wizard before, do that once
# more and let it save the config — after that, this script keeps working
# from a fresh android/ checkout every time, since Studio writes the signing
# config into the same (gitignored) build.gradle this script also edits.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root, regardless of where this is invoked from

echo "== 1/4  data -> build -> smoke =="
npm run verify

echo
echo "== 2/4  android/ project =="
if [ -d android ]; then
  echo "  exists — syncing"
  npx cap sync android
else
  echo "  missing — creating"
  npx cap add android
fi

echo
echo "== 3/4  stamp API 36 + version =="
bash scripts/prep-android-api36.sh

echo
echo "== 4/4  build signed release bundle =="
( cd android && ./gradlew clean bundleRelease )

AAB=android/app/build/outputs/bundle/release/app-release.aab
echo
if [ -f "$AAB" ]; then
  echo "DONE -> $AAB"
else
  echo "gradlew reported success but $AAB wasn't found — check the Gradle output above."
fi
