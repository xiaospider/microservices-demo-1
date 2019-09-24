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

wait_confirm () {
    local msg=$1
    read -p "Are you sure $msg ?" -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        return 0
    elif [[ $REPLY =~ ^[Nn]$ ]]
    then
        return 1
    fi
}

rollback () {
    local msg=$1
    local pv=$2
    local nv=$3   
    echo "$msg"
    cd "$SCRIPT_DIR" || exit
    wait_confirm " remove service version $nv "
    kubectl apply -f "$ROOT_DIR/manifest-networking/svc-$pv.yaml"
    echo "Starting remove deployment of version $nv ... "
    kubectl delete -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"
    echo "Remove version $nv finished!"
}

weighttest () {
   rw=$1
   local pv=$2
   local nv=$3
   echo "Add route traffic to $nv weighted $rw, leaving all other to $pv"
   kubectl apply -f "$ROOT_DIR/manifest-networking/svc-$nv-$rw.yaml"
   echo "Start canary testing"
   cd /opt/js-engine-dev || exit
   node index.js -f sock-shop-header.js -c username=test -c password=test -a "$pv" -a "$nv"
   level=$?
   
   if [ $level == 2 ]
   then
     msg="Version $nv with route traffice weighted $rw synthetic test failure, remove route traffic to the version $nv"
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

deploy () {
    echo "Starting blue green upgrading front-end service from $pv to version $nv"
    kubectl delete -f "$ROOT_DIR/manifests-versions/front-end-dep-$nv.yaml"
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
}

addtraffic () {
    echo "Add route traffic to $nv based on http header x-version=$nv, leaving all other to $pv"
    kubectl apply -f "$ROOT_DIR/manifest-networking/svc-$nv.yaml"
    sleep 2
    echo "Add route traffic success!"
}

remove_previous_version () {
    echo "All traffic routed to new version $nv, will remove deployment of old version $pv ... "
    wait_confirm " remove deployment version $pv "
    local level=$?
    if [ $level == 0 ]
    then
        kubectl delete -f "$ROOT_DIR/manifests-versions/front-end-dep-$pv.yaml"
        echo "Remove version $pv finished!"
    fi
}

main () {

    deploy
    addtraffic

    echo "Start canary testing"
    cd /opt/js-engine-dev || exit
    node index.js -f sock-shop-header.js -c "username=test" -c "password=test" -a "$pv" -a "$nv"
    level=$?

    if [ $level == 2 ]
    then 
        msg="Version $nv canary test failure, remove route traffic to the version $nv"
        rollback msg "$pv" "$nv"
    elif [ $level == 1 ]
    then
        msg="Version $nv respsoneTime is slower than previous version $pv, remove route traffic to the version $nv"
        rollback msg "$pv" "$nv"
    else
        echo "0 weight traffic test passed for version $nv !"
        cd "$SCRIPT_DIR" || exit
        array=( 10 50 100 )
        for i in "${array[@]}"
        do
            wait_confirm " add route traffic to $nv weighted $rw "
            weighttest "$i" "$pv" "$nv"
            level=$?
            if [ $level != 0 ]
            then
                break
            fi
        done
        remove_previous_version
        echo " Upgrade finished, the finally version is $nv"
    fi
    
}

main