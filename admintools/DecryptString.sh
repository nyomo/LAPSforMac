#!/bin/bash
# vim: set ts=4 sw=4 sts=0 ft=sh fenc=utf-8 ff=unix :
#-
#- Usage:
#-  ./DecryptString.sh -e EncryptedString -p Passphrase -s Salt
#-  or
#-  ./DecryptString.sh -e EncryptedString -f Salt:Passphrase
#-
#-  -----
#-  eval $(path/to/EncryptString.sh plainTextString)
#-  decryptedString=$(path/to/DecryptString.sh -e $encryptedString -p $passphrase -s $salt)
#-
if [ -f "/etc/os-release" ]
then
 GREP="/bin/grep"
 OPENSSL="/usr/bin/openssl"
 OPENSSLOPT=" -md md5 "
else
 GREP="/usr/bin/grep"
 OPENSSLOPT=""
 OPENSSL="/usr/local/bin/openssl"
fi


while getopts e:f:s:p:h sw
do
    case "$sw" in
        "e")
               EncryptedString="$OPTARG"
            ;;
        "s")
               Salt="$OPTARG"
            ;;
        "p")
               PassPhrase="$OPTARG"
            ;;
        "f")
               SaltPhrase="$OPTARG"
            ;;
        "h"| * )
            ShowHelp=yes
            ;;
    esac
done

if [ -n "$SaltPhrase" ]; then
    Salt="$( echo "$SaltPhrase" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $1}' )"
    PassPhrase="$( echo "$SaltPhrase" | /usr/bin/tr -d "[:blank:]" | /usr/bin/awk -F: '{print $2}' )"
fi

if [ "$#" -eq 0 ] ||
    [ -z "$EncryptedString" ] ||
    [ -z "$Salt" ] ||
    [ -z "$PassPhrase" ]
then
    ShowHelp=yes
fi
if [ "${ShowHelp:-no}" = yes ]; then
    $GREP ^#- "$0" | /usr/bin/cut -c 4-
    exit 1
fi

echo "$EncryptedString" | $OPENSSL enc -aes256 -d -a -A -S "$Salt" -k "$PassPhrase" $OPENSSLOPT
exit "${PIPESTATUS[1]}"

