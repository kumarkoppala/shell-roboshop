#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z07086101C1CVP7AT2UK4" # replace with your zone ID
DOMAIN_NAME="daws90s.shop" # replace with your domain name
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: Atleast 2 arguments required $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

ACTION=$1
shift # first argument will be removed

if [ $ACTION -ne "create" ] && [ $ACTION -ne "delete" ]; then
    echo -e "$R ERROR:: First argument must be either create or delete"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi