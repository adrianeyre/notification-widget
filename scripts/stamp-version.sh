#!/bin/sh
# Writes the app's version into the built app's Info.plist from git, so Settings and the
# menu bar show the release this build came from (see AppVersion.swift).
#
# Releases are the v* tags semantic-release makes; nothing in the project is bumped.
# Without git or tags (a shallow CI checkout, a source archive) the plist keeps
# MARKETING_VERSION and CURRENT_PROJECT_VERSION from Config/Base.xcconfig.
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
cd "${SRCROOT}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "stamp-version: not a git checkout; keeping ${MARKETING_VERSION:-the xcconfig version}"
  exit 0
fi

tag=$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)
if [ -z "$tag" ]; then
  echo "stamp-version: no v* tags (fetch them with: git fetch --tags); keeping ${MARKETING_VERSION:-the xcconfig version}"
  exit 0
fi

version=${tag#v}
build=$(git rev-list --count HEAD)
description=$(git describe --tags --match 'v[0-9]*' --dirty)

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build}" "$plist"
/usr/libexec/PlistBuddy -c "Delete :NWGitDescription" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :NWGitDescription string ${description}" "$plist"
echo "stamp-version: ${version} (${build}), ${description}"
