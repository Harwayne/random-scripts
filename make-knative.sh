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
head=false

for arg in "$@"
do
  if startsWith "$arg" "--"; then
    if [ "$arg" = "--nocreate" ]; then
      create=false
    elif startsWith "$arg" "--zone="; then
      # len(--zone=) = 7
      zone=${arg:7}
    elif [ "$arg" = "--head" ]; then
      head=true
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

## Istio

if $head ; then
  ## Move to Serving.
  pushd ~/go/src/github.com/knative/serving
  kubectl apply -f ./third_party/istio-1.0.1/istio.yaml
  popd
else
  kubectl apply -f https://raw.githubusercontent.com/knative/serving/v0.1.1/third_party/istio-1.0.1/istio.yaml
  kubectl label namespace default istio-injection=enabled
fi

watch kubectl get pods -n istio-system

## Build
if $head ; then
  pushd ~/go/src/github.com/knative/serving
  kubectl apply -f ./third_party/config/build/release.yaml
  popd
else
  kubectl apply -f https://raw.githubusercontent.com/knative/serving/v0.1.1/third_party/config/build/release.yaml
fi

watch kubectl get pods -n knative-build

## Serving
if $head ; then
  pushd ~/go/src/github.com/knative/serving
  # Use my custom config-network.yaml instead of the original
  ko apply -f config/
  popd
else
  kubectl apply -f https://github.com/knative/serving/releases/download/v0.1.1/release.yaml
fi

watch kubectl get pods -n knative-serving

## Reserved domain and IP.
kubectl apply -f ~/knative/config-domain.yaml
kubectl patch svc knative-ingressgateway -n istio-system --patch '{"spec": { "loadBalancerIP": "35.224.154.114" }}'

## Eventing
pushd ~/go/src/github.com/knative/eventing
ko apply -f config/
popd

watch kubectl get pods -n knative-eventing

# Cluster Stub Bus
if $head ; then
  kubectl apply -f https://storage.googleapis.com/knative-releases/eventing/latest/release-clusterbus-stub.yaml
else
  ko apply -f ~/knative/stub-bus.yaml
fi
