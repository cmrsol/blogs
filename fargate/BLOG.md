### Introduction:
At Corteva, the Agricultural Division of DowDuPont, our purpose is to enrich
the lives of those who produce and those who consume, ensuring progress for
generations to come.  To accomplish this, we must support a network of research
stations to improve agricultural across the entire world.  As analytical
technology advances the volume of data, as well as the speed at which it must be
processed to meet the needs of our scientists poses challenges.  The Corteva
Cloud Center of Excellence (CCOE) is responsible for collaborating with and
enabling software developers, data scientists, and others to become the most
efficient innovation machine in the Agricultural industry.


Recently the CCOE was approached with a problem of how to deploy a novel machine
learning algorithm in support of our plant breeding organization.  This solution
would support labs across six continents in a process that is run daily.  When
examining the solution space for a new machine learning algorithm and
application in support of our plant breeding organization, the main drivers for
our solution were global deployability, application uptime, and scalability.

---

### Solutions considered:
A RESTful web service seemed to be an obvious way to solve the problem
presented. AWS has several patterns that could implement a RESTful
web service e.g. API Gateway / Lambda, EC2 / Autoscaling, Classic ECS, ECS
Fargate etc.

At the time the project came into our backlog we had just heard of ECS Fargate. 
ECS Fargate does have a few limitations (scratch storage, CPU and memory) none of
which were a problem. So EC2 / Autoscaling and Classic ECS were ruled out because 
they would have introduced unneeded complexity. The unneeded complexity is mostly
around management of EC2 instances to either run the application or the container
needed for the solution.

When the project came into our group there had been a substantial proof-of-concept 
done. This proof-of-concept had been done with a Docker container. While we are strong
API Gateway / Lambda proponents there is no need to re-invent the wheel and
Fargate would easily run the existing container. So... we had an ECS Fargate
project!

---

### Solution description:
**Overview:**

our group is very biased toward using existing AWS services to bring a complete project 
to the production environment. With that said here is list of the AWS services used for 
the complete solution:
* CodeCommit, CodePipeline and CodeBuild are used for the CI/CD tooling
* CloudFormation is our preferred method to describe, create and manage AWS resources
* AWS Elastic Container Registry is used to store the needed Docker container image
* AWS Systems Manager Parameter Store (SSM) to hold secrets like database passwords
* and obviously ECS Fargate for the actual application stack

**CI/CD Pipeline:** 

A complete discussion of the CI/CD pipeline for the project is beyond the scope of this
post. However, in broad strokes the pipeline is:
1. Compile some C++ code wrapped in Python, create a Python wheel and publish it to an artifact store
2. Create a Docker image with that wheel installed and publish it to ECR
3. Deploy and test the new image to our test environment
4. Deploy the new image to the production environment

