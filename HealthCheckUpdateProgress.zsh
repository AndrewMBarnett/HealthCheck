#!/bin/zsh 
# shellcheck shell=bash

####################################################################################################
#
#   Health Check Update Progress with swiftDialog
#   Inventory, Policy Check In, Jamf Protect Check In
#   https://github.com/AndrewMBarnett/HealthCheck
#
####################################################################################################
#
# Version 1.0.0 - 02/20/2024
#   - Update Inventory, Check for Policies, Jamf Protect Check In
#   - Operation Modes for specific modes to call or default for all
#   - Webhook enabled for notifications
#   - Timing for 'Fresh' or 'Stale' check in with Jamf Pro. Check Dan Snelson's post on more details(https://snelson.us/2024/02/inventory-update-progress/)
#   
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Script Version & Client-side Log
scriptVersion="1.0.0"
scriptLog="/var/log/healthCheckTest.log"

# Display an inventory progress dialog, even if an inventory update is not required
displayProgessSansUpdate="true"

# swiftDialog Binary & Logs 
swiftDialogMinimumRequiredVersion="2.4.0.4750"
dialogBinary="/usr/local/bin/dialog"
dialogLog=$( mktemp -u /var/tmp/dialogLog.XXX )
inventoryLog="/var/tmp/HCinventory.log"
jamfBinary="/usr/local/bin/jamf"

# Help message and Infobox variables
dialogVersion=$( /usr/local/bin/dialog --version )
timestamp="$( date '+%Y-%m-%d-%H%M%S' )"
serialNumber=$( ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}' )
computerName=$( scutil --get ComputerName )
modelName=$( /usr/libexec/PlistBuddy -c 'Print :0:_items:0:machine_name' /dev/stdin <<< "$(system_profiler -xml SPHardwareDataType)" )

#Jamf Pro Variables
jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Jamf Pro Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Parameter 4: Seconds To Wait before updating inventory
# 86400 seconds is 1 day; 90061 seconds is 1 day, 1 hour, 1 minute and 1 second.
secondsToWait="${4:-"86400"}"

# Parameter 5: Estimated Total Seconds
estimatedTotalSeconds="${5:-"120"}"

# Parameter 6: Operation Mode [ Inventory | Inventory Force | Policy | Policy Force | Protect | Protect Force |  Self Service | Silent | Uninstall ]
operationMode="${6:-""}"

# Parameter 7: Enables the webhook feature [ true | false ]
webhookEnabled="${7:-""}"

# Paramter 8: Teams webhook URL 
teamsURL="${8:-""}"

# Paramter 9: Slack webhook URL 
slackURL="${9:-""}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Script Human-readable Name
humanReadableScriptName="Health Check"

# Organization's Script Name
scriptName="Health Check"

# Organization's Directory (i.e., where your client-side scripts reside; must previously exist)
organizationDirectory="/private/var/tmp/"

# Inventory Delay File
inventoryDelayFilepath="${organizationDirectory}.${scriptName}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Operating System Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

osVersion=$( sw_vers -productVersion )
osVersionExtra=$( sw_vers -productVersionExtra ) 
osBuild=$( sw_vers -buildVersion )
osMajorVersion=$( echo "${osVersion}" | awk -F '.' '{print $1}' )

# Report RSR sub-version if applicable
if [[ -n $osVersionExtra ]] && [[ "${osMajorVersion}" -ge 13 ]]; then osVersion="${osVersion} ${osVersionExtra}"; fi


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Custom Branding, Overlay Icon, etc
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Desktop/Laptop Icon ###

# Set icon based on whether the Mac is a desktop or laptop
if system_profiler SPPowerDataType | grep -q "Battery Power"; then
    icon="SF=laptopcomputer.and.arrow.down,weight=regular,colour1=black,colour2=white"
else
    icon="SF=desktopcomputer.and.arrow.down,weight=regular,colour1=black,colour2=white"
fi

### Overlay Icon ###

useOverlayIcon="true"								# Toggles swiftDialog to use an overlay icon [ true (default) | false ]

