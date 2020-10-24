#!/bin/bash
# vim: set ts=4 sw=4 sts=0 ft=sh fenc=utf-8 ff=unix :
#
# https://github.com/NU-ITS/LAPSforMac/blob/master/LICENSE
#
#-
#- Usage:
#-  macOS_LAPS.sh is designed to be used via JamfPro.
#-  macOS version 10.14 or later. ( Because I tested this with macOS 10.14 Mojave or later ).
#-

# Debug flag
if [ "$1" = "debug_mode" ]; then
    debug=on
fi

# Show help.
if [ "$#" -eq 0 ]; then
    /usr/bin/grep ^#- "$0" | /usr/bin/cut -c 4-
    exit 0
fi

# Check OS Version.
osversion="$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. 'V = $1 * 100 + $2 {print V}' )"
if [ "$osversion" -lt 1014 ]; then
    /usr/bin/grep ^#- "$0" | /usr/bin/cut -c 4-
    exit 1
fi

####################################################################################################
# FUNCTIONS
function scriptLogging(){
    # `scriptLogging "your message"` then logging file and put it std-out.
    # `scriptLogging "your message" 2` then logging file and put it std-err.
    # Other than 2 is ignored.
    local logfile scriptname timestamp label mode
    logfile="/Library/Logs/Jamf_LAPS.$( /bin/date +%F).log"
    scriptname="$( /usr/bin/basename "$0" )"
    timestamp="$( /bin/date "+%F %T" )"
    mode="$2"
    case "${mode:-1}" in
        2 )
            label="[error]"
            echo "$timestamp $scriptname $label $1" | /usr/bin/tee -a "$logfile" >&2
            ;;
        * )
            label="[info]"
            echo "$timestamp $scriptname $label $1" | /usr/bin/tee -a "$logfile"
            ;;
    esac
}

function decryptString() {
    local decryptString encryptedString salt passphrase errmsgfile errmsg
    encryptedString="$1"
    salt="$2"
    passphrase="$3"
    errmsgfile="$( /usr/bin/mktemp )"
    decryptString="$( echo "$encryptedString" | /usr/bin/openssl enc -aes256 -d -a -A -S "$salt" -k "$passphrase" 2> "$errmsgfile" )"

    if [ -s "$errmsgfile" ]; then
        errmsg="Decrypt failed: $( /bin/cat "$errmsgfile" )"
        scriptLogging "$errmsg" 2
    else
        echo "$decryptString"
    fi
    /bin/rm -f "$errmsgfile"
}

function retrievePassword(){
    local apiUserName apiUserPasswd udid extensionAttribute response httpStatus apiHostURL
    apiUserName="$1"
    apiUserPasswd="$2"
    udid="$3"
    extensionAttribute="$4"
    apiHostURL="$5"

    response="$( /usr/bin/curl -s -f -u "${apiUserName}:${apiUserPasswd}" -H "Accept: application/xml" \
                "${apiHostURL}/JSSResource/computers/udid/${udid}/subset/extension_attributes" \
                -w "HTTPSTATUS:%{http_code}" )"

    if [ "${debug:-off}" = on ]; then
        echo "$response" > /tmp/response.xml
    fi

    httpStatus=$( echo "$response" | /usr/bin/tr -d '\n' | /usr/bin/sed -e 's/.*HTTPSTATUS://')
    if [ "$httpStatus" -ne 200 ];then
        scriptLogging "Cannot get stored password. JSS api call is failed with HTTP status is $httpStatus." 2
        exit 1
    fi

    if [ "$osversion" -le 1015 ]; then
        echo "$response" | /usr/bin/sed -e 's/HTTPSTATUS\:.*//g' | \
            /usr/bin/xpath "//extension_attribute[name=\"$extensionAttribute\"]/value/text()" 2>/dev/null
    else
        # mac OS 11.0 Big Sur or later
        echo "$response" | /usr/bin/sed -e 's/HTTPSTATUS\:.*//g' | \
            /usr/bin/xpath -e "//extension_attribute[name=\"$extensionAttribute\"]/value/text()" 2>/dev/null
    fi
}

