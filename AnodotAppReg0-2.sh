#!/usr/bin/env bash

# Display a banner

echo -e "
     /\                   | |     | |  
    /  \   _ __   ___   __| | ___ | |_ 
   / /\ \ | '_ \ / _ \ / _\` |/ _ \| __|
  / ____ \| | | | (_) | (_| | (_) | |_ 
 /_/    \_\_| |_|\___/ \__,_|\___/ \__|"

echo -e "\n AI Business Analytics Platform"


echo -e "\n Welcome to our automated onboarding process. This streamlined procedure encompasses the following steps:
          1. erify necessary permissions.
          2. Create a Blob Storage container and schedule an export process to transfer files.
          3. Automatically register the application and assign appropriate roles, including Azure Blob Storage Reader and Azure Monitoring Reader.
          4. Generate a client secret for the application.
 We have invested significant effort to minimize security risks and reduce our digital footprint, ensuring a reliable and professional experience for our users."
sleep 5s

# Authenticate the user and retrieve the subscription ID
az login> /dev/null

# Prompt the user to enter their email address
read -p "Enter your email address: " email

# Retrieve the objectId of the user with the specified email address
objectId=$(az ad user list --query "[?signInNames.emailAddress=='$email'].id" --output tsv)

# Echo the value of the objectId variable
echo $objectId

# Retrieve the userId of the user with the specified email address
userId=$(az ad user list --query "[?signInNames.emailAddress=='$email'].userPrincipalName" --output tsv)

# Echo the value of the userId variable
echo $userId

#-------------------------------
### CHECKS
#-------------------------------

# Set the length of the loading bar
BAR_LENGTH=50

# Set the character used for the loading bar
BAR_CHAR="▓"

# Define the print_progress_bar function
print_progress_bar() {
  local filled=""
  local empty=""
  local progress_bar_width=$BAR_LENGTH

  for ((i = 0; i < $1; i++)); do
    filled+="$BAR_CHAR"
  done

  for ((i = 0; i < $((progress_bar_width - $1)); i++)); do
    empty+=" "
  done

  printf "|%-*s|" "$progress_bar_width" "$filled$empty"
}

# Define the loading function
function loading() {
  local duration=$1
  local sleep_duration=0.1
  local max_iterations=$((duration * 10))
  local iteration=0

  while [ $iteration -lt $max_iterations ]; do
    printf "\r%s" "$(print_progress_bar $((iteration * BAR_LENGTH / max_iterations)))"
    sleep $sleep_duration
    iteration=$((iteration + 1))
  done

  printf "\n"
}


# loading 2

######## check if the user has owner permission on  subscription level
echo "Checking if the user has owner permission on the subscription level..."
loading 2

role=$(az role assignment list --include-classic-administrators --query "[?principalName=='$(az account show --query 'user.name' -o tsv)' && roleDefinitionName=='Owner'].principalName" -o tsv)

if [[ -z "$role" ]]; then
  echo "The logged-in user does not have 'Owner' permission on this subscription"
else
  echo "The logged-in user has 'Owner' permission on this subscription"
fi

########### check if the user has global or user administrator permission
echo "Checking if the user has global or user administrator permission..."
loading 2

if az role assignment list --include-classic-administrators --query "[?principalName=='$(az account show --query 'user.name' -o tsv)' && (roleDefinitionName=='Global administrator' || roleDefinitionName=='User administrator')]" | grep -q .; then
  has_permission="yes"
else
  has_permission="no"
fi

if [[ "$has_permission" == "yes" ]]; then
  echo "The logged-in user has 'Global administrator' or 'User administrator' role on this subscription"
else
  echo "The logged-in user does not have 'Global administrator' or 'User administrator' role on this subscription"
fi

################# check if the user has Billing Reader role assigned
echo "Checking if the user has Billing Reader role assigned..."
loading 2

if az role assignment list --all --query "[?roleDefinitionName=='Billing Reader' && principalName=='$(az account show --query user.name -o tsv)']" --output tsv | grep -q "Billing Reader"; then
  has_permission="yes"
else
  has_permission="no"
fi

if [[ "$has_permission" == "yes" ]]; then
  echo "User has Billing Reader role assigned"
else
  echo "User does not have Billing Reader role assigned"
fi

###################### check if the user has Monitoring Reader role assigned
echo "Checking if the user has Monitoring Reader role assigned..."
loading 2

if az role assignment list --all --query "[?roleDefinitionName=='Monitoring Reader' && principalName=='$(az account show --query user.name -o tsv)']" | grep -q .
then
  has_permission="yes"
else
  has_permission="no"
fi

if [[ "$has_permission" == "yes" ]]; then
  echo "User has Monitoring Reader role assigned"
else
  echo "User does not have Monitoring Reader role assigned"
fi


# ###################### check if the user has Security Reader role assigned
# echo "Checking if the user has Security Reader role assigned..."
# loading 2

# if az role assignment list --all --query "[?roleDefinitionName=='Security Reader' && principalName=='$(az account show --query user.name -o tsv)']" --output tsv | grep -q "Security Reader"; then
#   has_permission="yes"
# else
#   has_permission="no"
# fi

# if [[ "$has_permission" == "yes" ]]; then
#   echo "User has Security Reader role assigned"
# else
#   echo "User does not have Security Reader role assigned"
# fi

echo "All checks completed."

############################################
#-------------------------------
### RESOURCE GROUP SELECTION OR CREATION
#-------------------------------
############################################

# get the list of resource groups
resource_groups=($(az group list --query '[].name' -o tsv))

# prompt the user to select or create a resource group
echo "Select a resource group or create a new one:"
options=("Create new resource group" "${resource_groups[@]}") > /dev/null
select selected_rg in "${options[@]}" 
do
  case $selected_rg in
    "Create new resource group")
      read -p "Enter the name of the new resource group: " new_rg_name
      az group create --name $new_rg_name --location eastus > /dev/null
      selected_rg=$new_rg_name
      break
      ;;
    *)
      break
      ;;
  esac