# Create `overlayicon` from Self Service's custom icon (thanks, @meschwartz!)
if [[ "$useOverlayIcon" == "true" ]]; then
    xxd -p -s 260 "$(defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path)"/Icon$'\r'/..namedfork/rsrc | xxd -r -p > /var/tmp/overlayicon.icns
    overlayicon="/var/tmp/overlayicon.icns"
else
    overlayicon=""
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# IT Support Variable 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

### Support Team Details ###

supportTeamName="Add IT Support"
supportTeamPhone="Add IT Phone Number"
supportTeamEmail="Add email"
supportTeamWebsite="Add IT Help site"
supportTeamHyperlink="[${supportTeamWebsite}](https://${supportTeamWebsite})"

# Create the help message based on Support Team variables
helpMessage="If you need assistance, please contact ${supportTeamName}:  \n- **Telephone:** ${supportTeamPhone}  \n- **Email:** ${supportTeamEmail}  \n- **Help Website:** ${supportTeamHyperlink}  \n\n**Computer Information:**  \n- **Operating System:**  $osVersion ($osBuild)  \n- **Serial Number:** $serialNumber  \n- **Dialog:** $dialogVersion  \n- **Started:** $timestamp  \n- **Script Version:** $scriptVersion"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "Inventory Update" Dialog Settings and Features
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

title="Health Check"
message=""
inventoryProgressText="Initializing …"

dialogHealthCheck="$dialogBinary \
--title \"$title\" \
--icon \"$icon\" \
--message \"\" \
--overlayicon \"$overlayicon\" \
--helpmessage \"$helpMessage\" \
--height 400 \
--width 600 \
--windowbuttons min \
--position topright \
--button1text \"Close\" \
--moveable \
--listitem \"Health Check in progress …\" \
--progress \
--titlefont size=20 \
--messagefont size=14 \
--infobox \"**Computer Name:**  \n\n$computerName  \n\n **macOS Version:**  \n\n$osVersion ($osBuild)\" \
--progresstext \"$inventoryProgressText\" \
--quitkey K \
--commandfile \"$dialogLog\" "



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${scriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

function preFlight() {
    updateScriptLog "[PRE-FLIGHT]      ${1}"
}

function notice() {
    updateScriptLog "[NOTICE]          ${1}"
}

function infoOut() {
    updateScriptLog "[INFO]            ${1}"
}

function debugVerbose() {
    if [[ "$debugMode" == "verbose" ]]; then
        updateScriptLog "[DEBUG VERBOSE]   ${1}"
    fi
}

function debug() {
    if [[ "$debugMode" == "true" ]]; then
        updateScriptLog "[DEBUG]           ${1}"
    fi
}

function errorOut(){
    updateScriptLog "[ERROR]           ${1}"
}

function error() {
    updateScriptLog "[ERROR]           ${1}"
    let errorCount++
}

function warning() {
    updateScriptLog "[WARNING]         ${1}"
    let errorCount++
}

function fatal() {
    updateScriptLog "[FATAL ERROR]     ${1}"
    exit 1
}

function quitOut(){
    updateScriptLog "[QUIT]            ${1}"
}

####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}"
    if [[ -f "${scriptLog}" ]]; then
        preFlight "Created specified scriptLog"
    else
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified scriptLog exists; writing log entries to it"
fi




# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})"
preFlight "Initiating …"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Organization Directory
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ -d "${organizationDirectory}" ]]; then
    preFlight "Specified Organization Directory of exists; proceeding …"
else
    fatal "The specified Organization Directory of is NOT found; exiting."
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Operating System
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${osMajorVersion}" -ge 12 ]] ; then
    preFlight "macOS ${osMajorVersion} installed; proceeding ..."
    dialogCheck
