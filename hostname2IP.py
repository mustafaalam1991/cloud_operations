#!/usr/bin/env python3
## This script was taken from https://www.simplified.guide/python/hostname-to-ip
 
import socket
import sys

## Need to update this hardcoded file/folder location to more dynamic location 
with open('/home/mustafa/Desktop/IM_Mid/top500websites/top500DomainsURL.txt') as file:
    lines = file.readlines()
    lines = [i.replace('"', '') for i in lines]
## removing /n character
lines = list(map(lambda s: s.strip(), lines))

#print(lines)
for li in lines:
    hostname = li
    try:
        ip = socket.gethostbyname(hostname)
        print('Hostname: ', hostname, ' IP: ', ip)
    except:
        print("Hostname resolution for $hostname failed")