done

# display the selected resource group
echo "You selected resource group: $selected_rg"

#-------------------------------
### STORAGE CHECKS AND CREATION
#-------------------------------

# variables for the storage account etc.
LOCATION="eastus"
STORAGE_ACCOUNT_NAME="anodotblob$(shuf -i 100000-999999 -n 1)"
CONTAINER_NAME="anodotcontainer"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
from=$(date -u +%Y-%m-%dT%H:%M:%SZ)
to=$(date -u -d "+1 month" +%Y-%m-%dT%H:%M:%SZ)
export_name="DemoExport"
STORAGE_ACCOUNT_KEY=""

az storage account create --name $STORAGE_ACCOUNT_NAME --resource-group $selected_rg > /dev/null
while [ $(az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $selected_rg --query provisioningState -o tsv) != "Succeeded" ]
do
  sleep 5
done
az storage container create --account-name $STORAGE_ACCOUNT_NAME --name $CONTAINER_NAME
while [ $(az storage container exists --account-name $STORAGE_ACCOUNT_NAME --name $CONTAINER_NAME --query exists -o tsv) != "true" ]
do
  sleep 5
done

# get the storage account key
STORAGE_ACCOUNT_KEY=$(az storage account keys list --resource-group $selected_rg --account-name $STORAGE_ACCOUNT_NAME --query "[0].value" -o tsv)

#-------------------------------
### EXPORT CREATION AND EXECUTION
#-------------------------------

# create the export
az costmanagement export create --name $export_name --type ActualCost \ > /dev/null
--scope "subscriptions/$SUBSCRIPTION_ID" \
--storage-account-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$selected_rg/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME \
--storage-container $CONTAINER_NAME --timeframe MonthToDate --recurrence Daily \
--recurrence-period from="$from" to="$to" \
--schedule-status Active --storage-directory demodirectory