else
    preFlight "macOS ${osMajorVersion} installed; updating inventory sans progress …"
    /usr/local/bin/jamf recon -endUsername "${loggedInUser}" --verbose >> "$inventoryLog" &
    exit 0
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / Create Inventory Delay File
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${inventoryDelayFilepath}" ]]; then
    touch "${inventoryDelayFilepath}"
    if [[ -f "${inventoryDelayFilepath}" ]]; then
        preFlight "Created specified inventoryDelayFilepath"
    else
        fatal "Unable to create specified inventoryDelayFilepath; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified inventoryDelayFilepath exists; proceeding …"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / Create Temp DialogLog File
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${dialogLog}" ]]; then
    touch "${dialogLog}"
    if [[ -f "${dialogLog}" ]]; then
        preFlight "Created specified dialogLog"
    else
        fatal "Unable to create specified dialogLog; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified dialogLog exists; proceeding …"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / Create Temp DialogLog File
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${inventoryLog}" ]]; then
    touch "${inventoryLog}"
    if [[ -f "${inventoryLog}" ]]; then
        preFlight "Created specified inventoryLog"
    else
        fatal "Unable to create specified inventoryLog; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    preFlight "Specified inventoryLog exists; proceeding …"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUser}"

    networkUser="$(dscl . -read /Users/$loggedInUser | grep "NetworkUser" | cut -d " " -f 2)"
    preFlight "Network User is $networkUser"

    until { [[ "${loggedInUser}" != "_mbsetupuser" ]] || [[ "${counter}" -gt "180" ]]; } && { [[ "${loggedInUser}" != "loginwindow" ]] || [[ "${counter}" -gt "30" ]]; } ; do
    preFlight "Logged-in User Counter: ${counter}"
    currentLoggedInUser
    sleep 2
    ((counter++))
    done

    loggedInUserFullname=$( id -F "${loggedInUser}" )
    loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
    loggedInUserLastname=$(echo "$loggedInUserFullname" | sed "s/$loggedInUserFirstname//" |  sed 's/,//g')
    loggedInUserID=$( id -u "${loggedInUser}" )
    preFlight "Current Logged-in User First Name: ${loggedInUserFirstname}"
    preFlight "Current Logged-in User Full Name: ${loggedInUserFirstname} ${loggedInUserLastname}"
    preFlight "Current Logged-in User ID: ${loggedInUserID}"

}

preFlight "Check for Logged-in System Accounts …"

