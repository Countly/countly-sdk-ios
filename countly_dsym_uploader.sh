#!/bin/bash

# countly_dsym_uploader.sh
#
# This code is provided under the MIT License.
#
# Please visit https://countly.com/ for more information.


# For your target, go to `Build Phases` tab and choose `New Run Script Phase` after clicking plus (+) button.
# Here the first line is a find command to find and extract the path to the script. If you know the path you can skip this line.
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
# Third argument is optional. If you do not provide it, the script will try to use Xcode Environment Variables to find the dSYM.
# If you provide it, the script will use the provided path to find the dSYM.
# The path should be absolute and point to the .dSYM file or the folder containing the .dSYM files.


# Common functions
countly_log () { echo "[Countly] $1"; }

countly_fail () { countly_log "$1"; exit 0; }
countly_go_next_iteration () { countly_log "$1"; DSYM_FILE_NAME=$INITIAL_DSYM_FILE_NAME; DSYM_FOLDER_PATH=$INITIAL_FOLDER_PATH; continue; }

countly_usage ()
{
    countly_log "You must invoke the script as follows:"
    echo "    sh \"/path/to/.../countly_dsym_uploader.sh\" \"https://YOUR_COUNTLY_SERVER\" \"YOUR_APP_KEY\" [\"/path/to/.../your.dSYM\"]"
}


# Reading arguments
HOST="${1}";
APPKEY="${2}";
CUSTOM_DSYM_PATH="${3}"

countly_log "Provided server:[$HOST]\n app key:[$APPKEY]\n custom dSYM path:[$CUSTOM_DSYM_PATH]"

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
    countly_log "dSYM folder path:[$DSYM_FOLDER_PATH]"
    DSYM_FILE_NAME=${DWARF_DSYM_FILE_NAME}
    countly_log "dSYM file name:[$DSYM_FILE_NAME]"
else
    DSYM_FOLDER_PATH=$(dirname "${CUSTOM_DSYM_PATH}")
    countly_log "dSYM folder path:[$DSYM_FOLDER_PATH]"
    DSYM_FILE_NAME=$(basename "${CUSTOM_DSYM_PATH}")
    countly_log "dSYM file name:[$DSYM_FILE_NAME]"
fi
INITIAL_DSYM_FILE_NAME=$DSYM_FILE_NAME
INITIAL_FOLDER_PATH=$DSYM_FOLDER_PATH
DSYM_PATH="${DSYM_FOLDER_PATH}/${DSYM_FILE_NAME}"

for file in "$DSYM_PATH"/*; do
printf "======\n[Countly] Processing $file \n"
IN_DSYM=false
IN_FOLDER=false

    if [[ ! $INITIAL_DSYM_FILE_NAME == *.dSYM ]]; then
        countly_log "Provided file is not a .dSYM file!"
        countly_log "Given Path was a Folder. Checking the files inside the folder for .dSYM files!"
        if [[ $file == *.dSYM ]]; then
            IN_FOLDER=true
            DSYM_FILE_NAME=$(basename "${file}")
            DSYM_PATH="${CUSTOM_DSYM_PATH}/${DSYM_FILE_NAME}"
        else
            countly_go_next_iteration "File inside the folder is not a .dSYM file!"
        fi
    else
        countly_log "Provided file is a dSYM file!"
        IN_DSYM=true
    fi

    countly_log "Current dSYM path:[$DSYM_PATH]"

    # Extracting Build UUIDs from DSYM using dwarfdump
    XCRUN_RES=$(xcrun dwarfdump --uuid "${DSYM_PATH}")
    countly_log "Xcrun result:[$XCRUN_RES]"
    RAW_UUID=$(echo "${XCRUN_RES}" | awk '{print $2}')
    countly_log "Raw UUID:[$RAW_UUID]"
    # Remove whitespace and such
    BUILD_UUIDS=$(echo "${RAW_UUID}" | xargs | sed 's/ /,/g')
    if [ $? -eq 0 ]; then
        countly_log "Extracted Build UUIDs:[${BUILD_UUIDS}]"
        if [ ! "$BUILD_UUIDS" ]; then
            countly_go_next_iteration "Nothing was extracted! Check if your Xcode configuration or the provided path is correct."
        fi

    else
        countly_go_next_iteration "Extracting Build UUIDs failed!"
    fi


    # Creating archive of DSYM folder using zip 
    countly_log "Creating archive of dSYM folder using zip"
    countly_log "Current dSYM folder path:[$DSYM_FOLDER_PATH]"
    countly_log "Current dSYM file name:[$DSYM_FILE_NAME]"
    DSYM_ZIP_PATH="/tmp/$(date +%s)_${DSYM_FILE_NAME}.zip"
    if [ $IN_FOLDER == true ]; then
        countly_log "In folder. Pushd to:[$(dirname "${DSYM_PATH}")]"
        pushd $(dirname "${DSYM_PATH}") > /dev/null
    fi
    if [ $IN_DSYM == true ]; then
        countly_log "In dSYM. Pushd to:["${DSYM_FOLDER_PATH}"]"
        pushd "${DSYM_FOLDER_PATH}" > /dev/null
    fi
    zip -r "${DSYM_ZIP_PATH}" "${DSYM_FILE_NAME}"
    popd > /dev/null
    if [ $? -eq 0 ]; then
        countly_log "Created archive at $DSYM_ZIP_PATH"
    else
        countly_go_next_iteration "Creating archive failed!"
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
    countly_log "Uploading to:[${URL}]"


    # Uploading to server using curl
    UPLOAD_RESULT=$(curl -s -F "symbols=@${DSYM_ZIP_PATH}" "${URL}")
    if [ $? -eq 0 ] && [ "${UPLOAD_RESULT}" == "{\"result\":\"Success\"}" ]; then
        countly_log "dSYM upload succesfully completed."
    else
        countly_go_next_iteration "dSYM upload failed! Response from the server:[${UPLOAD_RESULT}]"
    fi


    # Removing artifacts
    rm "${DSYM_ZIP_PATH}"
    # return variables to default
    DSYM_FILE_NAME=$INITIAL_DSYM_FILE_NAME
    DSYM_FOLDER_PATH=$INITIAL_FOLDER_PATH
done
exit 0
