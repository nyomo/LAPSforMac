# LAPSforMac
Local Administrator Password Solution for Mac

## Purpose
macOS_LAPS.sh randomly changes the password of admin account of macOS computer and updates the inventory record of the macOS computer. You can securely manage the administrator password of the macOS computers being managed.

## Requirement
- macOS 10.14, macOS 10.15 and macOS 11.0 or later
- Every macOS computer has same initial password when it enrolled.

## Jamf Computer Extension Attribute

    Display Name: {extAttName}
    Description: This attribute will display the current Local Admin Password of the device.
    Data Type: String
    Inventory Display: General
    Input Type: Text Field
    Recon Display: User and Location (Not Used)

*Notes: The field is editable to allow for troubleshooting or manually overriding the password.*

## Jamf API User

    Username: {APIusername}
    Access Level: Full Access
    Privilege Set: Custom
    Access Status: Enabled
    Full Name: {APIusername}
    Email Address: (Not Used)
    Password: {APIpassword}
    Privileges:
    JSS Objects:
    Computer Extension Attributes: RU
    Computers: RU
    Users: U

*Notes: For Jamf permissions C=Create, R=Read, U=Update, D=Delete (Not sure why the "Users" permission is needed. After much trial and error, and a call to JAMF, I discovered this permission set was required to properly read and update the Computer tables)*

## Policy parameters
- Parameter  4: API User Name
- Parameter  5: API User Password. It must be encrypted.
- Parameter  6: Loacal Administrator User Name
- Parameter  7: Initial Encrypted Password of Loacal Administrator User
- Parameter  8: Extend Attribute Name which stores encrypted password string.
- Parameter  9: Salt & Passphrase for decrypt API user password. (format:: salt:passphrase)
- Parameter 10: Salt & Passphrase for encrypt/decrypt Local Administrator User password.  (format:: salt:passphrase)
- Parameter 11: Salt & Passphrase for decrypt LAPS user's initial password.  (format:: salt:passphrase)

## Log Location
You will find this script log as `/Library/Logs/Jamf_LAPS.YYYYMMDD.log`.

## Admintools
### DecryptString.sh
```
Usage:
 ./DecryptString.sh -e EncryptedString -p Passphrase -s Salt
 or
 ./path/to/DecryptString.sh -e EncryptedString -f Salt:Passphrase

 -----
 eval $(path/to/EncryptString.sh plainTextString)
 decryptedString=$(path/to/DecryptString.sh -e $EncryptedString -p $Passphrase -s $Salt)
```
### EncryptString.sh
```
Usage:
 ./EncryptString.sh StringToEncrypt

 ------
 eval $( path/to/EncryptString.sh StringToEncrypt )
 echo "$EncryptedString $Salt $Passphrase $Saltphrase"
 ```