function uploadPassword(){
    local apiUserName apiUserPasswd udid extensionAttribute uploadEncryptedPasswd xmlString apiHostURL
    apiUserName="$1"
    apiUserPasswd="$2"
    udid="$3"
    extensionAttribute="$4"
    uploadEncryptedPasswd="$5"
    apiHostURL="$6"

    xmlString="$(
    cat <<_XML
<?xml version="1.0" encoding="UTF-8"?>
<computer>
    <extension_attributes>
        <extension_attribute>
            <name>${extensionAttribute}</name>
            <value>${uploadEncryptedPasswd}</value>
        </extension_attribute>
    </extension_attributes>
</computer>
_XML
    )"

    /usr/bin/curl -s -u "${apiUserName}:${apiUserPasswd}" -X PUT -H "Content-Type: text/xml" -d "$xmlString" \
                  "${apiHostURL}/JSSResource/computers/udid/${udid}" > /dev/null 2>&1
    return $?
}

function changePassword(){
    local userName old new result sysadminlog
    userName="$1"
    old="$2"
    new="$3"
    sysadminlog="$( /usr/bin/mktemp )"
    /usr/sbin/sysadminctl -adminUser "$userName" -adminPassword "$old" \
        -resetPasswordFor "$userName" -newPassword "$new" > "$sysadminlog" 2>&1
    result=$?
    if [ "$result" -ne 0 ]; then
        scriptLogging "Failed to change password of $userName" 2
        scriptLogging "$( /bin/cat "$sysadminlog" )" 2
        rm -f "$sysadminlog"
        exit 1
    else
        scriptLogging "$( /usr/bin/awk -F'] ' '{print $2}' "$sysadminlog" | /usr/bin/tr -d '\n-' )"
        rm -f "$sysadminlog"
    fi

    /usr/bin/dscl /Local/Default -authonly "$userName" "$new" 2> /dev/null
    result=$?
    if [ "$result" -eq 0 ]; then
        scriptLogging "Password of $userName has changed in success."
    else
        scriptLogging "Given password of $userName is wrong. This is serious." 2
        exit 1
    fi
}

####################################################################################################
# REQUIRMENTS
jamfPlist=/Library/Preferences/com.jamfsoftware.jamf.plist
if [ -f "$jamfPlist" ]; then
    apiURL="$( /usr/libexec/PlistBuddy -c "print jss_url" "$jamfPlist" )"
fi
if [ -z "$apiURL" ]; then
    scriptLogging "Failed to get api URL from $jamfPlist" 2
    exit 1
fi

HWUUID="$( /usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }' )"

####################################################################################################
#- Jamf Parameters
#- - Parameter  4: API User Name
apiUser="$4"
if [ -z "$apiUser" ]; then
    scriptLogging "API User was not given via parameter 4" 2
    exit 1
fi

#- - Parameter  5: API User Password. It must be encrypted.
apiEncryptedPass="$5"
if [ -z "$apiEncryptedPass" ]; then
    scriptLogging "API User's passowrd was not given via parameter 5." 2
    exit 1
fi

#- - Parameter  6: Loacal Administrator User Name
laUserName="$6"
if [ -z "$laUserName" ]; then
    scriptLogging "LAPS user name was not given via parameter 6." 2
    exit 1
fi
localAccountCheck="$( /usr/sbin/dseditgroup -o checkmember -m "$laUserName" localaccounts 2>&1 )"
result=$?
if [ "$result" -ne 0 ]; then
    scriptLogging "${localAccountCheck}. Return Code (dserr) is ${result}." 2
    exit 1
fi

#- - Parameter  7: Initial Encrypted Password of Loacal Administrator User
initialEncryptedPassForLadminUser="$7"
if [ -z "$initialEncryptedPassForLadminUser" ]; then
    scriptLogging "Initial Encrypted Password of LAPS User was not given via parameter 7." 2
    exit 1
fi

#- - Parameter  8: Extend Attribute Name.
extensionAttributeName="$8"
if [ -z "$extensionAttributeName" ]; then
    scriptLogging "Extend Attribute Name was not given via parameter 8." 2
    exit 1
fi

#- - Parameter  9: Salt & Passphrase for decrypt API user password.
#-                 format:: salt:passphrase
apiSaltPass="$9"
if [ -z "$apiSaltPass" ]; then
    scriptLogging "Salt & Passphrase for decrypt API user password was not given via parameter 9" 2
    exit 1
fi
saltAPI="$( echo "$apiSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $1}' )"
passAPI="$( echo "$apiSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $2}' )"

if [ -z "$saltAPI" ] || [ -z "$passAPI" ]; then
    scriptLogging "Invalit string format given via parameter 9" 2
    exit 1
fi

#- - Parameter 10: Salt & Passphrase for encrypt/decrypt Local Administrator User password.
#-                 format:: salt:passphrase
laSaltPass="${10}"
if [ -z "$laSaltPass" ]; then
    scriptLogging "Salt & Passphrase for decrypt LAPS user password was not given via parameter 10" 2
    exit 1