currentLoggedInUser

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Complete!"


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Setup List for Health Check Window
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function buildHealthCheckWindow() {

    notice "Create Health Check dialog …"
    eval "$dialogHealthCheck" &

    updateDialog "listitem: delete, title: Health Check in progress …"

    if [[ ${operationMode} == "Self Service" || ${operationMode} == "Inventory" || ${operationMode} == "Inventory Force" ]]; then
        notice "Adding 'Taking Inventory' dialog"
        updateDialog "listitem: add, title: Taking Inventory, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Pending …, status: pending"
    else
        notice "Operation mode did not call for 'Taking Inventory'"
    fi

    if [[ ${operationMode} == "Self Service" || ${operationMode} == "Policy" || ${operationMode} == "Policy Force" ]]; then
        notice "Adding 'Policy Check' dialog"
        updateDialog "listitem: add, title: Checking for updates, icon: SF=laptopcomputer.and.arrow.down,weight=bold, statustext: Pending …, status: pending"
    else
        notice "Operation mode did not call for 'Policy Check'"
    fi    

    if [[ ${operationMode} == "Self Service" || ${operationMode} == "Protect" || ${operationMode} == "Protect Force" ]]; then
        if command -v /Applications/JamfProtect.app/Contents/MacOS/JamfProtect &> /dev/null; then
            infoOut "Jamf Protect is installed. Adding 'Protect' dialog"
            updateDialog "listitem: add, title: Jamf Protect, icon: SF=network.badge.shield.half.filled,weight=bold , statustext: Pending …, status: pending"
        else
            infoOut "Jamf Protect is not installed."
        fi
    fi    

    if [[ ${operationMode} == "Inventory Force" ]]; then
        notice "Operation Mode is Inventory Force, not adding 'Final Recon'"
    else
        notice "Operation Mode is not Inventory Force, adding 'Final Recon'"
        updateDialog "listitem: add, title: Submitting Inventory, icon: SF=icloud.and.arrow.up,weight=bold, statustext: Pending …, status: pending"
    fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "Health Check" dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function recon() {

    notice "Inventory Update dialog …"
    
    SECONDS="0"

    /usr/local/bin/jamf recon -endUsername "${networkUser}" --verbose >> "$inventoryLog" &

    counterRecon=0

    until [[ "$inventoryProgressText" == "Submitting data to"* ]]; do

        progressPercentage=$( echo "scale=2 ; ( $SECONDS / $estimatedTotalSeconds ) * 100" | bc )
        
        if [ $counterRecon -eq 0 ]; then
            updateDialog "listitem: delete, title: Health Check in progress …"
            updateDialog "progress:"
            updateDialog "icon: SF=pencil.and.list.clipboard,weight=bold"
            updateDialog "overlayicon: $overlayicon"
            updateDialog "listitem: title: Taking Inventory, icon: SF=pencil.and.list.clipboard,weight=bold, statustext: Checking …, status: wait"
        fi

        inventoryProgressText=$( tail -n1 "$inventoryLog" | sed -e 's/verbose: //g' -e 's/Found app: \/System\/Applications\///g' -e 's/Utilities\///g' -e 's/Found app: \/Applications\///g' -e 's/Running script for the extension attribute //g' )
        updateDialog "progresstext: Taking inventory of your computer …"

        ((counterRecon++))

    done

        updateDialog "listitem: title: Taking Inventory, statustext: Complete, status: success"
}

function policyErrorCheck(){

            error "Jamf was already checking in. Sending message to try Health Check again."

            dialogPolicyError="$dialogBinary \ 
            --title \"$title\" \
            --icon \"$icon\" \
            --overlayicon \"$overlayIcon\" \
            --message \"Jamf was already checking in. Please run Health Check again\" \
            --windowbuttons min \
            --moveable \
            --position topright \
            --timer 60 \
            --quitkey k \
            --button1text \"Close\" \
            --hidetimerbar \
            --style \"mini\" "

}

function policyCheckIn(){

    notice "Running Policy Check"

    SECONDS="0"

    /usr/local/bin/jamf policy -verbose -forceNoRecon >> "$inventoryLog" &

    counterPolicy=0

     until [[ "$inventoryProgressText" == "No patch policies were found."* || "$inventoryProgressText" == "Removing existing launchd task /Library/LaunchDaemons/com.jamfsoftware.task.bgrecon.plist..."* || "$inventoryProgressText" == "Policy error code: 51"* ]]; do

        progressPercentage=$( echo "scale=2 ; ( $SECONDS / $estimatedTotalSeconds ) * 100" | bc )
        #updateDialog "progress: ${progressPercentage}"

        if [ $counterPolicy -eq 0 ]; then
            updateDialog "listitem: delete, title: Health Check in progress …"
            updateDialog "progress"
            updateDialog "icon: SF=laptopcomputer.and.arrow.down,weight=bold"
            updateDialog "overlayicon: $overlayicon"
            updateDialog "listitem: title: Checking for updates, icon: SF=laptopcomputer.and.arrow.down,weight=bold, statustext: Checking …, status: wait"
        fi

        policyError=$( tail -n1 "$inventoryLog" | grep 'Policy error code: 51')

        if [[ -n "$policyError" ]]; then
            policyErrorCheck
            quitScript
        fi

    inventoryProgressText=$( tail -n1 "$inventoryLog" | sed -e 's/verbose: //g' -e 's/Removing existing launchd task \/Library\/LaunchDaemons\/com.jamfsoftware.task.bgrecon.plist... //g')

    updateDialog "progresstext: ${inventoryProgressText}"

    ((counterPolicy++))

    done

    updateDialog "listitem: title: Checking for updates, statustext: Complete, status: success"
}

function protectCheckIn(){

    notice "Running Protect Check-In"

    SECONDS="0"

    /Applications/JamfProtect.app/Contents/MacOS/JamfProtect checkin >> "$inventoryLog" &

    counterProtect=0
    
    until [[ "$inventoryProgressText" == "verbose: Timeout: 10"* || $SECONDS -ge 20 ]]; do
    
    progressPercentage=$(echo "scale=2 ; ($SECONDS / $estimatedTotalSeconds) * 100" | bc)
    #updateDialog "progress: ${progressPercentage}"
    
        if [ $counterProtect -eq 0 ]; then
            updateDialog "listitem: delete, title: Health Check in progress …"
            updateDialog "progress"
            updateDialog "icon: SF=network.badge.shield.half.filled,weight=bold"
            updateDialog "overlayicon: $overlayicon"
            updateDialog "listitem: title: Jamf Protect, icon: SF=network.badge.shield.half.filled,weight=bold , statustext: Checking …, status: wait"
        fi
    inventoryProgressText=$(tail -n1 "$inventoryLog")

    updateDialog "progresstext: Jamf Protect is a purpose-built endpoint security and mobile threat defense (MTD) for Mac and mobile devices."
    
    ((counterProtect++))

    done

    updateDialog "listitem: title: Jamf Protect, statustext: Complete, status: success"
}

function finalRecon() {

    notice "Running Final Recon"

    SECONDS="0"

    /usr/local/bin/jamf recon -endUsername "${networkUser}" --verbose >> "$inventoryLog" &
    
    counterFinalRecon=0

    until [[ "$inventoryProgressText" == "Submitting data to"* ]]; do

    progressPercentage=$( echo "scale=2 ; ( $SECONDS / $estimatedTotalSeconds ) * 100" | bc )
        
    if [ $counterFinalRecon -eq 0 ]; then
            updateDialog "listitem: delete, title: Health Check in progress …"
            updateDialog "progress"
            updateDialog "icon: SF=icloud.and.arrow.up,weight=bold"
            updateDialog "overlayicon: $overlayicon"
            updateDialog "listitem: title: Submitting Inventory, icon: SF=icloud.and.arrow.up,weight=bold, statustext: Checking …, status: wait"
    fi

    inventoryProgressText=$( tail -n1 "$inventoryLog" | sed -e 's/verbose: //g' -e 's/Found app: \/System\/Applications\///g' -e 's/Utilities\///g' -e 's/Found app: \/Applications\///g' -e 's/Running script for the extension attribute //g' )

    updateDialog "progresstext: Submitting inventory of your computer to Jamf …"

    ((counterFinalRecon++))

    done

    updateDialog "listitem: title: Submitting Inventory, statustext: Complete, status: success"

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Complete "Inventory Update" dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function completeInventoryProgress() {

    infoOut "Checking if Dialog is running or closed for another prompt"

    if pgrep -x "Dialog" >/dev/null; then
        infoOut "Dialog is running."
        infoOut "Complete Inventory Update dialog"
        updateDialog "ontop: enabled"
        updateDialog "listitem: delete, title: Health Check in progress …,"
        updateDialog "icon: SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"
        updateDialog "overlayicon: $overlayicon"
        updateDialog "progress: 100"
        updateDialog "progresstext: Done!"
        infoOut "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        sleep 10
    else
        infoOut "Dialog closed at some point. Calling window to show complete"
        eval "$dialogHealthCheck" &
        infoOut "Complete Inventory Update dialog"
        updateDialog "icon: SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"
        updateDialog "listitem: delete, title: Health Check in progress …"
        updateDialog "listitem: add, title: Health Check, icon: "$overlayicon", statustext: Complete, status: success"
        updateDialog "overlayicon: $overlayicon"
        updateDialog "progress: 100"
        updateDialog "progresstext: Done!"
        infoOut "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        sleep 10
    fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Self Service Inventory Update (i.e., ALWAYS update inventory)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function selfServiceInventoryUpdate() {

    infoOut "Health Check Will run, showing progress via swiftDialog …"
    touch "${inventoryDelayFilepath}"
    buildHealthCheckWindow
    recon
    policyCheckIn

    if command -v /Applications/JamfProtect.app/Contents/MacOS/JamfProtect &> /dev/null; then
        infoOut "Jamf Protect is installed. Adding Protect Function"
        protectCheckIn
    else
        infoOut "Jamf Protect is not installed."
    fi

    finalRecon
    completeInventoryProgress

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# JAMF Display Message (for fallback in case swiftDialog fails to install)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function jamfDisplayMessage() {
    updateScriptLog "Jamf Display Message: ${1}"
    /usr/local/jamf/bin/jamf displayMessage -message "${1}" &
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogInstall() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog..."

    # Create temporary working directory
    workDirectory=$( /usr/bin/basename "$0" )
    tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

    # Download the installer package
    /usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

    # Verify the download
    teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

        /usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        dialogVersion=$( /usr/local/bin/dialog --version )
        preFlight "swiftDialog version ${dialogVersion} installed; proceeding..."

    else

        # Display a so-called "simple" dialog if Team ID fails to validate
        osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Setup Your Mac: Error" buttons {"Close"} with icon caution'
        completionActionOption="Quit"
        exitCode="1"
        quitScript

    fi

    # Remove the temporary working directory when done
    /bin/rm -Rf "$tempDirectory"

}



function dialogCheck() {

    # Output Line Number in `verbose` Debug Mode
    if [[ "${debugMode}" == "verbose" ]]; then preFlight "# # # SETUP YOUR MAC VERBOSE DEBUG MODE: Line No. ${LINENO} # # #" ; fi

    # Check for Dialog and install if not found
    if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then

        preFlight "swiftDialog not found. Installing..."
        dialogInstall

    else

        dialogVersion=$(/usr/local/bin/dialog --version)
        if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
            
            preFlight "swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating..."
            dialogInstall
            
        else

        preFlight "swiftDialog version ${dialogVersion} found; proceeding..."

        fi
    
    fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Jamf Pro URL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function jamfProURL(){

    search_text="Jamf Computer URL:"

if grep -q "$search_text" "$scriptLog" ; then
    jamfProComputerURL=$(grep "$search_text" "$scriptLog"| tail -n 1| awk -F 'Jamf Computer URL:' '{print $2}' | awk '{$1=$1};1')

        if [ -n "$jamfProComputerURL" ]; then
        infoOut "Found, Jamf Computer URL: $jamfProComputerURL"
        else
        infoOut "Jamf Computer URL not found in the script log."
        fi
    
else

    infoOut "Jamf Pro URL not found, searching now"

    reconRaw=$( eval "${jamfBinary} recon ${reconOptions} -verbose | tee -a ${inventoryLog}" )
    computerID=$( echo "${reconRaw}" | grep '<computer_id>' | xmllint --xpath xmllint --xpath '/computer_id/text()' - )
    jamfProComputerURL="${jamfProURL}computers.html?id=${computerID}&o=r"

    infoOut "Jamf Computer URL: $jamfProComputerURL"

fi   

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Webhook Message (Microsoft Teams or Slack) 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function webHookMessage() {

if [[ $slackURL == "" ]]; then
    infoOut "No slack URL configured"
else
    if [[ $supportTeamHyperlink == "" ]]; then
        supportTeamHyperlink="https://www.slack.com"
    fi
    infoOut "Sending Slack WebHook"
    curl -s -X POST -H 'Content-type: application/json' \
        -d \
        '{
	"blocks": [
		{
			"type": "header",
			"text": {
				"type": "plain_text",
				"text": "'${scriptName}'",
			}
		},
		{
			"type": "divider"
		},
		{
			"type": "section",
			"fields": [
				{
					"type": "mrkdwn",
					"text": ">*Serial Number and Computer Name:*\n>'"$serialNumber"' on '"$computerName"'"
				},
                		{
					"type": "mrkdwn",
					"text": ">*Computer Model:*\n>'"$modelName"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Current User:*\n>'"$loggedInUser"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Updates:*\n>'"$formatted_result"'"
				},
				{
					"type": "mrkdwn",
					"text": ">*Errors:*\n>'"$formatted_error_result"'"
				},
                		{
					"type": "mrkdwn",
					"text": ">*Computer Record:*\n>'"$jamfProComputerURL"'"
				}
			]
		},
		{
		"type": "actions",
			"elements": [
				{
					"type": "button",
					"text": {
						"type": "plain_text",
						"text": "View computer in Jamf Pro",
						"emoji": true
					},
					"style": "primary",
					"action_id": "actionId-0",
					"url": "'"$jamfProComputerURL"'"
				}
			]
		}
	]
}' \
        $slackURL
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Teams notification (Credit to https://github.com/nirvanaboi10 for the Teams code)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# URL to an image to add to your notification
activityImage="https://raw.githubusercontent.com/AndrewMBarnett/HealthCheck/main/Images/macbook_apple_computer_screen.jpg"


if [[ $teamsURL == "" ]]; then
    infoOut "No teams Webhook configured"
else
    if [[ $supportTeamHyperlink == "" ]]; then
        supportTeamHyperlink="https://www.microsoft.com/en-us/microsoft-teams/"
    fi
    infoOut "Sending Teams WebHook"
    jsonPayload='{
	"@type": "MessageCard",
	"@context": "http://schema.org/extensions",
	"themeColor": "0076D7",
	"summary": "'"$scriptName"'",
	"sections": [{
		"activityTitle": "'${scriptName}'",
        "activitySubtitle": "'${jamfProURL}'",
		"activityImage": "'${activityImage}'",
		"facts": [{
			"name": "Computer Name (Serial Number):",
			"value": "'${computerName}' ('"$serialNumber"')"
		}, {
			"name": "Computer Model:",
			"value": "'"$modelName"'"
		}, {
			"name": "User:",
			"value": "'${loggedInUserFirstname}' '${loggedInUserLastname}' ('"$loggedInUser"')"
		}, {
			"name": "Operation Mode:",
			"value": "'${operationMode}'"
        }],
		"markdown": true
	}],
	"potentialAction": [{
		"@type": "OpenUri",
		"name": "View in Jamf Pro",
		"targets": [{
			"os": "default",
			"uri":
			"'"$jamfProComputerURL"'"
		}]
	}]
}'

    # Send the JSON payload using curl
    curl -s -X POST -H "Content-Type: application/json" -d "$jsonPayload" "$teamsURL"

fi

}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {

    case ${webhookEnabled} in

    "true" ) # Notify on sucess and failure 
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, continuing ..."
            jamfProURL
            webHookMessage
    ;;

    "false" ) # Don't notify
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
    ;;

    * ) # Catch-all
        infoOut "Webhook Enabled flag set to: ${webhookEnabled}, skipping ..."
        ;;

esac

    notice "*** QUITTING ***"
    updateDialog "quit: "

    # Remove dialogLog
    if [[ -f "${dialogLog}" ]]; then
        infoOut "Removing ${dialogLog} …"
        rm "${dialogLog}"
    fi

    # Remove inventoryLog
    if [[ -f "${inventoryLog}" ]]; then
        infoOut "Removing ${inventoryLog} …"
        rm "${inventoryLog}"
    fi

    infoOut "Goodbye!"
    exit "${1}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateDialog() {
    echo "${1}" >> "${dialogLog}"
    sleep 0.4
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Uninstall
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function uninstall() {

    warning "*** UNINSTALLING ${humanReadableScriptName} ***"
    info "Reset inventoryDelayFilepath … "
    infoOut "Removing '${inventoryDelayFilepath}' … "
    rm -f "${inventoryDelayFilepath}"
    infoOut "Removed '${inventoryDelayFilepath}'"
    infoOut "Uninstalled all ${humanReadableScriptName} configuration files"
    notice "Thanks for using ${humanReadableScriptName}!"

}



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# "Seconds To Wait" Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

testFileSeconds=$( date -j -f "%s" "$( stat -f "%m" $inventoryDelayFilepath)" +"%s" )
nowSeconds=$( date +"%s" )
ageInSeconds=$((nowSeconds-testFileSeconds))
secondsToWaitHumanReadable=$( printf '"%dd, %dh, %dm, %ds"\n' $((secondsToWait/86400)) $((secondsToWait%86400/3600)) $((secondsToWait%3600/60)) $((secondsToWait%60)) )
ageInSecondsHumanReadable=$( printf '"%dd, %dh, %dm, %ds"\n' $((ageInSeconds/86400)) $((ageInSeconds%86400/3600)) $((ageInSeconds%3600/60)) $((ageInSeconds%60)) )



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Evaluate "Seconds To Wait" and "Operation Mode" before updating inventory
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "*** Evaluating 'Seconds To Wait' and 'Operation Mode' before updating inventory ***"
infoOut "Set to wait ${secondsToWaitHumanReadable} and inventoryDelayFilepath was created ${ageInSecondsHumanReadable} ago"
infoOut "Operation Mode: '${operationMode}'"

if [[ ${ageInSeconds} -le ${secondsToWait} ]]; then
    
    # Current Inventory is "fresh" (i.e., inventory isn't yet stale enough to be updated)

    case ${operationMode} in

        "Self Service" ) # When executed via Self Service, *always* update inventory 
            selfServiceInventoryUpdate
            quitScript "0"
            ;;

        "Silent" ) # Don't leverage swiftDialog
            notice "Inventory will NOT be updated …"
            quitScript "0"
            ;;
        
        "Inventory" ) # Update inventory, with swiftDialog
            infoOut "Inventory will NOT updated …"
            quitScript "0"
            ;;

        "Inventory Force" ) # Update inventory, with swiftDialog
            infoOut "Inventory WILL BE updated, WITH swiftDialog …"
            buildHealthCheckWindow
            recon
            completeInventoryProgress
            quitScript "0"
            ;;
        
        "Policy" ) # Update inventory, with swiftDialog
            infoOut "Inventory will NOT updated …"
            quitScript "0"
            ;;

        "Policy Force" ) # Update Policy, with swiftDialog
            infoOut "Forcing Policy check in …"
            buildHealthCheckWindow
            policyCheckIn
            finalRecon
            completeInventoryProgress
            quitScript "0"
            ;;

        "Protect" ) # Update inventory, sans swiftDialog
            infoOut "NOT Checking in with Jamf Protect …"
            quitScript "0"
            ;; 

        "Protect Force" ) # Update inventory, sans swiftDialog
            infoOut "Forcing Jamf Protect check in …"
            buildHealthCheckWindow
            protectCheckIn
            finalRecon
            completeInventoryProgress
            quitScript "0"
            ;; 

        "Uninstall" ) # Remove client-side files
            notice "Sorry to see you go …"
            uninstall
            quitScript "0"
            ;;

        * | "Default" ) # Default Catch-all
            notice "Inventory will NOT be updated …"
            if [[ "${displayProgessSansUpdate}" == "true" ]]; then
                infoOut "Display 'Inventory update not required' dialog …"
                eval "$dialogHealthCheck" &
                updateDialog "progress: 1"
                updateDialog "icon: SF=checkmark.circle.fill,weight=bold,colour1=#00ff44,colour2=#075c1e"
                updateDialog "message: Inventory update not required"
                updateDialog "progress: 100"
                updateDialog "progresstext: "
                infoOut "So long!"
                sleep 3
            fi
            quitScript "0"
            ;;

    esac

