#!/bin/bash

# countly_dsym_uploader.sh
#
# This code is provided under the MIT License.
#
# Please visit www.count.ly for more information.


# For your target, go to `Build Phases` tab and choose `New Run Script Phase` after clicking plus (+) button.
# Add these two lines:
#
# COUNTLY_DSYM_UPLOADER=$(find $SRCROOT -name "countly_dsym_uploader.sh" | head -n 1)
# sh "$COUNTLY_DSYM_UPLOADER" "https://YOUR_COUNTLY_SERVER" "YOUR_APP_KEY"
#
# or if you're using CocoaPods just add this one line:
#
# sh "$(PODS_ROOT)/Countly/countly_dsym_uploader.sh" "https://YOUR_COUNTLY_SERVER" "YOUR_APP_KEY"
#
# Notes:
# Do not forget to replace YOUR_COUNTLY_SERVER and YOUR_APP_KEY with real values.
# If your project setup and/or CI/CD flow requires a custom path for the generated dSYMs, you can specify it as third argument.


# Common functions
countly_log () { echo "[Countly] $1"; }

countly_fail () { countly_log "$1"; exit 0; }

countly_usage ()
{
    countly_log "You must invoke the script as follows:"
    echo "    sh \"/path/to/.../countly_dsym_uploader.sh\" \"https://YOUR_COUNTLY_SERVER\" \"YOUR_APP_KEY\" [\"/path/to/.../your.dSYM\"]"
}


# Reading arguments
HOST="${1}";
APPKEY="${2}";
CUSTOM_DSYM_PATH="${3}"


# Pre-checks
if [[ -z $HOST ]]; then
    countly_usage
    countly_fail "Host not specified!"
fi

if [[ -z $APPKEY ]]; then
    countly_usage
    countly_fail "App Key not specified!"
fi

if [[ -z $CUSTOM_DSYM_PATH ]]; then
    if [ ! "${DWARF_DSYM_FOLDER_PATH}" ] || [ ! "${DWARF_DSYM_FILE_NAME}" ]; then
        countly_usage
        countly_fail "Custom dSYM path not specified and Xcode Environment Variables are missing!"
    fi

    DSYM_FOLDER_PATH=${DWARF_DSYM_FOLDER_PATH}
    DSYM_FILE_NAME=${DWARF_DSYM_FILE_NAME}
else
    DSYM_FOLDER_PATH=$(dirname "${CUSTOM_DSYM_PATH}")
    DSYM_FILE_NAME=$(basename "${CUSTOM_DSYM_PATH}")
fi

DSYM_PATH="${DSYM_FOLDER_PATH}/${DSYM_FILE_NAME}";
if [[ ! -d $DSYM_PATH ]]; then
    countly_fail "dSYM path ${DSYM_PATH} does not exist!"
fi


# Extracting Build UUIDs from DSYM using dwarfdump
BUILD_UUIDS=$(xcrun dwarfdump --uuid "${DSYM_PATH}" | awk '{print $2}' | xargs | sed 's/ /,/g')
if [ $? -eq 0 ]; then
    countly_log "Extracted Build UUIDs: ${BUILD_UUIDS}"
else
    countly_fail "Extracting Build UUIDs failed!"
fi


# Creating archive of DSYM folder using zip
DSYM_ZIP_PATH="/tmp/$(date +%s)_${DSYM_FILE_NAME}.zip"
pushd "${DSYM_FOLDER_PATH}" > /dev/null
zip -rq "${DSYM_ZIP_PATH}" "${DSYM_FILE_NAME}"
popd > /dev/null
if [ $? -eq 0 ]; then
    countly_log "Created archive at $DSYM_ZIP_PATH"
else
    countly_fail "Creating archive failed!"
fi


# Preparing for upload
ENDPOINT="/i/crash_symbols/upload_symbol"

PLATFORM="ios" #This value is common for all iOS/iPadOS/watchOS/tvOS/macOS

EPN=${EFFECTIVE_PLATFORM_NAME:1}
if [[ -z $EPN ]]; then
EPN="macos"
fi

QUERY="?platform=${PLATFORM}&epn=${EPN}&app_key=${APPKEY}&build=${BUILD_UUIDS}"
URL="${HOST}${ENDPOINT}${QUERY}"
countly_log "Uploading to ${URL}"


# Uploading to server using curl
UPLOAD_RESULT=$(curl -s -F "symbols=@${DSYM_ZIP_PATH}" "${URL}")
if [ $? -eq 0 ] && [ "${UPLOAD_RESULT}" == "{\"result\":\"Success\"}" ]; then
    countly_log "dSYM upload succesfully completed."
else
    countly_fail "dSYM upload failed! ${UPLOAD_RESULT}"
fi


# Removing artifacts
rm "${DSYM_ZIP_PATH}"

exit 0
