# ECS-Optimised-AMI-Builder
Packer script to build custom AMI to run on ECS EC2 instances

## Running to packer scripts

```bash
$ AMI_ID=ami-xxxxx # Amazon Linux or CentOS Base image
$ packer build \
-var "ami=$AMI_ID" \
-var 'vpc=<your VPC id>' \
-var 'subnet=<your subnet id>' \
-var 'tag=<your CostCentre tag>' \
ecs-hip-packer.json
```