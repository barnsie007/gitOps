#!/bin/bash

#run scripts at relative path
scriptdir="$(dirname "$0")"
cd "$scriptdir"

source ../config.txt 
#
# Set uo NFS storage on fyre cluster. This script will do the following:
#   - Create storage directories for couch DB and neo4j
#   - Create NFS config in /etc/exports and exportfs it
#   - Log in to each worker and create the storage locations and mount them
#   - Create the PVs for couch and neo4j
#
# For simplicity, setting open permissions on the storage - TODO: Change this and pass in supplementalGroups when installing.
#
if grep couch /etc/exports; then
        echo "[INFO\ Detected couch directory in /etc/exports. Assuming NFS is already set up."
        exit 0
fi



####
echo "[INFO] Getting infrastructure ip"
# using the private IP (10..) as using the public IP gives problems when mounting in the workers.
# Can be tricky to get the private ip (10..) as there can be multiple 10.. on the fyre systems (as returned by `hostname -I`). Following seems reliable so far:
infra_ip=$(ip addr show label 'e*' | grep -Po 'inet \K[\d.]+' | grep ^10)

echo "[INFO] Getting worker ips"
workers=$(oc get nodes --no-headers | awk '{print$1}' | grep worker)
master=$(ping -c 1 api.${clustername}.cp.fyre.ibm.com  | awk 'NR==1{print$3}' | sed -e "s/(//g" -e "s/)//g")

echo "what is master $master "


###set the ssh key


expect -c "set timeout -1
spawn ssh-copy-id root@$master
expect {Are you sure you want to continue connecting}
send {yes}; send \r
expect {password:}
send {$serverPassword}; send \r
expect eof"


######

worker_ips=""
for worker in $workers; do

         ip=$(ping -c 1 $worker | awk 'NR==1{print$3}' | sed -e "s/(//g" -e "s/)//g")

         worker_ips="${worker_ips} $ip"

done

echo "[INFO] Worker IPs: $worker_ips"

ssh -o StrictHostKeychecking=no "root@${master}" > nfs_${wip}.log << EOF
                sudo mkdir /root/couch
                sudo mkdir /root/neo4j
               sudo  chmod -R 777 /root/couch
               sudo  chmod -R 777 /root/neo4j
EOF

ssh -t $master  'ip addr show label 'e*'' | grep 'inet 10' > ip.txt

master_ip=`cat ip.txt | tail -n 1 | awk -F / '{print $1}' | awk '{print $2}'`

echo "Master private IP is: $master_ip"


for wip in $worker_ips; do

        echo "[INFO] Logging on to $worker_ips"

        ssh -o StrictHostKeychecking=no "root@${master}" > nfs_${wip}.log << EOF

                 echo "/root/couch        $wip(rw,sync,no_wdelay,no_root_squash,insecure)" >> /etc/exports
                 echo "/root/neo4j        $wip(rw,sync,no_wdelay,no_root_squash,insecure)" >> /etc/exports
                 

EOF

done

ssh -o StrictHostKeychecking=no "root@${master}" > nfs_${wip}.log << EOF
               exportfs -a 

EOF


#echo "[INFO] Making /root/couch and /root/neo4j dirs"
#mkdir /root/couch
#mkdir /root/neo4j

#echo "[INFO] Updating /etc/exports"
#for wip in $worker_ips; do

#        echo "/root/couch        $wip(rw,sync,no_wdelay,no_root_squash,insecure)" >> /etc/exports
#        echo "/root/neo4j        $wip(rw,sync,no_wdelay,no_root_squash,insecure)" >> /etc/exports

#done

#echo "[INFO] Exporting /etc/exports configuration"
#exportfs -a

sleep 10

echo "[INFO] Log on to each worker and mount the directories"
for wip in $worker_ips; do

        echo "[INFO] Logging on to $worker_ips"

        ssh -o StrictHostKeychecking=no "core@${wip}" > nfs_${wip}.log << EOF
                sudo mkdir /root/couch
                sudo mount -t nfs $master_ip:/root/couch /root/couch
                sudo mkdir /root/neo4j
                sudo mount -t nfs $master_ip:/root/neo4j /root/neo4j
EOF

done

echo "[INFO] Opening permissions on dirs"
chmod -R 777 /root/couch /root/neo4j

echo "[INFO] Creating pv01"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv01
spec:
  capacity:
    storage: 20Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /root/couch
    server: $master_ip
  persistentVolumeReclaimPolicy: Recycle
EOF

echo "[INFO] Creating pv02"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv02
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /root/neo4j
    server: $master_ip
  persistentVolumeReclaimPolicy: Recycle
EOF

echo "[INFO] Done"

