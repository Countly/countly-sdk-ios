#!/usr/bash

# countly_dsym_uploader.sh
#
# This code is provided under the MIT License.
#
# Please visit www.count.ly for more information.


# For your target, go to Build Phases tab and choose New Run Script Phase after clicking plus (+) button.
# Add this line and do not forget to replace YOUR_COUNTLY_SERVER and YOUR_APP_KEY.
#
# COUNTLY_DSYM_UPLOADER=$(/usr/bin/find $SRCROOT -name "countly_dsym_uploader.sh" | head -n 1)
# sh "$COUNTLY_DSYM_UPLOADER" "https://YOUR_COUNTLY_SERVER" "YOUR_APP_KEY"
#
# or if you're using CocoaPods:
# sh "$(PODS_ROOT)/Countly/countly_dsym_uploader.sh" "https://YOUR_COUNTLY_SERVER" "YOUR_APP_KEY"

HOST="$1";
APPKEY="$2";
CUSTOM_DSYM_PATH="${3}"


# Common functions
countly_log () { echo "[Countly] $1"; }

countly_usage () { 
	countly_log
	countly_log "You must invoke the script as follows:"
	countly_log
	countly_log "	sh \"/path/to/.../countly_dsym_uploader.sh\" \"https://YOUR_COUNTLY_SERVER\" \"YOUR_APP_KEY\" [\"/path/to/.../your.dSYM\"]"
	countly_log
}

countly_fail () { countly_log "$1"; exit 0; }

countly_upload() {
	BUILD_UUIDS="${1}"
	HOST="${2}"
	APPKEY="${3}"
	DSYM_ZIP_PATH="${4}"

	# Preparing for upload
	ENDPOINT="/i/crash_symbols/upload_symbol"
	QUERY="?platform=ios&app_key=${APPKEY}&build=${BUILD_UUIDS}"
	URL="$HOST$ENDPOINT${QUERY}"
	countly_log "Uploading to $URL"


	# Uploading to server using curl
	UPLOAD_RESULT=$(curl -s -F "symbols=@${DSYM_ZIP_PATH}" "${URL}")
	if [ $? -eq 0 ] && [ "$UPLOAD_RESULT" == "{\"result\":\"Success\"}" ]; then
	    countly_log "dSYM upload succesfully completed."
	else
	    countly_fail "dSYM upload failed!"
	fi
}

countly_zip() {
	DSYM_PATH="${1}"
	DSYM_FILENAME="${2}"

	if [ ! -d "${DSYM_PATH}" ]; then
	    countly_fail "${DSYM_PATH} does not exist!"
	fi

	pushd "${DSYM_PATH}"

	if [ ! -d "${DSYM_FILENAME}" ]; then
		countly_fail "${DSYM_FILENAME} does not exist!"
		popd
	fi

	# Extracting Build UUIDs from DSYM using dwarfdump
	BUILD_UUIDS=$(xcrun dwarfdump --uuid "${DSYM_FILENAME}" | awk '{print $2}' | xargs | sed 's/ /,/g')
	if [ $? -eq 0 ]; then
	    countly_log "Extracted Build UUIDs: $BUILD_UUIDS"
	else
	    countly_fail "Extracting Build UUIDs failed!"
	fi


	# Creating archive of DSYM folder using zip
	DSYM_ZIP_NAME="$(date +%s)_$(basename "${DSYM_FILENAME}").zip"
	DSYM_ZIP_PATH="/tmp/${DSYM_ZIP_NAME}"
	zip -rq "${DSYM_ZIP_PATH}" "${DSYM_FILENAME}"

	if [ $? -eq 0 ]; then
	    countly_log "Created archive at ${DSYM_ZIP_PATH}"
	else
	    countly_fail "Creating archive failed!"
	fi

	popd
}


# Pre-checks
if [[ -z $HOST ]]; then
	countly_usage
	countly_fail "Did not provide a Count.ly host to which to upload dSYMs."
fi

if [[ -z $APPKEY ]]; then
	countly_usage
	countly_fail "Did not provide an App Key for your dSYMs."
fi


# create the zip archive for upload
if [[ -z $CUSTOM_DSYM_PATH ]]; then
	if [ ! "$DWARF_DSYM_FOLDER_PATH" ] || [ ! "$DWARF_DSYM_FILE_NAME" ]; then
	    countly_fail "Xcode Environment Variables are missing!"
	fi

	countly_zip "${DWARF_DSYM_FOLDER_PATH}" "${DWARF_DSYM_FILE_NAME}"
else
	DSYM_PATH=$(dirname "${CUSTOM_DSYM_PATH}")
	DSYM_FILENAME=$(basename "${CUSTOM_DSYM_PATH}")
	countly_zip "${DSYM_PATH}" "${DSYM_FILENAME}"
fi


# upload
countly_upload "${BUILD_UUIDS}" "${HOST}" "${APPKEY}" "${DSYM_ZIP_PATH}"


# Removing artifacts
rm "${DSYM_ZIP_PATH}"


exit 0
