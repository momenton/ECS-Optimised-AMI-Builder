#!/usr/bin/env bash -xe

# install docker ce (using recommended approach)
yum install -y http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.21-1.el7.noarch.rpm
yum install -y yum-utils device-mapper-persistent-data lvm2

yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum-config-manager --disable docker-ce-edge
yum-config-manager --disable docker-ce-test

# Minimum required version for gVisor is v17.09.0
yum install -y docker-ce-17.12.0.ce

systemctl enable docker

# install ECS container agent

# allow the port proxy to route traffic using loopback addresses
echo 'net.ipv4.conf.all.route_localnet = 1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

# enable IAM roles for tasks
iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679

iptables-save > /etc/sysconfig/iptables

# Install gVisor runsc
wget https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
chmod +x runsc
sudo mv runsc /usr/local/bin

# create the Amazon ECS container agent configuration file and then
# set the cluster name in User Data with the following:
#    #!/bin/bash -xe
#    echo ECS_CLUSTER=your_cluster_name_here >> /etc/ecs/ecs.config
mkdir -p /var/log/ecs /var/lib/ecs/data /etc/ecs
cat <<EOF > /etc/ecs/ecs.config
ECS_DATADIR=/data
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_LOGFILE=/log/ecs-agent.log
ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]
ECS_LOGLEVEL=info
HTTP_PROXY=forwardproxy:3128
NO_PROXY=169.254.169.254,169.254.170.2,/var/run/docker.sock
EOF

cat <<EOF > /etc/systemd/system/docker-container@ecs-agent.service
[Unit]
Description=Docker Container %I
Requires=docker.service
After=cloud-final.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm -f %i
ExecStart=/usr/bin/docker run --name %i \
--privileged \
--restart=on-failure:10 \
--volume=/var/run:/var/run \
--volume=/var/log/ecs/:/log:Z \
--volume=/var/lib/ecs/data:/data:Z \
--volume=/etc/ecs:/etc/ecs \
--net=host \
--env-file=/etc/ecs/ecs.config \
amazon/amazon-ecs-agent:latest
ExecStop=/usr/bin/docker stop %i

[Install]
WantedBy=multi-user.target
EOF

# Configure docker daemon to swap runc for runsc
cat <<EOF >> /etc/docker/daemon.json
{
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc",
            "runtimeArgs": [
                "--debug-log-dir=/tmp/runsc",
                "--debug",
                "--strace"
            ]
       }
    }
}
EOF

systemctl enable docker-container@ecs-agent.service
