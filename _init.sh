#!/bin/bash

#********************************************************************************
# Copyright 2014 IBM
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#********************************************************************************

#############
# Colors    #
#############
export green='\e[0;32m'
export red='\e[0;31m'
export label_color='\e[0;33m'
export no_color='\e[0m' # No Color

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}

#########################################
# Configure log file to store errors  #
#########################################
if [ -z "$ERROR_LOG_FILE" ]; then
    ERROR_LOG_FILE="${EXT_DIR}/errors.log"
    export ERROR_LOG_FILE
fi

set +e
set +x 
##################################################
# capture packages that on the originial container 
##################################################
if [[ $DEBUG -eq 1 ]]; then
    dpkg -l | grep '^ii' > ${EXT_DIR}/pkglist
fi 

###############################
# Configure extension PATH    #
###############################
if [ -n ${EXT_DIR} ]; then 
    export PATH=${EXT_DIR}:$PATH
fi 
##############################
# Configure extension LIB    #
##############################
if [ -z $GAAS_LIB ]; then 
    export GAAS_LIB="${EXT_DIR}/lib"
fi 

################################
# Setup archive information    #
################################
if [ -z $WORKSPACE ]; then 
    echo -e "${red}Please set WORKSPACE in the environment${no_color}"
    ${EXT_DIR}/print_help.sh
    exit 1
fi 

if [ -z $ARCHIVE_DIR ]; then 
    echo "${label_color}ARCHIVE_DIR was not set, setting to WORKSPACE/archive ${no_color}"
    export ARCHIVE_DIR="${WORKSPACE}"
fi 

if [ -d $ARCHIVE_DIR ]; then
  echo "Archiving to $ARCHIVE_DIR"
else 
  echo "Creating archive directory $ARCHIVE_DIR"
  mkdir $ARCHIVE_DIR 
fi 
export LOG_DIR=$ARCHIVE_DIR

#############################
# Install Cloud Foundry CLI #
#############################
pushd . 
echo "Installing Cloud Foundry CLI"
cd $EXT_DIR
mkdir bin
cd bin
curl --silent -o cf-linux-amd64.tgz -v -L https://cli.run.pivotal.io/stable?release=linux64-binary &>/dev/null 
gunzip cf-linux-amd64.tgz &> /dev/null
tar -xvf cf-linux-amd64.tar  &> /dev/null

cf help &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo "Cloud Foundry CLI not already installed, adding CF to PATH"
    export PATH=$PATH:$EXT_DIR/bin
else 
    echo 'Cloud Foundry CLI already available in container.  Latest CLI version available in ${EXT_DIR}/bin'  
fi 

# check that we are logged into cloud foundry correctly
cf spaces 
RESULT=$?
if [ $RESULT -ne 0 ]; then
    echo -e "${red}Failed to check cf spaces to confirm login${no_color}"
    exit $RESULT
else 
    echo -e "${green}Successfully logged into IBM Bluemix${no_color}"
fi 
popd 

export container_cf_version=$(cf --version)
export latest_cf_version=$(${EXT_DIR}/bin/cf --version)
echo "Container Cloud Foundry CLI Version: ${container_cf_version}"
echo "Latest Cloud Foundry CLI Version: ${latest_cf_version}"

##########################################
# setup bluemix env
##########################################
# attempt to  target env automatically
CF_API=`cf api`
if [ $? -eq 0 ]; then
    # find the bluemix api host
    export BLUEMIX_API_HOST=`echo $CF_API  | awk '{print $3}' | sed '0,/.*\/\//s///'`
    echo $BLUEMIX_API_HOST | grep 'stage1'
    if [ $? -eq 0 ]; then
        # on staging, make sure bm target is set for staging
        export BLUEMIX_TARGET="staging"
    else
        # on prod, make sure bm target is set for prod
        export BLUEMIX_TARGET="prod"
    fi
elif [ -n "$BLUEMIX_TARGET" ]; then
    # cf not setup yet, try manual setup
    if [ "$BLUEMIX_TARGET" == "staging" ]; then 
        echo -e "Targetting staging Bluemix"
        export BLUEMIX_API_HOST="api.stage1.ng.bluemix.net"
    elif [ "$BLUEMIX_TARGET" == "prod" ]; then 
        echo -e "Targetting production Bluemix"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    else 
        echo -e "${red}Unknown Bluemix environment specified${no_color}"
    fi 
else 
    echo -e "Targetting production Bluemix"
    export BLUEMIX_API_HOST="api.ng.bluemix.net"
fi

