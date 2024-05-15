### build OCP

#run scripts at relative path
scriptdir="$(dirname "$0")"
cd "$scriptdir"

source ./config.txt
##############
###copy back yaml files

cp ./pipeline/secret.yaml_var ./pipeline/secret.yaml

cp ./pipeline/run.yaml_var ./pipeline/run.yaml

cp ./modWL.yaml_var ./modWL.yaml

#####login to cluster

#oc login -u kubeadmin -p $clusterpassword --server=https://api.$ocpclusterName.cp.fyre.ibm.com:6443 --insecure-skip-tls-verify

####install argo CD

oc create ns openshift-gitops-operator

oc apply -f ./operatorGroup.yaml

oc apply -f ./subscription.yaml

oc get pods -n openshift-gitops-operator

echo "Waiting for Git Ops pods to be in a running state"

sleep 280

pods_count=$(oc get pods -n openshift-gitops | grep -c "Running")

echo $pods_count


while [ $pods_count -ne $(oc get pods -n openshift-gitops --no-headers | wc -l) ];
do
 echo "waiting for all pods to be ready"
 sleep 10
done

echo "All pods are ready"


####give cluster privileges to argo CD
oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops


###get the password

argoCDpassword=`oc get secret/openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d`
argoCDroute=`oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}{"\n"}'`

######Apply the IBM Operator catalog

oc apply -f ./ibm_operator.yaml

while true;
do


wloc=`oc get pods -n openshift-marketplace | grep ibm-operator-catalog | awk '{print $3}'`

echo "Waiting for IBM Catalog to be installed"

 if [ "$wloc" = "Running" ]; then
    break
  fi
  sleep 10
done

sleep 20 

#####apply the WebSphere Liberty Operator

oc apply -f ./websphere_subscription.yaml

while true;
do


wloc=`oc get pods -n openshift-operators | grep wlo-controller-manager | awk '{print $3}'`

echo "Waiting for IBM WebSphere Liberty Operator to be installed"

 if [ "$wloc" = "Running" ]; then
    break
  fi
  sleep 10
done

sleep 20


####Install the Red Had Pipeline Operators

oc create -f ./redHatPipelinesSubscription.yaml

echo "Installing Red Hat Pipeline"
sleep 120

while true;
do


redpipe=`oc get pods -n openshift-operators | grep openshift-pipelines-operator | awk '{print $3}'`

echo "Waiting for Red Hat PipeLine Operator to be installed"

 if [ "$redpipe" = "Running" ]; then
    break
  fi
  sleep 10
done

sleep 20



#####Install the Runtime Component Operator
#oc new-project runtime-component 


#oc create -k ./RCO/overlays/watch-all-namespaces/ 

#while true;
#do
#rco=`oc get pods -n runtime-component | grep rco-controller-manager | awk '{print $3}'`

#echo "Waiting for Runtime Component Operator to be installed"

# if [ "$rco" = "Running" ]; then
#    break
#  fi
#  sleep 10
#done


oc new-project $namespace 


####opening ocp route for internal registry

oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

#####################

##### set up the nfs persistence
echo "Setting up the persistence"

./nfs/testnfs.sh

sleep 20

#### create the pvc

oc create -f ./nfs/pvc.yaml

###############

############pipeline #####

oc create -f ./pipeline/git_update.yaml
oc create -f ./pipeline/mavenTask.yaml
oc create -f ./pipeline/pipeline.yaml

###set the run yaml

sed -i "s|REPO-URL|${repourl}|g" ./pipeline/run.yaml

sed -i "s|IMAGE-URL|${imageurl}|g" ./pipeline/run.yaml

sed -i "s|CLUSTERNAME|${clustername}|g" ./pipeline/run.yaml

sed -i "s|BUNDLE|${bundle}|g" ./pipeline/run.yaml

sed -i "s|DEPLOYMENTFILE|${deploymentfile}|g" ./pipeline/run.yaml

sed -i "s/USER/${user}/g" ./pipeline/run.yaml

sed -i "s|MAIL|${usermail}|g" ./pipeline/run.yaml

sed -i "s|PASSWORD|${userpassword}|g" ./pipeline/run.yaml

sed -i "s|PAC|${pac}|g" ./pipeline/secret.yaml

oc create -f ./pipeline/secret.yaml

###edit the sa pipeline to add in thje secret

oc get sa pipeline --output="yaml" > ./pipeline/saPipe.txt

echo "- name: basic-user-pass" >> ./pipeline/saPipe.txt

sed -i '/creationTimestamp/d' ./pipeline/saPipe.txt

oc apply -f ./pipeline/saPipe.txt



############

sleep 1

##### Configuring Pull Secret for Mod Resorts

###oc create secret docker-registry ta --docker-server=9.46.78.247:5000 --docker-username=admin --docker-password=admin --docker-email=croninjo@ie.ibm.com --dry-run=true --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode > ./secret/myregistryconfigjson

#oc create secret docker-registry ta --docker-server=$devRegistry --docker-username=iamapikey --docker-password=$devRegPass --docker-email=croninjo@ie.ibm.com --dry-run=true --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode > ./secret/myregistryconfigjson

#oc get secret pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode > ./secret/dockerconfigjson

#jq -s '.[0] * .[1]' ./secret/dockerconfigjson ./secret/myregistryconfigjson > ./secret/dockerconfigjson-merged

#oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=./secret/dockerconfigjson-merged


#oc patch image.config.openshift.io/cluster --type=merge -p '{"spec":{"registrySources":{"insecureRegistries":["'9.46.78.247:5000'"]}}}'

###############################################

sleep 30

#######ARGO CD Connection ###############

sed -i "s|BUNDLE|${bundle}|g" ./modWL.yaml

sed -i "s|DEPLOYMENTFILE|${argo}|g" ./modWL.yaml

echo "Creating the ArgoCD Repo connection"
oc apply -f ./modWL.yaml

###########################################################

echo "#################################################################################################################################"
echo "OCP Cluster Information"
echo "--------------------------------------"
echo "URL: https://console-openshift-console.apps.$ocpclusterName.cp.fyre.ibm.com/"
echo "Cluster username: $clusterusername"
echo "Cluster password: $clusterpassword"
echo ""
echo "-----------------------------------------------------------------------------------------------------------------------------"
echo "Login to Cluster"
echo ""
echo "oc login -u $username -p $password --server=https://api.$ocpclusterName.cp.fyre.ibm.com:6443 --insecure-skip-tls-verify"
echo ""
echo "Namespace where application is running: $namespace"
echo ""
echo "-----------------------------------------------------------------------------------------------------------------------------"
echo ""
echo "Argo CD information"
echo ""
echo "Argo CD password: $argoCDpassword"
echo "Argo CD route: $argoCDroute"
echo ""
echo "--------------------------------------"
echo "Github information"
echo ""
echo "Application Repository: $repourl"
echo ""
echo "Deployment Repository: $bundle"
echo 
echo "###################################################################################################################################"
