#!/bin/bash
set -o xtrace
dos2unix $0

if [ ! -f ~/ec2master.pem ]; then
ssh-keygen -b 2048 -t rsa -f ~/ec2master.pem -q -N ""
chmod 400 ~/ec2master.pem
fi

type='p3.16xlarge'
vcpu=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-417A185B --query 'Quota.Value' | cut -d. -f1)
[[ $vcpu -ge 64 ]] && type='p3.16xlarge'; [[ $vcpu -ge 32 && $vcpu -lt 64 ]] && type='p3.8xlarge'

if [[ $@ == *'--list'* ]]; then 
	aws ec2 describe-instances --filters "Name=instance-type,Values=${type}" --query "Reservations[].Instances[].InstanceId"; exit 1
fi

declare -a reg=("us-east-1" "us-east-2" "us-west-2" "ap-northeast-2" "ap-southeast-2" "ap-northeast-1" "ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2")

aws ec2 create-default-vpc

for region in "${reg[@]}"; do
	aws ec2 import-key-pair --key-name ec2master --public-key-material file://~/ec2master.pub --region $region
	subnets_desc=$(aws ec2 describe-subnets --region $region | grep -oP '(?<="SubnetId": ").*?(?=")' | head -n 1);
	ami=$(aws ec2 describe-images --filters 'Name=manifest-location,Values=amazon/Deep Learning Base AMI (Ubuntu 18.04) Version 21.0' --region $region | grep -oP '(?<="ImageId": ").*?(?=")')
	run_instance=$(aws ec2 run-instances --image-id $ami --count 1 --instance-type $type --key-name ec2master --subnet-id $subnets_desc --region $region)
	instance_id=$(grep -Po '(?<="InstanceId": ").*?(?=")' <<< "$run_instance"); security_group=$(grep -Po '(?<="GroupId": ").*?(?=")' <<< "$run_instance" | head -n 1)
	aws ec2 authorize-security-group-ingress --region $region --group-id $security_group --protocol tcp --port 22 --cidr 0.0.0.0/0
	if [ ! -z "$instance_id" ]; then
		aws ec2 wait instance-status-ok --instance-ids $instance_id --region $region
		public_dns=$(aws ec2 describe-instances --instance-id $instance_id --region $region | grep PublicDnsName | head -n 1 | cut -d'"' -f4)
		[ -z "$public_dns" ] && public_dns=$(aws ec2 describe-instances --instance-ids $instance_id --region $region | grep -oP '(?<="PublicIp": ").*?(?=")')
		ssh -o StrictHostKeyChecking=no -i ~/ec2master.pem ubuntu@${public_dns} "command </dev/null >/dev/null 2>&1 &"
	fi
done
