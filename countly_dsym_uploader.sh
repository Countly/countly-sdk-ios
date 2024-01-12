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
countly_pass () { countly_log "$1"; DSYM_FILE_NAME=$INITIAL_DSYM_FILE_NAME; DSYM_FOLDER_PATH=$INITIAL_FOLDER_PATH; continue; }

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

    if [[ ! $INITIAL_DSYM_FILE_NAME == *.dSYM ]]; then
        countly_log "Provided file is not a ,dSYM file!"
        if [[ ! $INITIAL_DSYM_FILE_NAME == *.app ]]; then
            countly_log "Provided file is not an .app file!"
            if [[ $file == *.dSYM ]]; then
                countly_log "Using files inside the folder!"
                DSYM_FILE_NAME=$(basename "${file}")
                DSYM_PATH="${CUSTOM_DSYM_PATH}/${DSYM_FILE_NAME}"
            else
                countly_pass "File inside the folder is not a dSYM file!"
            fi
        else
            countly_log "Provided file is an app file!"
            FILE_LENGTH=${#INITIAL_DSYM_FILE_NAME}
            DSYM_INNER_FILE_NAME=${INITIAL_DSYM_FILE_NAME:0:FILE_LENGTH-4}
            DSYM_PATH="${DSYM_FOLDER_PATH}/${INITIAL_DSYM_FILE_NAME}/${DSYM_INNER_FILE_NAME}"
        fi
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
        # if UUIDs are empty and custom path is not provided it means that we are using new Xcode
        # this means instead of a .app.dSYM we have a .app which has a symbol file inside without .dSYM extension 
        # TODO: create a function instead of repeating the code
        if [ ! "$BUILD_UUIDS" ] && [ -z $CUSTOM_DSYM_PATH ];then
            countly_log "Will try to extract UUIDs with .app extension for new Xcode"
            FILE_LENGTH=${#DSYM_FILE_NAME}
            APP_NAME=${DSYM_FILE_NAME:0:FILE_LENGTH-5}
            countly_log "App name:[$APP_NAME]"
            # removing .app from the end
            DSYM_FILE_NAME=${DSYM_FILE_NAME:0:FILE_LENGTH-9}
            DSYM_PATH="${DSYM_FOLDER_PATH}/${APP_NAME}/${DSYM_FILE_NAME}"
            countly_log "New dSYM path:[$DSYM_PATH]"
            XCRUN_RES=$(xcrun dwarfdump --uuid "${DSYM_PATH}")
            countly_log "Xcrun result:[$XCRUN_RES]"
            RAW_UUID=$(echo "${XCRUN_RES}" | awk '{print $2}')
            countly_log "Raw UUID:[$RAW_UUID]"
            # Remove whitespace and such
            BUILD_UUIDS=$(echo "${RAW_UUID}" | xargs | sed 's/ /,/g')
            if [ $? -eq 0 ]; then
                countly_log "Extracted Build UUIDs:[${BUILD_UUIDS}]"
            else
                countly_pass "Extracting Build UUIDs failed!"
            fi
        fi

    else
        countly_pass "Extracting Build UUIDs failed!"
    fi


    # Creating archive of DSYM folder using zip
    DSYM_ZIP_PATH="/tmp/$(date +%s)_${DSYM_FILE_NAME}.zip"
    pushd "${DSYM_FOLDER_PATH}" > /dev/null
    zip -rq "${DSYM_ZIP_PATH}" . -i "${DSYM_FILE_NAME}"
    popd > /dev/null
    if [ $? -eq 0 ]; then
        countly_log "Created archive at $DSYM_ZIP_PATH"
    else
        countly_pass "Creating archive failed!"
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
        countly_pass "dSYM upload failed! Response from the server:[${UPLOAD_RESULT}]"
    fi


    # Removing artifacts
    rm "${DSYM_ZIP_PATH}"
    # return variables to default
    DSYM_FILE_NAME=$INITIAL_DSYM_FILE_NAME
    DSYM_FOLDER_PATH=$INITIAL_FOLDER_PATH

done
exit 0
