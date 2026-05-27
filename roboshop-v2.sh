#!/bin/bash

#export PATH=$PATH:/usr/local/bin

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

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "$R ERROR:: First argument must be either create or delete $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

get_instance_id(){
    name=$1
    aws ec2 describe-instances --filters "Name=tag:Name,Values=roboshop-$name" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text
}

for instance in $@
do
    INSTANCE_ID=$(get_instance_id $instance)
    if [ $ACTION == "create" ]; then
        if [ $INSTANCE_ID == "None" ]; then
            echo "Launching Instance: roboshop-$instance"
            INSTANCE_ID=$( aws ec2 run-instances \
            --image-id $AMI_ID \
            --instance-type t3.micro \
            --security-groups "roboshop-common" "roboshop-$instance" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text 
            )
            echo "Launched Instance: $INSTANCE_ID"
            aws ec2 wait instance-running --instance-ids $INSTANCE_ID
            echo "Instance is running: $INSTANCE_ID"

        else
            echo "roboshop-$instance already running: $INSTANCE_ID"
        fi

        # update R53 record
        if [ $instance == "frontend" ]; then
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
            --query 'Reservations[*].Instances[*].PublicIpAddress' \
            --output text
            )
            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
            --query 'Reservations[*].Instances[*].PrivateIpAddress' \
            --output text
            )
            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONE_ID \
        --change-batch '
            {
                "Comment": "Update A record to new IP",
                "Changes": [
                    {
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": "'$R53_RECORD'",
                            "Type": "A",
                            "TTL": 1,
                            "ResourceRecords": [
                                {
                                    "Value": "'$IP'"
                                }
                            ]
                        }
                    }
                ]
            }
        '
        echo "updated R53 record for: $instance"
    else
        if [ $INSTANCE_ID == "None" ]; then
            echo "$instance already destroyed, nothing to do..."
        else
            aws ec2 terminate-instances --instance-ids $INSTANCE_ID
            echo "Terminating Instance: $instance"
        fi
    fi
done

# ================================================================
# ASSIGNMENT 2 — roboshop-v3.sh (Handle stopped instances)
# ================================================================

# roboshop-v2.sh only checks for "running" instances.
# A stopped instance is treated as non-existent — it gets re-created
# instead of re-started, and on delete it is silently skipped.

# Improve it so that:

#   - If create and instance is stopped, start it instead of launching new
#   - If delete and instance is stopped, terminate it and delete R53 record
#   - If delete and instance is running, terminate it and delete R53 record