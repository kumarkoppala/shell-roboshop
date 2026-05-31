#!/bin/bash

#export PATH=$PATH:/usr/local/bin

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z09281972U2VCOAQJYQ2O" # replace with your zone ID
DOMAIN_NAME="yokshithkumar.shop" # replace with your domain name
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
    INSTANCE_ID=$(get_instance_id "$instance")
    
    if [ "$ACTION" == "create" ]; then
        if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
            echo "Launching Instance: roboshop-$instance"
            
            # Left-aligned unquoted heredoc block allows local parsing of $instance
            USER_DATA_SCRIPT=$(cat <<EOF
#!/bin/bash
# 1. Force all outputs/errors to log to a file we can read
exec > >(tee /var/log/user-data.log|logger -t user-data -s2>/dev/null) 2>&1
echo "Starting bootstrap for roboshop-$instance"
cd /root
# 2. Install Git and clone the codebase cleanly
dnf install git -y
rm -rf shell-roboshop
git clone -q https://github.com/kumarkoppala/shell-roboshop.git
cd shell-roboshop
# 3. Execute the specific component script
sh "$instance".sh
EOF
)   

            # Correctly structured multiline AWS execution block with exact instance array filtering
            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id "$AMI_ID" \
                --instance-type t3.micro \
                --security-groups "roboshop-frontend" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
                --iam-instance-profile "Arn=arn:aws:iam::$(aws sts get-caller-identity --query 'Account' --output text):instance-profile/Admin-script" \
                --user-data "$USER_DATA_SCRIPT" \
                --query 'Instances[0].InstanceId' \
                --output text)

            echo "Launched Instance: $INSTANCE_ID"
            sleep 2 # sometimes instance take some time to create

        else
            echo "roboshop-$instance already running: $INSTANCE_ID"
        fi

        # update R53 record
        if [ "$instance" == "frontend" ]; then
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[*].Instances[*].PublicIpAddress' \
                --output text)
            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[*].Instances[*].PrivateIpAddress' \
                --output text)
            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "
            {
                \"Comment\": \"Update A record to new IP\",
                \"Changes\": [
                    {
                        \"Action\": \"UPSERT\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"$R53_RECORD\",
                            \"Type\": \"A\",
                            \"TTL\": 1,
                            \"ResourceRecords\": [
                                {
                                    \"Value\": \"$IP\"
                                }
                            ]
                        }
                    }
                ]
            }"
        echo "updated R53 record for: $instance"
        
    else
        # Deletion logic segment
        if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
            echo "$instance already destroyed, nothing to do..."
        else
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
            echo "Terminating Instance: $instance"
        fi
    fi
done
