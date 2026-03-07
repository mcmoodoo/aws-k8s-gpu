"""
Set GPU node group desired capacity. Invoked by EventBridge on a schedule.
Event payload: {"desired_capacity": 1} or {"desired_capacity": 0}
"""
import os
import boto3

def handler(event, context):
    desired = int(event.get("desired_capacity", 0))
    cluster = os.environ["EKS_CLUSTER_NAME"]
    nodegroup = os.environ["EKS_NODEGROUP_NAME"]

    eks = boto3.client("eks")
    ng = eks.describe_nodegroup(clusterName=cluster, nodegroupName=nodegroup)
    asg_name = ng["nodegroup"]["resources"]["autoScalingGroups"][0]["name"]

    asg = boto3.client("autoscaling")
    asg.set_desired_capacity(AutoScalingGroupName=asg_name, DesiredCapacity=desired)

    return {"status": "ok", "asg": asg_name, "desired_capacity": desired}
