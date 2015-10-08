#!/bin/bash

#download sonar-runner
curl -o sonar-runner-dist-2.4.zip -fSL http://repo1.maven.org/maven2/org/codehaus/sonar/runner/sonar-runner-dist/2.4/sonar-runner-dist-2.4.zip
unzip sonar-runner-dist-2.4.zip

#update sonar-runner.properties
rm sonar-runner-2.4/conf/sonar-runner.properties
echo "#Configure here general information about the environment, such as SonarQube DB details for example
#No information about specific project should appear here
#----- Default SonarQube server
sonar.host.url=http://134.168.19.103:9000
#temp DB
sonar.jdbc.url=jdbc:h2:tcp://134.168.19.103/sonar
#----- PostgreSQL
#sonar.jdbc.url=jdbc:postgresql://134.168.19.103/sonar
#----- Global database settings
sonar.jdbc.username=sonar
sonar.jdbc.password=sonar" > sonar-runner-2.4/conf/sonar-runner.properties

#test
#if choices are empty
if [ -z "$SRC" ] && [ -z "$LANG"]; then
    #assume .properties file is present and execute
    sonar-runner-2.4/bin/sonar-runner
fi

if [ ! -f sonar-project.properties ]; then
    #no configuration so use provided info to run
    sonar-runner-2.4/bin/sonar-runner -Dsonar.projectKey=${KEY} -Dsonar.projectName=${NAME} -Dsonar.projectVersion=1.0 -Dsonar.sources=${SRC}
fi