# trigger the export via HTTP request
endpoint="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/$export_name/run?api-version=2021-10-01"
request_body='{ "commandName": "Microsoft_Azure_CostManagement.ACM.Exports.run" }'
access_token=$(az account get-access-token --query accessToken -o tsv)

http_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $access_token" -H "Content-Type: application/json" -H "Accept: application/json" -d "$request_body" $endpoint)

# trigger the export via az cli
az storage blob list --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --container-name $CONTAINER_NAME --output table

# Wait for the export file to be generated
echo "Waiting for the export file to be generated..."
loading 2
sleep_duration=60
max_attempts=30
attempt_counter=0
file_found=false

print_progress_bar() {
  local filled=""
  local empty=""
  local progress_bar_width=50

  for ((i = 0; i < $1; i++)); do
    filled+="="
  done

  for ((i = 0; i < $((progress_bar_width - $1)); i++)); do
    empty+=" "
  done

  printf "|%-*s|" "$progress_bar_width" "$filled$empty"
}

function loading() {
  local duration=$1
  local sleep_duration=1
  local max_iterations=$((duration))
  local iteration=0

  while [ $iteration -lt $max_iterations ]; do
    printf "\r%s" "$(print_progress_bar $((iteration * 50 / max_iterations)))"
    sleep $sleep_duration
    iteration=$((iteration + 1))
  done

  printf "\n"
}

