#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR"/.. || exit; pwd)

nv="v1"
echo "Apply deployment version $nv to kube"
kubectl apply -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"

while [ 1 ]
do
    ava=`(kubectl get deployment front-end-$nv  -n sock-shop | awk -F' ' '{print $4}' | grep -v AVAILABLE)`
    if [ $ava -gt 0 ]
    then
    break
    else
    echo "waiting pod started ... "
    sleep 2
    fi
done 
echo "Apply deployment front-end-$nv success!"

kubectl apply -f "$ROOT_DIR/manifest-networking/svc-$nv.yaml"

echo "Apply traffic finish"