#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z09281972U2VCOAQJYQ2O"   # replace with your zone ID
DOMAIN_NAME="yokshithkumar.shop" # replace with your domain name
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

ALL_INSTANCES="mongodb redis mysql rabbitmq catalogue user cart shipping payment frontend"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: At least 2 arguments required $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...] or [all]"
    exit 1
fi

ACTION=$1
shift

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "$R ERROR:: First argument must be either create or delete $N"
    exit 1
fi

# Expand "all"
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
    aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=roboshop-$name" "Name=instance-state-name,Values=running" \
      --query "Reservations[0].Instances[0].InstanceId" --output text
}

for instance in $INSTANCES
do
    INSTANCE_ID=$(get_instance_id "$instance")

    if [ "$ACTION" == "create" ]; then
        if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
            echo "Launching Instance: roboshop-$instance"

            # Write user_data to a temp file
cat > /tmp/roboshop-userdata.sh <<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/null) 2>&1
echo "Starting bootstrap for roboshop-$instance"

# Ensure git is present
if ! command -v git &>/dev/null; then
  yum install -y git || apt-get update && apt-get install -y git
fi

cd /root
rm -rf shell-roboshop
git clone -q https://github.com/kumarkoppala/shell-roboshop.git
cd shell-roboshop
sh "$instance".sh
EOF

            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id "$AMI_ID" \
                --instance-type t3.micro \
                --security-groups "roboshop-frontend" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
                --iam-instance-profile Name=Admin-script \
                --user-data file:///tmp/roboshop-userdata.sh \
                --query 'Instances[0].InstanceId' \
                --output text)

            echo "Launched Instance: $INSTANCE_ID"
            sleep 2
        else
            echo "roboshop-$instance already running: $INSTANCE_ID"
        fi

        # Update Route53 record
        if [ "$instance" == "frontend" ]; then
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
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
                                { \"Value\": \"$IP\" }
                            ]
                        }
                    }
                ]
            }"
        echo "updated R53 record for: $instance"

    else
        # Delete logic
        if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
            echo "$instance already destroyed, nothing to do..."
        else
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
            echo "Terminating Instance: $instance"
        fi
    fi
done
