#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat <<EOF > /var/www/html/index.html
<html>
<body style="font-family: sans-serif; text-align: center; margin-top: 100px;">
  <h1>HA Project — Server is up</h1>
  <p>Instance ID: $INSTANCE_ID</p>
  <p>Availability Zone: $AZ</p>
</body>
</html>
EOF