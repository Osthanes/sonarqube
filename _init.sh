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

########################################
# default values to build server names #
########################################
# beta servers
BETA_API_PREFIX="api-ice"
BETA_REG_PREFIX="registry-ice"
# default servers
DEF_API_PREFIX="containers-api"
DEF_REG_PREFIX="registry"

##################################################
# Simple function to only run command if DEBUG=1 # 
### ###############################################
debugme() {
  [[ $DEBUG = 1 ]] && "$@" || :
}

export -f debugme 
#########################################
# Configure log file to store errors  #
#########################################
if [ -z "$ERROR_LOG_FILE" ]; then
    ERROR_LOG_FILE="${EXT_DIR}/errors.log"
    export ERROR_LOG_FILE
fi

installwithpython27() {
    echo "Installing Python 2.7"
    sudo apt-get update &> /dev/null
    sudo apt-get -y install python2.7 &> /dev/null
    python --version 
    wget --no-check-certificate https://bootstrap.pypa.io/get-pip.py &> /dev/null
    python get-pip.py --user &> /dev/null
    export PATH=$PATH:~/.local/bin
    wget https://static-ice.ng.bluemix.net/icecli-2.0.zip &> /dev/null
    pip install --user icecli-2.0.zip > cli_install.log 2>&1 
    debugme cat cli_install.log 
}

if [[ $DEBUG = 1 ]]; then 
    export ICE_ARGS="--verbose"
else
    export ICE_ARGS=""
fi 

set +e
set +x 

###############################
# Configure extension PATH    #
###############################
if [ -n $EXT_DIR ]; then 
    export PATH=$PATH:$EXT_DIR:
fi 

################################
# Application Name and Version #
################################
# The build number for the builder is used for the version in the image tag 
# For deployers this information is stored in the $BUILD_SELECTOR variable and can be pulled out
if [ -z "$APPLICATION_VERSION" ]; then
    export SELECTED_BUILD=$(grep -Eo '[0-9]{1,100}' <<< "${BUILD_SELECTOR}")
    if [ -z $SELECTED_BUILD ]
    then 
        if [ -z $BUILD_NUMBER ]
        then 
            export APPLICATION_VERSION=$(date +%s)
        else 
            export APPLICATION_VERSION=$BUILD_NUMBER    
        fi
    else
        export APPLICATION_VERSION=$SELECTED_BUILD
    fi 
fi 
debugme echo "installing bc"
sudo apt-get install bc >/dev/null 2>&1
debugme echo "done installing bc"
if [ -n "$BUILD_OFFSET" ]; then 
    echo "Using BUILD_OFFSET of $BUILD_OFFSET"
    export APPLICATION_VERSION=$(echo "$APPLICATION_VERSION + $BUILD_OFFSET" | bc)
    export BUILD_NUMBER=$(echo "$BUILD_NUMBER + $BUILD_OFFSET" | bc)
fi 

echo "APPLICATION_VERSION: $APPLICATION_VERSION"

################################
# Setup archive information    #
################################
if [ -z $WORKSPACE ]; then 
    echo -e "${red}Please set WORKSPACE in the environment${no_color}" | tee -a "$ERROR_LOG_FILE"
    ${EXT_DIR}/print_help.sh
    exit 1
fi 

if [ -z $ARCHIVE_DIR ]; then
    echo -e "${label_color}ARCHIVE_DIR was not set, setting to WORKSPACE ${no_color}"
    export ARCHIVE_DIR="${WORKSPACE}"
fi

if [ "$ARCHIVE_DIR" == "./" ]; then
    echo -e "${label_color}ARCHIVE_DIR set relative, adjusting to current dir absolute ${no_color}"
    export ARCHIVE_DIR=`pwd`
fi

if [ -d $ARCHIVE_DIR ]; then
  echo -e "Archiving to $ARCHIVE_DIR"
else 
  echo -e "Creating archive directory $ARCHIVE_DIR"
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

######################
# Install ICE CLI    #
######################
echo "Installing IBM Container Service CLI"
ice help &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    installwithpython27
    ice help &> /dev/null
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        echo -e "${red}Failed to install IBM Container Service CLI ${no_color}" | tee -a "$ERROR_LOG_FILE"
        debugme python --version
        ${EXT_DIR}/print_help.sh
        exit $RESULT
    fi
    echo -e "${label_color}Successfully installed IBM Container Service CLI ${no_color}"
fi 

##########################################
# setup bluemix env
##########################################
# if user entered a choice, use that
if [ -n "$BLUEMIX_TARGET" ]; then
    # user entered target use that
    if [ "$BLUEMIX_TARGET" == "staging" ]; then 
        export BLUEMIX_API_HOST="api.stage1.ng.bluemix.net"
    elif [ "$BLUEMIX_TARGET" == "prod" ]; then 
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    else 
        log_and_echo "$ERROR" "Unknown Bluemix environment specified: ${BLUEMIX_TARGET}, Defaulting to production"
        export BLUEMIX_TARGET="prod"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    fi 