fi
laSalt="$( echo "$laSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $1}' )"
laPass="$( echo "$laSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $2}' )"

if [ -z "$laSalt" ] || [ -z "$laPass" ]; then
    scriptLogging "Invalit string format given via parameter 10" 2
    exit 1
fi

#- - Parameter 11: Salt & Passphrase for decrypt LAPS user's initial password.
#-                 format:: salt:passphrase
initialLaSaltPass="${11}"
if [ -z "$initialLaSaltPass" ]; then
    scriptLogging "Salt & Passphrase for decrypt LAPS user's initial password was not given via parameter 11" 2
    exit 1
fi
initLaSalt="$( echo "$initialLaSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $1}' )"
initLaPass="$( echo "$initialLaSaltPass" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $2}' )"

if [ -z "$initLaSalt" ] || [ -z "$initLaPass" ]; then
    scriptLogging "Invalit string format given via parameter 11" 2
    exit 1
fi

####################################################################################################
# Decode API user Password
apiPass="$( decryptString "$apiEncryptedPass" "$saltAPI" "$passAPI" )"
if [ -z "$apiPass" ]; then
    scriptLogging "Failed to decrypt API user's password" 2
    exit 1
fi

####################################################################################################
# Retrieve LAPS user password from Extent Attribute
previousEncryptedPassword="$( retrievePassword "$apiUser" "$apiPass" "$HWUUID" "$extensionAttributeName" "${apiURL%%/}" )"
if [ -n "$previousEncryptedPassword" ]; then
    scriptLogging "Retrieved previous password is $previousEncryptedPassword (encrypted)."
    retrievedPassword="$( decryptString "$previousEncryptedPassword" "$laSalt" "$laPass" )"
else
    scriptLogging "Could not get previous password. Try initial password for ${laUserName}."
    scriptLogging "Try to use initial password for ${laUserName}: $initialEncryptedPassForLadminUser (encrypted)."
    retrievedPassword="$( decryptString "$initialEncryptedPassForLadminUser" "$initLaSalt" "$initLaPass" )"
fi
if [ -z "$retrievedPassword" ]; then
    scriptLogging "Failed to decrypt previous password of $laUserName" 2
    exit 1
fi

####################################################################################################
# Check current password with Retrieved password
/usr/bin/dscl /Local/Default -authonly "$laUserName" "$retrievedPassword" 2> /dev/null
returnCode=$?
if [ "$returnCode" -ne 0 ]; then
    scriptLogging "Retrieved password for $laUserName is not match current password. dserr: $returnCode" 2
    exit $returnCode
fi
scriptLogging "Current password has match with retrieved password."

####################################################################################################
# Make a new password
lengthOfPassword=16
newpassword="$( /usr/bin/openssl rand -base64 $(( lengthOfPassword * 10 )) | /usr/bin/tr -d 'OoIi1lLS/+=\n' | /usr/bin/head -c "$lengthOfPassword" )"

####################################################################################################
# Encrypt New Password
encryptedPassword="$( echo "$newpassword" | /usr/bin/openssl enc -aes256 -a -A -S "$laSalt" -k "$laPass" )"
if [ -z "$encryptedPassword" ]; then
    scriptLogging "Failed to encrypt new password. Why?" 2
    exit 1
fi
# If you want to log new password, remove ':' at start of next line.
: scriptLogging "New password: $encryptedPassword (Encrypted)"

####################################################################################################
# Change password with new one.
changePassword "$laUserName" "$retrievedPassword" "$newpassword"

####################################################################################################
# Update Extent Attribute with New Password
uploadPassword "$apiUser" "$apiPass" "$HWUUID" "$extensionAttributeName" "$encryptedPassword" "${apiURL%%/}"
returnCode=$?
if [ "$returnCode" -ne 0 ]; then
    scriptLogging "Failed to upload." 2
    scriptLogging "Roll back with previous one."
    changePassword "$laUserName" "$newpassword" "$retrievedPassword"
    exit 1
fi

try="$( retrievePassword "$apiUser" "$apiPass" "$HWUUID" "$extensionAttributeName" "${apiURL%%/}" )"
if [ "$try" = "$encryptedPassword" ]; then
    scriptLogging "Retrieve test passed."
    scriptLogging "Done."
    exit 0
else
    scriptLogging "Retrieve test failed. Get unexpected string." 2
    scriptLogging "Retrieved String: $try" 2
    scriptLogging "Expected String: $encryptedPassword" 2
    scriptLogging "Done in error." 2
    exit 1
fi