################################
# Login to Container Service   #
################################
if [ -n "$BLUEMIX_USER" ] || [ ! -f ~/.cf/config.json ]; then
    # need to gather information from the environment 
    # Get the Bluemix user and password information 
    if [ -z "$BLUEMIX_USER" ]; then 
        echo -e "${red} Please set BLUEMIX_USER on environment ${no_color} "
        exit 1
    fi 
    if [ -z "$BLUEMIX_PASSWORD" ]; then 
        echo -e "${red} Please set BLUEMIX_PASSWORD as an environment property environment ${no_color} "
        exit 1
    fi 
    if [ -z "$BLUEMIX_ORG" ]; then 
        export BLUEMIX_ORG=$BLUEMIX_USER
        echo -e "${label_color} Using ${BLUEMIX_ORG} for Bluemix organization, please set BLUEMIX_ORG if on the environment if you wish to change this. ${no_color} "
    fi 
    if [ -z "$BLUEMIX_SPACE" ]; then
        export BLUEMIX_SPACE="dev"
        echo -e "${label_color} Using ${BLUEMIX_SPACE} for Bluemix space, please set BLUEMIX_SPACE if on the environment if you wish to change this. ${no_color} "
    fi 
    echo -e "${label_color}Targetting information.  Can be updated by setting environment variables${no_color}"
    echo "BLUEMIX_USER: ${BLUEMIX_USER}"
    echo "BLUEMIX_SPACE: ${BLUEMIX_SPACE}"
    echo "BLUEMIX_ORG: ${BLUEMIX_ORG}"
    echo "BLUEMIX_PASSWORD: xxxxx"
    echo ""
    echo -e "${label_color}Logging in to Bluemix using environment properties${no_color}"
    debugme echo "login command: cf login -a ${BLUEMIX_API_HOST} -u ${BLUEMIX_USER} -p XXXXX -o ${BLUEMIX_ORG} -s ${BLUEMIX_SPACE}"
    cf login -a ${BLUEMIX_API_HOST} -u ${BLUEMIX_USER} -p ${BLUEMIX_PASSWORD} -o ${BLUEMIX_ORG} -s ${BLUEMIX_SPACE} 2> /dev/null
    RESULT=$?
else 
    # we are already logged in.  Simply check via cf command 
    echo -e "${label_color}Logging into IBM Container Service using credentials passed from IBM DevOps Services ${no_color}"
    cf target >/dev/null 2>/dev/null
    RESULT=$?
    if [ ! $RESULT -eq 0 ]; then
        echo "cf target did not return successfully.  Login failed."
    fi 
fi 


# check login result 
if [ $RESULT -eq 1 ]; then
    echo -e "${red}Failed to login to IBM Bluemix${no_color}"
    exit $RESULT
else 
    echo -e "${green}Successfully logged into IBM Bluemix${no_color}"
fi 



export container_cf_version=$(cf --version)
export latest_cf_version=$(${EXT_DIR}/bin/cf --version)
echo "Container Cloud Foundry CLI Version: ${container_cf_version}"
echo "Latest Cloud Foundry CLI Version: ${latest_cf_version}"

echo "Installing Containers Plug-in"
${EXT_DIR}/bin/cf install-plugin https://static-ice.ng.bluemix.net/ibm-containers-linux_x64
ls ${EXT_DIR}/bin/cf
echo "Checking for existing SonarQube server"
#${EXT_DIR}/bin/cf ${EXT_DIR}/bin/ic namespace set sonar_space
#RESULT=$?
#if [ $RESULT -ne 0 ]; then
#    ${EXT_DIR}/bin/cf ${EXT_DIR}/bin/ic images
#    #space is already set, check for existing Sonar image
#    existing=$(${EXT_DIR}/bin/cf ${EXT_DIR}/bin/ic images | grep "sonar")
#    if [ -z "$existing" ]; then
#        #sonar image is already present, check if running
#        echo "SonarQube server found, checking if running"
##        running=$()
##        if [ -z "$running" ]; then
##            #not running; start
##            echo "SonarQube server not running, starting"
##        else
##           #already running, exit
##            echo "SonarQube server is running" 
##        fi
#    else
#        #no existing image, install
#        echo "No SonarQube server found, creating one"
#    fi
#else
#    #space set to sonar_space, need to install new image
#    echo "Created new namespace, creating new SonarQube server"
#fi

################################
# get the extensions utilities #
################################
pushd . >/dev/null
cd ${EXT_DIR} 
git clone https://github.com/Osthanes/utilities.git utilities
popd >/dev/null

#############################################
# Capture packages installed on the container  
#############################################
if [[ $DEBUG -eq 1 ]]; then
    dpkg -l | grep '^ii' > ${EXT_DIR}/pkglist2
    diff ${EXT_DIR}/pkglist ${EXT_DIR}/pkglist2
fi