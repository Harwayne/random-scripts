#!/bin/bash

# https://github.com/knative/docs/blob/master/install/Knative-with-GKE.md

set -e -u

startsWith() {
  str="$1"
  prefix="$2"
  case "$str" in "$prefix"*)
    true
    ;;
  *)
    false
    ;;
  esac
}

create=true
zone=us-central1-a
name=""

for arg in "$@"
do
  if startsWith "$arg" "--"; then
    if [ "$arg" = "--nocreate" ]; then
      create=false
    elif startsWith "$arg" "--zone="; then
      # len(--zone=) = 7
      zone=${arg:7}
    else
      echo "Unknown argument: '$arg'"
      exit 1
    fi
  else
    if [ "$name" = "" ]; then
      name="$arg"
    else
      echo "Name has already been set, can't set it a second time: '$name', '$arg'"
      exit 2
    fi
  fi
done

if [ "$name" = "" ]; then
  echo "Name must be set, provide an argument without a leading --"
  exit 3
fi

echo "Setting up '$name' in zone '$zone'. Creating: $create"

set -x

if $create ; then
  gcloud container clusters create $name \
    --zone=$zone \
    --cluster-version=latest \
    --machine-type=n1-standard-4 \
    --enable-autoscaling --min-nodes=1 --max-nodes=10 \
    --enable-autorepair \
    --scopes=service-control,service-management,compute-rw,storage-ro,cloud-platform,logging-write,monitoring-write,pubsub,datastore \
    --num-nodes=3
fi

gcloud container clusters get-credentials $name --zone=$zone

kubectl create clusterrolebinding cluster-admin-binding \
--clusterrole=cluster-admin \
--user=$(gcloud config get-value core/account)

kubectl apply -f https://raw.githubusercontent.com/knative/serving/v0.1.1/third_party/istio-0.8.0/istio.yaml
kubectl label namespace default istio-injection=enabled
watch kubectl get pods -n istio-system

kubectl apply -f https://github.com/knative/serving/releases/download/v0.1.1/release.yaml
watch kubectl get pods -n knative-serving

kubectl apply -f https://raw.githubusercontent.com/knative/serving/v0.1.1/third_party/config/build/release.yaml
watch kubectl get pods -n knative-build

kubectl apply -f ~/knative/config-domain.yaml
kubectl patch svc knative-ingressgateway -n istio-system --patch '{"spec": { "loadBalancerIP": "35.224.154.114" }}'

echo "You should be at the root of the eventing repo..."
ko apply -f config/
watch kubectl get pods -n knative-eventing

ko apply -f ~/knative/stub-bus.yaml