else
    # try to auto-detect
    CF_API=`${EXT_DIR}/bin/cf api`
    RESULT=$?
    debugme echo "cf api returned: $CF_API"
    if [ $RESULT -eq 0 ]; then
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
    else 
        # failed, assume prod
        export BLUEMIX_TARGET="prod"
        export BLUEMIX_API_HOST="api.ng.bluemix.net"
    fi
fi
echo "Bluemix host is '${BLUEMIX_API_HOST}'"
echo "Bluemix target is '${BLUEMIX_TARGET}'"
# strip off the hostname to get full domain
CF_TARGET=`echo $BLUEMIX_API_HOST | sed 's/[^\.]*//'`
if [ -z "$API_PREFIX" ]; then
    API_PREFIX=$DEF_API_PREFIX
fi
if [ -z "$REG_PREFIX" ]; then
    REG_PREFIX=$DEF_REG_PREFIX
fi
# build api server hostname
export CCS_API_HOST="${API_PREFIX}${CF_TARGET}"
# build registry server hostname
export CCS_REGISTRY_HOST="${REG_PREFIX}${CF_TARGET}"
# set up the ice cfg
sed -i "s/ccs_host =.*/ccs_host = $CCS_API_HOST/g" $EXT_DIR/ice-cfg.ini
sed -i "s/reg_host =.*/reg_host = $CCS_REGISTRY_HOST/g" $EXT_DIR/ice-cfg.ini
sed -i "s/cf_api_url =.*/cf_api_url = $BLUEMIX_API_HOST/g" $EXT_DIR/ice-cfg.ini
export ICE_CFG="ice-cfg.ini"


################################
# Login to Container Service   #
################################
if [ -n "$API_KEY" ]; then 
    echo -e "${label_color}Logging on with API_KEY${no_color}"
    debugme echo "Login command: ice $ICE_ARGS login --key ${API_KEY}"
    #ice $ICE_ARGS login --key ${API_KEY} --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} 
    ice $ICE_ARGS login --key ${API_KEY} 2> /dev/null
    RESULT=$?
elif [ -n "$BLUEMIX_USER" ] || [ ! -f ~/.cf/config.json ]; then
    # need to gather information from the environment 
    # Get the Bluemix user and password information 
    if [ -z "$BLUEMIX_USER" ]; then 
        echo -e "${red} Please set BLUEMIX_USER on environment ${no_color}" | tee -a "$ERROR_LOG_FILE"
        ${EXT_DIR}/print_help.sh
        exit 1
    fi 
    if [ -z "$BLUEMIX_PASSWORD" ]; then 
        echo -e "${red} Please set BLUEMIX_PASSWORD as an environment property environment ${no_color}" | tee -a "$ERROR_LOG_FILE"
        ${EXT_DIR}/print_help.sh    
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
    echo -e "${label_color}Logging in to Bluemix and IBM Container Service using environment properties${no_color}"
    debugme echo "login command: ice $ICE_ARGS login --cf --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} --user ${BLUEMIX_USER} --psswd ${BLUEMIX_PASSWORD} --org ${BLUEMIX_ORG} --space ${BLUEMIX_SPACE}"
    ice $ICE_ARGS login --cf --host ${CCS_API_HOST} --registry ${CCS_REGISTRY_HOST} --api ${BLUEMIX_API_HOST} --user ${BLUEMIX_USER} --psswd ${BLUEMIX_PASSWORD} --org ${BLUEMIX_ORG} --space ${BLUEMIX_SPACE} 2> /dev/null
    RESULT=$?
else 
    # we are already logged in.  Simply check via ice command 
    echo -e "${label_color}Logging into IBM Container Service using credentials passed from IBM DevOps Services ${no_color}"
    mkdir -p ~/.ice
    debugme cat "${EXT_DIR}/${ICE_CFG}"
    cp ${EXT_DIR}/${ICE_CFG} ~/.ice/ice-cfg.ini
    debugme cat ~/.ice/ice-cfg.ini
    debugme echo "config.json:"
    debugme cat /home/jenkins/.cf/config.json | cut -c1-2
    debugme cat /home/jenkins/.cf/config.json | cut -c3-
    debugme echo "testing ice login via ice info command"
    ice --verbose info > info.log 2> /dev/null
    RESULT=$?
    debugme cat info.log 
    if [ $RESULT -eq 0 ]; then
        echo "ice info was successful.  Checking login to registry server" 
        ice images &> /dev/null
        RESULT=$? 
    else 
        echo "ice info did not return successfully.  Login failed."
    fi 
fi 

printEnablementInfo() {
    echo -e "${label_color}No namespace has been defined for this user ${no_color}"
    echo -e "Please check the following: "
    echo -e "   - Login to Bluemix (https://console.ng.bluemix.net)"
    echo -e "   - Select the 'IBM Containers' icon from the Dashboard" 
    echo -e "   - Select 'Create a Container'"
    echo -e "Or using the ICE command line: "
    echo -e "   - ice login -a api.ng.bluemix.net -H containers-api.ng.bluemix.net -R registry.ng.bluemix.net"
    echo -e "   - ${label_color}ice namespace set [your-desired-namespace] ${no_color}"
}