![Pipeline Image](http://static.mknote.us/PolarisPipeline.png)


**The solution:**

As mentioned above the Polaris application is a Docker container deployed into
AWS ECS Fargate and uses an Aurora PostgreSQL DB for the backend data. The
application itself is only needed internally so the Application Load Balancer is
created with the scheme set to "internal" and deployed into our private
application subnets.

![Pipeline Image](http://static.mknote.us/Polaris.png)

Our environments are all constructed with CloudFormation templates. Each environment is constructed
in a separate AWS account and connected back to a central utility account. The infrastructure stacks 
export a number useful bits like VPC, subnets, IAM roles, security groups etc. This scheme allows us
to move projects through the several accounts without changing the CloudFormation templates just the 
parameters that are fed into them.

For this solution we leverage an existing VPC, set of subnets, IAM role and ACM certificate in the
us-east-1 region. The solution CloudFormation stack describes and manages the following resources:
* **AWS::ECS::Cluster**
* AWS::EC2::SecurityGroup
* AWS::EC2::SecurityGroupIngress
* AWS::Logs::LogGroup
* **AWS::ECS::TaskDefinition**
* AWS::ElasticLoadBalancingV2::LoadBalancer
* AWS::ElasticLoadBalancingV2::TargetGroup
* AWS::ElasticLoadBalancingV2::Listener
* **AWS::ECS::Service**
* AWS::ApplicationAutoScaling::ScalableTarget
* AWS::ApplicationAutoScaling::ScalingPolicy
* AWS::ElasticLoadBalancingV2::ListenerRule
* AWS::Route53::RecordSet

A complete discussion of all the resources for the solution is beyond the scope
of this post. However, we can explore the resource definitions of the ECS
Fargate specific components. The following three simple segments of
CloudFormation are all that is needed to create an ECS Fargate stack. *More complete
example CloudFormation templates are linked below with stack creation instructions.*

**AWS::ECS::Cluster:**
```
"ECSCluster": {
    "Type":"AWS::ECS::Cluster",
    "Properties" : {
        "ClusterName" : { "Ref": "clusterName" }
    }
}
```
The *ECS Cluster* resource is a very simple grouping for the other ECS resources
that will be created. The cluster created in this stack will hold the tasks and
service that will implement that actual solution. Finally, in the AWS console, the
cluster is the entry point to find info about your ECS resources.

**AWS::ECS::TaskDefinition:**
```
"fargateDemoTaskDefinition": {
    "Type": "AWS::ECS::TaskDefinition",
    "Properties": {
        "ContainerDefinitions": [
            {
                "Essential": "true",
                "Image": { "Ref": "taskImage" },
                "LogConfiguration": {
                    "LogDriver": "awslogs",
                    "Options": {
                        "awslogs-group": {
                            "Ref": "cloudwatchLogsGroup"
                        },
                        "awslogs-region": {
                            "Ref": "AWS::Region"
                        },
                        "awslogs-stream-prefix": "fargate-demo-app"
                    }
                },
                "Name": "fargate-demo-app",
                "PortMappings": [
                    {
                        "ContainerPort": 80
                    }
                ]
            }
        ],
        "ExecutionRoleArn": {"Fn::ImportValue": "fargateDemoRoleArnV1"},
        "Family": {
            "Fn::Join": [
                "",
                [ { "Ref": "AWS::StackName" }, "-fargate-demo-app" ]
            ]
        },
        "NetworkMode": "awsvpc",
        "RequiresCompatibilities" : [ "FARGATE" ],
        "TaskRoleArn": {"Fn::ImportValue": "fargateDemoRoleArnV1"},
        "Cpu": { "Ref": "cpuAllocation" },
        "Memory": { "Ref": "memoryAllocation" }
    }
}
```
The *ECS Task Definition* is where we specify and configure the container.
Interesting things to note are the CPU and memory configuration 
items. It is important to note there are valid combinations CPU/Memory settings:

|CPU       |Memory                                      |
|----------|--------------------------------------------|
|0.25 vCPU |0.5GB, 1GB, and 2GB                         |
|0.5 vCPU  |Min. 1GB and Max. 4GB, in 1GB increments    |
|1 vCPU    |Min. 2GB and Max. 8GB, in 1GB increments    |
|2 vCPU    |Min. 4GB and Max. 16GB, in 1GB increments   |
|4 vCPU    |Min. 8GB and Max. 30GB, in 1GB increments   |


**AWS::ECS::Service:**
```
"fargateDemoService": {
     "Type": "AWS::ECS::Service",
     "DependsOn": [
         "fargateDemoALBListener"
     ],
     "Properties": {
         "Cluster": { "Ref": "ECSCluster" },
         "DesiredCount": { "Ref": "minimumCount" },
         "LaunchType": "FARGATE",
         "LoadBalancers": [
             {
                 "ContainerName": "fargate-demo-app",
                 "ContainerPort": "80",
                 "TargetGroupArn": { "Ref": "fargateDemoTargetGroup" }
             }
         ],
         "NetworkConfiguration":{
             "AwsvpcConfiguration":{
                 "SecurityGroups": [
                     { "Ref":"fargateDemoSecuityGroup" }
                 ],
                 "Subnets":[
                    {"Fn::ImportValue": "privateSubnetOneV1"},
                    {"Fn::ImportValue": "privateSubnetTwoV1"},
                    {"Fn::ImportValue": "privateSubnetThreeV1"}
                 ]
             }
         },
         "TaskDefinition": { "Ref":"fargateDemoTaskDefinition" }
     }
}
```
The *ECS Service* resource is how we can configure where and how many 
instances of tasks are executed to solve our problem. In this case we see
that there will be at least *minimumCount* instances of the task running in
any of three private subnets in our VPC.

---

### The complete story:
The snippets above are instructive but not complete. If you want to explore a
mostly complete sanitized version of the stack there are two repos at GitHub you
can explore.

*Note: the components in these repos are just code to show "It works!" from an
ECS Fargate solution*:
* [Fargate demo infrastructure](https://github.com/cmrsol/fargate-demo-infrastructure)
* [Fargate demo](https://github.com/cmrsol/fargate-demo)
