#!/bin/bash

# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: MIT-0

# Define params
 export EKSCLUSTER_NAME=eks-nvme-alluxio
 export AWS_REGION=us-east-1
export OSS_SPARK_SVCACCT_NAME=spark-operator-spark
export OSS_NAMESPACE=spark-operator
export EMR_NAMESPACE=emr
export EKS_VERSION=1.28
export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ROLE_NAME=${EMRCLUSTER_NAME}-execution-role
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export S3TEST_BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}

echo "==============================================="
echo "  setup IAM roles ......"
echo "==============================================="

# create S3 bucket for application
if [ $AWS_REGION=="us-east-1" ]; then
  aws s3api create-bucket --bucket $S3TEST_BUCKET --region $AWS_REGION
else
  aws s3api create-bucket --bucket $S3TEST_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
# Create a job execution role (https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/creating-job-execution-role.html)
cat >/tmp/job-execution-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject","s3:DeleteObject","s3:GetObject","s3:ListBucket"],
            "Resource": [
              "arn:aws:s3:::${S3TEST_BUCKET}",
              "arn:aws:s3:::${S3TEST_BUCKET}/*",
              "arn:aws:s3:::blogpost-sparkoneks-us-east-1/blog/BLOG_TPCDS-TEST-3T-partitioned/*",
              "arn:aws:s3:::blogpost-sparkoneks-us-east-1"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [ "logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:CreateLogGroup" ],
            "Resource": [ "arn:aws:logs:*:*:*" ]
        }
    ]
}
EOF

cat >/tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    } ]
}
EOF

aws iam create-policy --policy-name $ROLE_NAME-policy --policy-document file:///tmp/job-execution-policy.json
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$ROLE_NAME-policy

echo "==============================================="
echo "  Create EKS Cluster ......"
echo "==============================================="

cat <<EOF >/tmp/ekscluster.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $EKSCLUSTER_NAME
  region: $AWS_REGION
  version: "$EKS_VERSION"
addons:
  - name: aws-ebs-csi-driver
#  - name: aws-mountpoint-s3-csi-driver
vpc:
  clusterEndpoints:
      publicAccess: true
      privateAccess: true
availabilityZones: ["${AWS_REGION}a","${AWS_REGION}b"]
iam:
  withOIDC: true
  serviceAccounts:
  - metadata:
      name: cluster-autoscaler
      namespace: kube-system
      labels: {aws-usage: "cluster-ops"}
    wellKnownPolicies:
      autoScaler: true
    roleName: eksctl-cluster-autoscaler-role
  - metadata:
      name: $OSS_SPARK_SVCACCT_NAME
      namespace: $OSS_NAMESPACE
      labels: {aws-usage: "application"}
    attachPolicyARNs:
    - arn:aws:iam::${ACCOUNTID}:policy/$ROLE_NAME-policy
managedNodeGroups:
  - name: mn-od
    availabilityZones: ["${AWS_REGION}b"]
    preBootstrapCommands:
      - "sleep 5;sudo mkfs.xfs /dev/nvme1n1;sudo mkdir -p /mnt;sudo echo /dev/nvme1n1 /mnt xfs defaults,noatime 1 2 >> /etc/fstab"
      - "sudo mount -a"
      - "sudo chown ec2-user:ec2-user /mnt"
    instanceType: c5d.4xlarge
    # ebs optimization is enabled by default
    volumeSize: 20
    volumeType: gp2
    minSize: 1
    desiredCapacity: 1
    maxSize: 6
    labels:
      app: sparktest 
    tags:
      # required for cluster-autoscaler auto-discovery
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/$EKSCLUSTER_NAME: "owned"  

# enable all of the control plane logs
cloudWatch:
 clusterLogging:
   enableTypes: ["*"]
EOF

# create eks cluster in a single AZ
eksctl create cluster -f /tmp/ekscluster.yaml
# if EKS cluster exists, comment out the line above, uncomment this line
# eksctl create nodegroup -f /tmp/ekscluster.yaml
aws eks update-kubeconfig --name $EKSCLUSTER_NAME --region $AWS_REGION

echo "==============================================="
echo "  Enable EMR on EKS ......"
echo "==============================================="

# Create kubernetes namespace for EMR on EKS
kubectl create namespace $EMR_NAMESPACE