while [ $attempt_counter -lt $max_attempts ] && [ "$file_found" = false ]
do
  # List the blobs in the container
  blobs_list=$(az storage blob list --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_ACCOUNT_KEY --container-name $CONTAINER_NAME --query '[].name' -o tsv)

  # Check if any of the blobs match the exported file pattern
  for blob_name in $blobs_list; do
    if [[ $blob_name == demodirectory/* ]]; then
      file_found=true
      echo -e "\nExported file found: $blob_name"
      break
    fi
  done

  if [ "$file_found" = false ]; then
    attempt_counter=$((attempt_counter + 1))
    loading 1
  fi
done
e

  # If the file is not found, wait and retry
  if [ "$file_found" = false ]; then
    printf "\r%s" "$(print_progress_bar $((attempt_counter * 50 / max_attempts)))"
    sleep $sleep_duration
    attempt_counter=$((attempt_counter + 1))
  fi


if [ "$file_found" = false ]; then
  echo -e "\nThe exported file was not found in the container after $max_attempts attempts. Please check the export process or try again later."
  loading 2
else
  echo "The exported file has been successfully generated and is available in the container."
  loading 2
fi

#-------------------------------
### APP REGISTRATION
#------------------------------

# Prompt the user for the application name
echo "Select an option for the application name:"
echo "1. Use default name (AnodotRegApp)"
echo "2. Enter custom name"

# Read user input
read -p "Enter your choice (1 or 2): " choice

# Process the choice and set the appregname variable accordingly
case $choice in
    1)
        appregname="AnodotRegApp"
        ;;
    2)
        read -p "Enter the custom application name: " custom_app_name
        appregname="$custom_app_name"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

appregname="anodotregapp"
SUBSCRIPTION_ID=$(az account show --query id -o tsv) > /dev/null

#create appregname="anodotregapp"
clientid=$(az ad app create --display-name $appregname --query appId --output tsv) > /dev/null
objectid=$(az ad app show --id $clientid --query objectId --output tsv) > /dev/null

# echo $clientid

###Add client secret with expiration. The default is one year.
clientsecretname=mycert2
clientsecretduration=2
clientsecret=$(az ad app credential reset --id $clientid --append --display-name $clientsecretname --years $clientsecretduration --query password --output tsv)
# echo $clientsecret

###Create an AAD service principal
spid=$(az ad sp create --id $clientid --query id --output tsv)
###Look up a service principal
spid=$(az ad sp show --id $clientid --query id --output tsv)
# echo $spid

#Reviewing the manifest step is optional. You can view and download the client application detail, or the manifest.

az ad app list --app-id $clientid

# assign the Monitoring Reader role to the service principal and check if the role was successfully assigned

# set variables using service-principal-object-id (spid)
role_name="Monitoring Reader"

# Set the length of the loading bar
BAR_LENGTH=50

# Define the print_progress_bar function
print_progress_bar() {
  local filled=""
  local empty=""
  local progress_bar_width=$BAR_LENGTH
  local percentage=$((100 * $1 / progress_bar_width))
  local custom_text="Anodot-AI: control your costs"

  for ((i = 0; i < $1; i++)); do
    filled+="█"
  done

  for ((i = 0; i < $((progress_bar_width - $1)); i++)); do
    empty+="░"
  done

  printf "%s |%-*s| %3d%%" "$custom_text" "$progress_bar_width" "$filled$empty" "$percentage"
}

# Define the loading function
function loading() {
  local duration=$1
  local sleep_duration=0.1
  local max_iterations=$((duration * 10))
  local iteration=0

  while [ $iteration -lt $max_iterations ]; do
    printf "\r%s" "$(print_progress_bar $((iteration * BAR_LENGTH / max_iterations)))"
    sleep $sleep_duration
    iteration=$((iteration + 1))
  done

  printf "\n"
}

# assign the role_name role to the service principal and check if the role was successfully assigned
role_name="Monitoring Reader"

# assign the role_name role to the service principal
az role assignment create --assignee $spid --role "$role_name"

# check if the role was successfully assigned
role_assignment=$(az role assignment list --assignee $spid --query "[?roleDefinitionName=='$role_name'].{Name:name, Principal:principalName, Role:roleDefinitionName}" --output json)

loading 2

if [ -z "$role_assignment" ]
then
    echo "$role_name role was not assigned successfully."
else
    echo "$role_name role was assigned successfully."
    echo "Role assignment details:"
    echo "$role_assignment"
fi

# Set the length of the loading bar
BAR_LENGTH=50

# Define the print_progress_bar function
print_progress_bar() {
  local filled=""
  local empty=""
  local progress_bar_width=$BAR_LENGTH
  local percentage=$((100 * $1 / progress_bar_width))
  local custom_text="Anodot-AI: control your costs"

  for ((i = 0; i < $1; i++)); do
    filled+="█"
  done

  for ((i = 0; i < $((progress_bar_width - $1)); i++)); do
    empty+="░"
  done

  printf "%s |%-*s| %3d%%" "$custom_text" "$progress_bar_width" "$filled$empty" "$percentage"
}

# Define the loading function
function loading() {
  local duration=$1
  local sleep_duration=0.1
  local max_iterations=$((duration * 10))
  local iteration=0

  while [ $iteration -lt $max_iterations ]; do
    printf "\r%s" "$(print_progress_bar $((iteration * BAR_LENGTH / max_iterations)))"
    sleep $sleep_duration
    iteration=$((iteration + 1))
  done

  printf "\n"
}

# assign the Storage Blob Data Reader role to the service principal and check if the role was successfully assigned
role_name="Storage Blob Data Reader"

# assign the role_name role to the service principal
az role assignment create --assignee $spid --role "$role_name"

# check if the role was successfully assigned
role_assignment=$(az role assignment list --assignee $spid --query "[?roleDefinitionName=='$role_name'].{Name:name, Principal:principalName, Role:roleDefinitionName}" --output json)
loading 2

if [ -z "$role_assignment" ]
then
    echo "$role_name role was not assigned successfully."
else
    echo "$role_name role was assigned successfully."
    echo "Role assignment details:"
    echo "$role_assignment"
fi

echo -e " >>>>>>>>>>>>>>>>>>>>>>>>>>>>>your details are as follows<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< "
echo ""
echo " your client ID is: $clientid\n"
echo ""
echo " STORAGE_ACCOUNT_NAME $STORAGE_ACCOUNT_NAME\n"
echo ""
echo " CONTAINER_NAME $CONTAINER_NAME\n"
echo ""
echo " clientsecret $clientsecret\n"
echo ""
tanetID=$(az account show --query tenantId --output tsv)
echo " your tanent id id $tanetID\n"


