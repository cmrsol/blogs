_This post was contributed by Duke Takle and Kevin Hayes from the Corteva Agriscience™, the Agricultural Division of DowDuPont team._

  

### Introduction:

  

At Corteva Agriscience™, the Agricultural Division of DowDuPont, our purpose is to enrich the lives of those who produce and those who consume, ensuring progress for generations to come. We support a network of research stations to improve agricultural productivity around the world. As analytical technology advances the volume of data, as well as the speed at which it must be processed to meet the needs of our scientists poses unique challenges. Corteva Cloud Engineering teams are responsible for collaborating with and enabling software developers, data scientists, and others to allow Corteva research and development to become the most efficient innovation machine in the Agricultural industry.

Recently, our Systems and Innovations for Breeding and Seed Products organization approached the Cloud Engineering team with the challenge of how to deploy a novel machine learning algorithm for scoring genetic markers. The solution would require supporting labs across six continents in a process that is run daily. This algorithm replaces time-intensive manual scoring of genotypic assays with a robust, automated solution. When examining the solution space for this challenge, the main requirements for our solution were global deployability, application uptime, and scalability.

Prior to the implementing this algorithm in AWS, machine learning autoscoring was done as a proof of concept using pre-production instances on premise and required several technicians to continue to process assays by hand. After implementing on AWS, we have enabled those technicians to be better utilized in other areas such as technology development.

  

### Solutions considered:

  
A RESTful web service seemed to be an obvious way to solve the problem presented. AWS has several patterns that could implement a RESTful web services such as API Gateway / Lambda, EC2 / Autoscaling, Classic ECS, and ECS Fargate.

At the time the project came into our backlog we had just heard of ECS Fargate. ECS Fargate does have a few limitations (scratch storage, CPU and memory) none of which were a problem. So EC2 / Autoscaling and Classic ECS were ruled out because they would have introduced unneeded complexity. The unneeded complexity is mostly around management of EC2 instances to either run the application or the container needed for the solution.

When the project came into our group there had been a substantial proof-of-concept done. This proof-of-concept had been done with a Docker container. While we are strong API Gateway / Lambda proponents there is no need to duplicate processes or services that AWS provides. We also knew we needed to be able to move fast and we wanted to put the power in the hands of our developers to focus on building out the solution. Additionally, we needed something that could scale across our organization and provide some rationalization in how we approach these problems. Leveraging AWS services such as AWS Fargate, AWS CodePipeline, and AWS CloudFormation made that possible.

  

----------

### Solution description:

**Overview:**

Our group prefers using existing AWS services to bring a complete project to the production environment. We used:

-   CodeCommit, CodePipeline and CodeBuild are used for the CI/CD tooling
-   CloudFormation is our preferred method to describe, create and manage AWS resources
-   AWS Elastic Container Registry is used to store the needed Docker container image
-   AWS Systems Manager Parameter Store (SSM) to hold secrets like database passwords
-   and obviously ECS Fargate for the actual application stack

**CI/CD Pipeline:**

A complete discussion of the CI/CD pipeline for the project is beyond the scope of this post. However, in broad strokes the pipeline is:

1.  Compile some C++ code wrapped in Python, create a Python wheel and publish it to an artifact store
2.  Create a Docker image with that wheel installed and publish it to ECR
3.  Deploy and test the new image to our test environment
4.  Deploy the new image to the production environment

![Pipeline Image](http://static.mknote.us/PolarisPipeline.png)

**The solution:**

As mentioned above the application is a Docker container deployed into AWS ECS Fargate and uses an Aurora PostgreSQL DB for the backend data. The application itself is only needed internally so the Application Load Balancer is created with the scheme set to "internal" and deployed into our private application subnets.

![Pipeline Image](http://static.mknote.us/Polaris.png)


Our environments are all constructed with CloudFormation templates. Each environment is constructed in a separate AWS account and connected back to a central utility account. The infrastructure stacks export a number useful bits like VPC, subnets, IAM roles, security groups etc. This scheme allows us to move projects through the several accounts without changing the CloudFormation templates just the parameters that are fed into them.

For this solution we leverage an existing VPC, set of subnets, IAM role and ACM certificate in the us-east-1 region. The solution CloudFormation stack describes and manages the following resources:

```
AWS::ECS::Cluster*
AWS::EC2::SecurityGroup
AWS::EC2::SecurityGroupIngress
AWS::Logs::LogGroup
AWS::ECS::TaskDefinition*
AWS::ElasticLoadBalancingV2::LoadBalancer
AWS::ElasticLoadBalancingV2::TargetGroup
AWS::ElasticLoadBalancingV2::Listener
AWS::ECS::Service*
AWS::ApplicationAutoScaling::ScalableTarget
AWS::ApplicationAutoScaling::ScalingPolicy
AWS::ElasticLoadBalancingV2::ListenerRule
```

  
A complete discussion of all the resources for the solution is beyond the scope of this post. However, we can explore the resource definitions of the ECS Fargate specific components. The following three simple segments of CloudFormation are all that is needed to create an ECS Fargate stack.  **More complete example CloudFormation templates are linked below with stack creation instructions.**

**AWS::ECS::Cluster:**

```
"ECSCluster": {
    "Type":"AWS::ECS::Cluster",
    "Properties" : {
        "ClusterName" : { "Ref": "clusterName" }
    }
}
```

  
The *ECS Cluster* resource is a very simple grouping for the other ECS resources that will be created. The cluster created in this stack will hold the tasks and service that will implement that actual solution. Finally, in the AWS console, the  
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
  
The  `ECS Task Definition` is where we specify and configure the container. Interesting things to note are the CPU and memory configuration items. It is important to note there are valid combinations CPU/Memory settings:

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
    
The `ECS Service` resource is how we can configure where and how many instances of tasks are executed to solve our problem. In this case we see that there will be at least *minimumCount* instances of the task running in any of three private subnets in our VPC.

----------

**Wrap Up:**

Deploying this algorithm on AWS using containers and Fargate allowed us to start running the application at scale with low support overhead. This has resulted in faster turnaround time with fewer staff and a concomitant reduction in cost. "We are very excited with the deployment of Polaris, the autoscoring of the marker lab genotyping data using AWS technologies. This key technology deployment has enhanced performance, scalability and efficiency of our global labs to deliver over 1.4 Billion data points annually to our key customers in Plant Breeding and Integrated Operations." said Sandra Milach, Director of Systems and Innovations for Breeding and Seed Products. We are distributing this solution to all our worldwide laboratories that will harmonize data quality and speed, enabling an increase in the velocity of genetic gain to increase yields of crops for farmers around the world.

You can learn more about the work we do at Corteva at  [https://www.corteva.com/](https://www.corteva.com/)

**Try it yourself:**

The snippets above are instructive but not complete. We have published two repositories on GitHub that you can explore to see how we built this solution:

  

**_Fargate demo infrastructure_** [https://github.com/cmrsol/fargate-demo-infrastructure](https://github.com/cmrsol/fargate-demo-infrastructure)  
_**Fargate demo**_ [https://github.com/cmrsol/fargate-demo](https://github.com/cmrsol/fargate-demo)

_Note: the components in these repos do not include our production code, but they will show you how this works using Amazon ECS and AWS Fargate._