# Enable cluster access for Amazon EMR on EKS in the 'emr' namespace
eksctl create iamidentitymapping --cluster $EKSCLUSTER_NAME --namespace $EMR_NAMESPACE --service-name "emr-containers"
aws emr-containers update-role-trust-policy --cluster-name $EKSCLUSTER_NAME --namespace $EMR_NAMESPACE --role-name $ROLE_NAME

# Create emr virtual cluster
aws emr-containers create-virtual-cluster --name $EMRCLUSTER_NAME \
  --container-provider '{
        "id": "'$EKSCLUSTER_NAME'",
        "type": "EKS",
        "info": { "eksInfo": { "namespace": "'$EMR_NAMESPACE'" } }
    }'

echo "==============================================="
echo "  Configure EKS Cluster ......"
echo "==============================================="
# config k8s rbac access to service account 'oss'
cat <<EOF | kubectl apply -f - -n $OSS_NAMESPACE
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $OSS_SPARK_SVCACCT_NAME-role
  namespace: $OSS_NAMESPACE
rules:
  - apiGroups: ["", "batch","extensions"]
    resources: ["configmaps","serviceaccounts","events","pods","pods/exec","pods/log","pods/portforward","secrets","services"]
    verbs: ["create","delete","get","list","patch","update","watch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $OSS_SPARK_SVCACCT_NAME-rb
  namespace: $OSS_NAMESPACE
subjects:
  - kind: ServiceAccount
    name: $OSS_SPARK_SVCACCT_NAME
    namespace: $OSS_NAMESPACE
roleRef:
  kind: Role
  name: $OSS_SPARK_SVCACCT_NAME-role
  apiGroup: rbac.authorization.k8s.io  
EOF

# Map S3 bucket to the EMR namespace dyanmically
kubectl create configmap --namespace $OSS_NAMESPACE special-config --from-literal=codeBucket=$S3TEST_BUCKET
# kubectl create configmap --namespace $OSS_NAMESPACE pod-template --from-file=docker/benchmark-util/default-driver-pod-template.yaml --from-file=docker/benchmark-util/default-executor-pod-template.yaml

# Install k8s metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install Cluster Autoscale that automatically adjusts the number of nodes in EKS
cat <<EOF >/tmp/autoscaler-config.yaml
---
autoDiscovery:
    clusterName: $EKSCLUSTER_NAME
awsRegion: $AWS_REGION
image:
    tag: v1.26.3
nodeSelector:
    app: sparktest    
podAnnotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: 'false'
extraArgs:
    skip-nodes-with-system-pods: false
    scale-down-unneeded-time: 2m
    scale-down-unready-time: 5m
rbac:
    serviceAccount:
        create: false
        name: cluster-autoscaler
EOF

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install nodescaler autoscaler/cluster-autoscaler --namespace kube-system --values /tmp/autoscaler-config.yaml --debug

# Install Spark-Operator for the OSS Spark test
helm repo add spark-operator https://kubeflow.github.io/spark-operator
helm repo update
helm install spark-operator spark-operator/spark-operator --version 1.4.6 \
   --namespace $OSS_NAMESPACE \
   --create-namespace \
   --set webhook.enable=true

#echo "============================================================================="
#echo "  Upload project examples to S3 ......"
#echo "============================================================================="
#aws s3 sync examples/ s3://$S3TEST_BUCKET/app_code/

#echo "============================================================================="
#echo "  Create ECR for eks-spark-benchmark utility docker image ......"
#echo "============================================================================="
#export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"
#aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
#aws ecr create-repository --repository-name eks-spark-benchmark --image-scanning-configuration scanOnPush=true
## get EMR on EKS base image
#export SRC_ECR_URL=755674844232.dkr.ecr.us-east-1.amazonaws.com
#aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $SRC_ECR_URL
#docker pull $SRC_ECR_URL/spark/emr-6.5.0:latest
## Custom image on top of the EMR Spark runtime
#docker build -t $ECR_URL/eks-spark-benchmark:emr6.5 -f docker/benchmark-util/Dockerfile --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/spark/emr-6.5.0:latest .
## push
#aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
#docker push $ECR_URL/eks-spark-benchmark:emr6.5

echo "Finished, proceed to submitting a job"
