#!/usr/bin/env bash
set -euo pipefail

if [ -f "$1/Payload/Telegram.app/Info.plist" ]; then
	APP_DIR="$1/Payload/Telegram.app"
else
	APP_DIR="$1/Telegram.app"
fi

INFO_PLIST="${APP_DIR}/Info.plist"
RUNFILES_ROOT="${NAGRAM_RUNFILES_ROOT:-${0}.runfiles/_main}"
if [ ! -d "${RUNFILES_ROOT}" ]; then
	RUNFILES_ROOT="${0}.runfiles/__main__"
fi

ACTOOL="$(/usr/bin/xcrun --find actool)"
if [ ! -x "${ACTOOL}" ]; then
	echo "Unable to find actool in the active Xcode toolchain: ${ACTOOL}" >&2
	exit 1
fi

# MARK: NEXTGRAM — Nextgram's primary icon plus the Telegram Icon Composer alternate.
NEXTGRAM_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/NextgramBuild.icon"
TELEGRAM_ICON_SOURCE="${RUNFILES_ROOT}/Telegram/Telegram-iOS/Telegram.icon"

for icon_source in "${NEXTGRAM_ICON_SOURCE}" "${TELEGRAM_ICON_SOURCE}"; do
	if [ ! -f "${icon_source}/icon.json" ]; then
		echo "Missing Icon Composer source: ${icon_source}" >&2
		exit 1
	fi
done

echo "Compiling Nextgram icons: ${ACTOOL}"

case "${APPLE_SDK_PLATFORM:-iPhoneOS}" in
	*iPhoneSimulator*|*iphonesimulator*)
		ACTOOL_PLATFORM="iphonesimulator"
		;;
	*)
		ACTOOL_PLATFORM="iphoneos"
		;;
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nagram-icons.XXXXXX")"
cleanup() {
	rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

real_dir() {
	local path="$1"
	cd "${path}"
	pwd -P
}

real_file_dir() {
	local path="$1"
	dirname "$(realpath "${path}/icon.json")"
}

ICONS_XCASSETS="$(real_dir "${RUNFILES_ROOT}/Telegram/Telegram-iOS/Icons.xcassets")"
LEGACY_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/LegacyComponents/LegacyImages.xcassets")"
PASSWORD_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/PasswordSetupUI/PasswordSetupUIImages.xcassets")"
TELEGRAM_UI_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/TelegramUI/Images.xcassets")"
CALL_SCREEN_XCASSETS="$(real_dir "${RUNFILES_ROOT}/submodules/TelegramUI/Components/Calls/CallScreen/CallScreenAssets.xcassets")"

NEXTGRAM_ICON="${WORK_DIR}/NextgramBuild.icon"
TELEGRAM_ICON="${WORK_DIR}/Telegram.icon"
ditto "$(real_file_dir "${NEXTGRAM_ICON_SOURCE}")" "${NEXTGRAM_ICON}"
ditto "$(real_file_dir "${TELEGRAM_ICON_SOURCE}")" "${TELEGRAM_ICON}"

COMPILED_ICONS_DIR="${WORK_DIR}/out"
mkdir -p "${COMPILED_ICONS_DIR}"
"${ACTOOL}" \
	--compile "${COMPILED_ICONS_DIR}" \
	--errors --warnings --notices \
	--output-format human-readable-text \
	--platform "${ACTOOL_PLATFORM}" \
	--minimum-deployment-target 15.0 \
	--compress-pngs \
	--app-icon NextgramBuild \
	--alternate-app-icon Telegram \
	--target-device iphone \
	--target-device ipad \
	--output-partial-info-plist "${WORK_DIR}/xcassets-info.plist" \
	"${ICONS_XCASSETS}" \
	"${LEGACY_XCASSETS}" \
	"${PASSWORD_XCASSETS}" \
	"${TELEGRAM_UI_XCASSETS}" \
	"${CALL_SCREEN_XCASSETS}" \
	"${NEXTGRAM_ICON}" \
	"${TELEGRAM_ICON}"

ditto "${COMPILED_ICONS_DIR}" "${APP_DIR}"

ensure_dict() {
	local path="$1"
	/usr/libexec/PlistBuddy -c "Print ${path}" "${INFO_PLIST}" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add ${path} dict" "${INFO_PLIST}"
}

reset_primary_icon() {
	local root="$1"
	shift
	ensure_dict "${root}"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundlePrimaryIcon" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles array" "${INFO_PLIST}"
	local index=0
	local icon_file
	for icon_file in "$@"; do
		/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconFiles:${index} string ${icon_file}" "${INFO_PLIST}"
		index=$((index + 1))
	done
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundlePrimaryIcon:CFBundleIconName string NextgramBuild" "${INFO_PLIST}"
}

set_icon_name() {
	local root="$1"
	local icon="$2"
	ensure_dict "${root}:CFBundleAlternateIcons"
	/usr/libexec/PlistBuddy -c "Delete ${root}:CFBundleAlternateIcons:${icon}" "${INFO_PLIST}" >/dev/null 2>&1 || true
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon} dict" "${INFO_PLIST}"
	/usr/libexec/PlistBuddy -c "Add ${root}:CFBundleAlternateIcons:${icon}:CFBundleIconName string ${icon}" "${INFO_PLIST}"
}

reset_primary_icon ":CFBundleIcons" NextgramBuild60x60
reset_primary_icon ":CFBundleIcons~ipad" NextgramBuild60x60 NextgramBuild76x76

set_icon_name ":CFBundleIcons" Telegram
set_icon_name ":CFBundleIcons~ipad" Telegram
