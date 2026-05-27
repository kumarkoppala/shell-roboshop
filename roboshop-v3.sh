#!/bin/bash

#export PATH=$PATH:/usr/local/bin

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z07086101C1CVP7AT2UK4" # replace with your zone ID
DOMAIN_NAME="daws90s.shop" # replace with your domain name
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

ALL_INSTANCES="mongodb redis mysql rabbitmq catalogue user cart shipping payment frontend"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: Atleast 2 arguments required $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...] or [all]"
    exit 1
fi

ACTION=$1
shift # first argument will be removed

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "$R ERROR:: First argument must be either create or delete $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...] or [all]"
    exit 1
fi

# If "all" is passed, expand to full list (reversed for delete)
if [ "$1" == "all" ]; then
    if [ "$ACTION" == "create" ]; then
        INSTANCES="$ALL_INSTANCES"
    else
        INSTANCES=$(echo $ALL_INSTANCES | tr ' ' '\n' | tac | tr '\n' ' ')
    fi
else
    INSTANCES="$@"
fi

get_instance_id(){
    name=$1
    aws ec2 describe-instances --filters "Name=tag:Name,Values=roboshop-$name" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text
}

for instance in $INSTANCES
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