# check login result 
if [ $RESULT -eq 1 ]; then
    echo -e "${red}Failed to login to IBM Container Service${no_color}" | tee -a "$ERROR_LOG_FILE"
    ice namespace get 2> /dev/null
    HAS_NAMESPACE=$?
    if [ $HAS_NAMESPACE -eq 1 ]; then 
        printEnablementInfo        
    fi
    ${EXT_DIR}/print_help.sh
    exit $RESULT
else 
    echo -e "${green}Successfully logged into IBM Container Service${no_color}"
    ice info 2> /dev/null
fi  

###########################################
# get the extensions utilities
###########################################
pushd . >/dev/null
cd $EXT_DIR 
git clone https://github.com/Osthanes/utilities.git utilities
popd >/dev/null

###########################################
# set up sonarqube server
###########################################
echo "Checking for existing SonarQube server"
ice namespace set sonar_space &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    #space is already set, check for existing Sonar image
    existing=$(ice images | grep "sonar")
    if [ ! -z "$existing" ]; then
        #sonar image is already present, check if running
        echo "SonarQube server found, checking if running"
        running=$(ice ps | grep "sonar" | grep "Running")
        if [ -z "$running" ]; then
            #not running; start
            echo "SonarQube server not running, starting"
            ice start sonarqube_ip
        else
           #already running, exit
            echo "SonarQube server is running" 
        fi
    else
        #no existing image, install
        echo "No SonarQube server found, creating one"
        echo "#!/bin/bash
apt-get update
apt-get upgrade


export TEST_HOST=`hostname`
export TEST_IP=`ip addr show | grep "\<172\." | awk '{print $2}' | awk -F "/" '{print $1}'`
echo -e "$TEST_IP    $TEST_HOST" >>/etc/hosts

set -e

if [ "${1:0:1}" != '-' ]; then
	exec "$@"
fi

exec java -jar lib/sonar-application-$SONAR_VERSION.jar \
  -Dsonar.log.console=true \
  -Dsonar.jdbc.username="$SONARQUBE_JDBC_USERNAME" \
  -Dsonar.jdbc.password="$SONARQUBE_JDBC_PASSWORD" \
  -Dsonar.jdbc.url="$SONARQUBE_JDBC_URL" \
  -Dsonar.web.javaAdditionalOpts="-Djava.security.egd=file:/dev/./urandom" \
	"$@"" > run.sh
    
    echo "FROM java:openjdk-8u45-jdk

MAINTAINER David Gageot <david.gageot@sonarsource.com>

ENV SONARQUBE_HOME /opt/sonarqube

# Http port
EXPOSE 9000

# H2 Database port
EXPOSE 9092

# Database configuration
# Defaults to using H2
ENV SONARQUBE_JDBC_USERNAME sonar
ENV SONARQUBE_JDBC_PASSWORD sonar
ENV SONARQUBE_JDBC_URL jdbc:h2:tcp://localhost:9092/sonar

ENV SONAR_VERSION 5.1.2

# pub   2048R/D26468DE 2015-05-25
#      Key fingerprint = F118 2E81 C792 9289 21DB  CAB4 CFCA 4A29 D264 68DE
# uid       [ unknown] sonarsource_deployer (Sonarsource Deployer) <infra@sonarsource.com>
# sub   2048R/06855C1D 2015-05-25
RUN gpg --keyserver ha.pool.sks-keyservers.net --recv-keys F1182E81C792928921DBCAB4CFCA4A29D26468DE

RUN set -x \
	&& cd /opt \
	&& curl -o sonarqube.zip -fSL http://downloads.sonarsource.com/sonarqube/sonarqube-$SONAR_VERSION.zip \
	&& curl -o sonarqube.zip.asc -fSL http://downloads.sonarsource.com/sonarqube/sonarqube-$SONAR_VERSION.zip.asc \
	&& gpg --verify sonarqube.zip.asc \
	&& unzip sonarqube.zip \
	&& mv sonarqube-$SONAR_VERSION sonarqube \
	&& rm sonarqube.zip* \
	&& rm -rf $SONARQUBE_HOME/bin/* \
	&& curl -o sonar-javascript-plugin-2.8.jar -fSL https://sonarsource.bintray.com/Distribution/sonar-javascript-plugin/sonar-javascript-plugin-2.8.jar \
	&& mv sonar-javascript-plugin-2.8.jar $SONARQUBE_HOME/extensions/plugins/

VOLUME ["$SONARQUBE_HOME/data", "$SONARQUBE_HOME/extensions"]

WORKDIR $SONARQUBE_HOME
COPY run.sh $SONARQUBE_HOME/bin/
ENTRYPOINT ["./bin/run.sh"]
" > Dockerfile
    
    ls
    cat Dockerfile
    cat run.sh
        
    fi
else
    #space set to sonar_space, need to install new image
    echo "Created new namespace, creating new SonarQube server"
fi
