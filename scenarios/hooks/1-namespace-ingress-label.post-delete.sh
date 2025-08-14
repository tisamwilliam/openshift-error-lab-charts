#!/usr/bin/bash

kubectl -n openshift-ingress set env deploy/router-default-esun \
  NAMESPACE_LABELS='ingress=default'- \
  --containers="$(kubectl -n openshift-ingress get deploy/router-default-esun -o jsonpath='{.spec.template.spec.containers[0].name}')"

kubectl -n openshift-ingress rollout status deploy/router-default-esun --timeout=10m
