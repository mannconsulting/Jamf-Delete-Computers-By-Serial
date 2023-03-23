#!/bin/zsh
###############################################################################
# Jamf Delete Computers By Serial
# Created by:    Mann Consulting (support@mann.com)
# Summary:       Script to bulk delete computers by serial number from Jamf Pro.
#
# Documentation: https://mann.com/docs
#
# Note:	         This script released publicly, but intended for Mann Consulting's Jamf Pro MSP customers.
#                If you'd like support sign up at https://mann.com/jamf or email support@mann.com for more details
###############################################################################

if [[ -z $1 ]]; then
  echo "No import file found, please specify an input file. Example: ./Jamf\ Delete\ Computers\ By \ Serial.sh /path/to/file/with"
  exit
fi

echo -n "Enter your Jamf Pro server URL : "
read jamfpro_url
echo -n "Enter your Jamf Pro user account : "
read jamfpro_user
echo -n "Enter the password for the $jamfpro_user account: "
read -s jamfpro_password
echo

jamfpro_url=${jamfpro_url%%/}
fulltoken=$(curl -s -X POST -u "${jamfpro_user}:${jamfpro_password}" "${jamfpro_url}/api/v1/auth/token")
authorizationToken=$(plutil -extract token raw - <<< "$fulltoken" )
serials=("${(@f)$(cat $1)}")

if [[ -z $serials ]]; then
  echo "No serial numbers found, exiting. Please use one serial number only per line."
  exit
fi

echo -n "Getting Computer IDs"

for i in $serials; do
  echo -n "."
  computerInfo=$(curl -s -X GET "$jamfpro_url/JSSResource/computers/serialnumber/$i" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken" | xmllint --format - 2> /dev/null)
  computerID=$(echo $computerInfo | grep -m1 id | cut -d '>' -f2 | cut -d '<' -f1)
  if [[ -z $computerID ]]; then
    computersMissing+=($i)
    continue
  fi
  lastcheckin=$(echo $computerInfo | grep -m1 last_contact_time_epoch | cut -d '>' -f2 | cut -d '<' -f1)
  lastcheckinDelta=$((((`date -u +%s` * 1000) - $lastcheckin)/86400000))
  if [[ $lastcheckinDelta -le 14 ]]; then
    computerIDsActive+=($computerID)
    computersToDoActive+=($i)
    unset $computerID
  else
    computerIDs+=($computerID)
    unset $computerID
    computersToDo+=($i)
  fi
done

echo

if [[ -z $computersToDo ]]; then
  echo "No computers found in Jamf Pro to delete, exiting."
  exit
fi

echo "WARNING: There are ${#computersToDoActive[@]} active computers (less than 14 days checkin) with the following Serial Numbers: $computersToDoActive"
echo -n "Would you like to delete these active computers? [yes/NO]: "
read deleteActive

if [[ ${deleteActive:l} != "yes" ]]; then
  echo "Skipping active computers."
else
  computerIDs+=($computerIDsActive)
  computersToDo+=($computersToDoActive)
fi
echo
echo "Deleting ${#computerIDs[@]} computers with the following computer IDs: $computerIDs"
echo
echo "Deleting ${#computersToDo[@]} computers with the following Serial Numbers: $computersToDo"
echo
echo "${#computersMissing[@]} computers with the following serial numbers are not in Jamf: $computersMissing"
echo
echo -n "Are you sure you want to proceed? This action is irreversable. [yes/NO]: "
read delete

if [[ ${delete:l} != "yes" ]]; then
  echo "You chose not to delete the computers, exiting."
  exit
fi

for i in $computerIDs; do
  echo -n "Deleting computer with ID $i..."
  curlStatus=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$jamfpro_url/JSSResource/computers/id/$i" -H "accept: application/xml" -H "Authorization: Bearer $authorizationToken")
  if [[ $curlStatus == 200 ]]; then
    echo "Success!"
  else
    echo "Possible Failure, wait and check back."
  fi
  sleep 1
done
echo
echo "########## Summary ##########"
echo "Deleted ${#computersToDo[@]} computers with the following Serial numbers: $computersToDo"
echo
echo "${#computersMissing[@]} computers with the following serial numbers are not in Jamf: $computersMissing"