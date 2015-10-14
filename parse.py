#!/usr/bin/python

import sys
import json
import os

ipJson = ""

with open('ipJSON.json') as jsonFile:
    global ipJson
    ipJson = json.load(jsonFile)

print ipJson[0]["NetworkSettings"]["PublicIpAddress"]
