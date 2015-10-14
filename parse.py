#!/usr/bin/python

import sys
import json
import os

with open('ipJSON.json') as jsonFile:
    ipJson = json.load(jsonFile)

print ipJson[0]["NetworkSettings"]["PublicIpAddress"]
