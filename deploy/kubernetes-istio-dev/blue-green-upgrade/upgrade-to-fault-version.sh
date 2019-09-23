#!/usr/bin/env bash
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR"/.. || exit; pwd)

if [[ -z "$PRE_VERSION" ]] ; then
    echo "Cannot find PRE_VERSION var"
    exit 1
fi

if [[ -z "$NEW_VERSION" ]] ; then
    echo "Cannot find NEW_VERSION var"
    exit 1
fi

pv=$PRE_VERSION
nv=$NEW_VERSION

echo "Starting blue green upgrading front-end service from $pv to version $nv"
kubectl delete -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"
echo "Apply deployment version $nv to kube"
kubectl apply -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"

echo "Add route traffic to $nv based on http header x-version=$nv, leaving all other to $pv"
kubectl apply -f "$ROOT_DIR/manifest-networking/svc-fault-$nv-added.yaml"

echo "Start canary testing"
cd /opt/js-engine-dev || exit
node index.js -f sock-shop-header.js -c "username=test" -c "password=test" -a "$pv" -a "$nv"
level=$?

if [ $level == 2 ]
then 
    msg="version $nv synthetic test failure, remove route traffic to the version $nv"
    rollback msg "$pv" "$nv"
elif [ $level == 1 ]
then
msg="version $nv respsoneTime is slower than previous version $pv, remove route traffic to the version $nv"
rollback msg "$pv" "$nv"
else
   cd "$SCRIPT_DIR" || exit
   array=( 10 50 100 )
   for i in "${array[@]}"
   do
      weighttest "$i" "$pv" "$nv"
      level=$?
      if [ $level != 0 ]
      then
         break
      fi
   done 
fi

rollback(){
    local msg=$1
    local pv=$2
    local nv=$3   
    echo "$msg"
    cd "$SCRIPT_DIR" || exit
    kubectl apply -f "$ROOT_DIR/manifest-networking/svc-normal-$pv.yaml"
    echo "String remove deployment of version $nv"
    kubectl delete -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"
    echo "Remove version $nv finished"
}

weighttest(){
   rw=$1
   local pv=$2
   local nv=$3
   echo "Add route traffic to $nv weighted $rw, leaving all other to $pv"
   kubectl apply -f "$ROOT_DIR/manifest-networking/svc-normal-$nv-$rw.yaml"
   echo "Start canary testing"
   cd /opt/js-engine-dev || exit
   node index.js -f sock-shop-header.js -c username=test -c password=test -a "$pv" -a "$nv"
   level=$?
   
   if [ $level == 2 ]
   then
     msg="version $nv with route weight $rw synthetic test failure, remove route traffic to the version $nv"
     rollback msg "$pv" "$nv"
     return 2 
   elif [ $level == 1 ]
   then
     if [ "$rw" -gt 50 ]
     then
       msg="version $nv with route weight $rw respsoneTime is slower than previous version $pv, remove route traffic to the version $nv"
       rollback msg "$pv" "$nv"
       return 1 
     else
       return 0
     fi
   else
     return 0
   fi
}