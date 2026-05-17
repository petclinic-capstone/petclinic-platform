"""
PetClinic Cost Control Lambda
Handles stop / start / status of RDS and EKS node group on demand.
Invoked from the terminal cost-control.sh script via AWS CLI.
"""

import boto3
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

REGION          = os.environ["AWS_REGION"]
RDS_IDENTIFIER  = os.environ["RDS_IDENTIFIER"]
EKS_CLUSTER     = os.environ["EKS_CLUSTER"]
EKS_NODEGROUP   = os.environ["EKS_NODEGROUP"]
NODE_MIN        = int(os.environ.get("NODE_MIN", "2"))
NODE_MAX        = int(os.environ.get("NODE_MAX", "4"))

rds = boto3.client("rds",  region_name=REGION)
eks = boto3.client("eks",  region_name=REGION)
ec2 = boto3.client("ec2",  region_name=REGION)


def get_status():
    """Return current state of RDS and EKS nodes."""
    rds_resp = rds.describe_db_instances(DBInstanceIdentifier=RDS_IDENTIFIER)
    rds_status = rds_resp["DBInstances"][0]["DBInstanceStatus"]

    ng_resp  = eks.describe_nodegroup(clusterName=EKS_CLUSTER, nodegroupName=EKS_NODEGROUP)
    ng       = ng_resp["nodegroup"]
    ng_status  = ng["status"]
    desired    = ng["scalingConfig"]["desiredSize"]
    running    = ng.get("resources", {}).get("autoScalingGroups", [])

    return {
        "rds_status":     rds_status,
        "nodegroup_status": ng_status,
        "nodes_desired":  desired,
        "message":        f"RDS: {rds_status} | Nodes desired: {desired} ({ng_status})"
    }


def stop_resources():
    """Stop RDS and scale nodes to 0 — eliminates EC2 and RDS compute charges."""
    results = []

    # Stop RDS
    try:
        rds_state = rds.describe_db_instances(
            DBInstanceIdentifier=RDS_IDENTIFIER
        )["DBInstances"][0]["DBInstanceStatus"]

        if rds_state == "available":
            rds.stop_db_instance(DBInstanceIdentifier=RDS_IDENTIFIER)
            results.append("RDS: stop initiated (will reach 'stopped' in ~2 min)")
        else:
            results.append(f"RDS: already in state '{rds_state}', skip stop")
    except Exception as e:
        results.append(f"RDS stop error: {e}")

    # Scale EKS nodes to 0
    try:
        eks.update_nodegroup_config(
            clusterName=EKS_CLUSTER,
            nodegroupName=EKS_NODEGROUP,
            scalingConfig={"minSize": 0, "maxSize": NODE_MAX, "desiredSize": 0}
        )
        results.append("EKS nodes: scaling to 0 (EC2 charges stop when instances terminate)")
    except Exception as e:
        results.append(f"EKS scale-down error: {e}")

    return {"action": "stop", "results": results}


def start_resources():
    """Start RDS and restore node count — brings cluster back to operational state."""
    results = []

    # Start RDS
    try:
        rds_state = rds.describe_db_instances(
            DBInstanceIdentifier=RDS_IDENTIFIER
        )["DBInstances"][0]["DBInstanceStatus"]

        if rds_state == "stopped":
            rds.start_db_instance(DBInstanceIdentifier=RDS_IDENTIFIER)
            results.append("RDS: start initiated (will reach 'available' in ~5 min)")
        else:
            results.append(f"RDS: already in state '{rds_state}', skip start")
    except Exception as e:
        results.append(f"RDS start error: {e}")

    # Scale EKS nodes back to minimum
    try:
        eks.update_nodegroup_config(
            clusterName=EKS_CLUSTER,
            nodegroupName=EKS_NODEGROUP,
            scalingConfig={"minSize": NODE_MIN, "maxSize": NODE_MAX, "desiredSize": NODE_MIN}
        )
        results.append(f"EKS nodes: scaling back to {NODE_MIN} nodes")
    except Exception as e:
        results.append(f"EKS scale-up error: {e}")

    return {"action": "start", "results": results}


def lambda_handler(event, context):
    action = event.get("action", "status").lower()
    logger.info(f"Cost-control action requested: {action}")

    if action == "stop":
        return stop_resources()
    elif action == "start":
        return start_resources()
    elif action == "status":
        return get_status()
    else:
        return {"error": f"Unknown action '{action}'. Valid: stop | start | status"}
