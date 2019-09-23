#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd $SCRIPT_DIR/..; pwd)

echo "Upgrade front-end service to version v2"
kubectl delete -f $ROOT_DIR/manifests-versions/front-end-dep-v2.yaml
kubectl apply -f $ROOT_DIR/manifests-versions/front-end-dep-v2.yaml

echo "Add route traffic to v2 based on http header x-version=v2, leaving all other to v1"
kubectl apply -f $ROOT_DIR/manifest-networking/svc-fault-v2-added.yaml

echo "Start canary testing"


echo "Rollback to the previous version"
kubectl apply -f $ROOT_DIR/manifest-networking/svc-normal-v1.yaml