elif [[ ${ageInSeconds} -ge ${secondsToWait} ]]; then

    # Current Inventory is "stale" (i.e., inventory is stale and should be updated)

    case ${operationMode} in

        "Self Service" ) # When executed via Self Service, *always* update Health Check 
            selfServiceInventoryUpdate
            quitScript "0"
            ;;

        "Silent Inventory" ) # Update inventory, sans swiftDialog
            infoOut "Inventory WILL BE updated, sans swiftDialog …"
            /usr/local/bin/jamf recon -endUsername "${loggedInUser}"
            quitScript "0"
            ;;

        "Inventory" ) # Update inventory, with swiftDialog
            infoOut "Inventory WILL BE updated, WITH swiftDialog …"
            buildHealthCheckWindow
            finalRecon
            completeInventoryProgress
            quitScript "0"
            ;;

        "Policy" ) # Update inventory, with swiftDialog
            infoOut "Inventory WILL BE updated, WITH swiftDialog …"
            buildHealthCheckWindow
            policyCheckIn
            finalRecon
            completeInventoryProgress
            quitScript "0"
            ;;

        "Protect" ) # Update inventory, sans swiftDialog
            infoOut "Checking in with Jamf Protect, sans swiftDialog …"
            /Applications/JamfProtect.app/Contents/MacOS/JamfProtect checkin
            quitScript "0"
            ;;   

        "Uninstall" ) # Remove client-side files
            infoOut "Sorry to see you go …"
            uninstall
            quitScript "0"
            ;;

        * | "Default" ) # Default Catch-all
            infoOut "Inventory WILL BE updated, showing progress via swiftDialog …"
            touch "${inventoryDelayFilepath}"
            selfServiceInventoryUpdate
            quitScript "0"
            ;;

    esac

fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Sideways Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

quitScript "1"
