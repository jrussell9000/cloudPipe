#! /usr/bin/env bash

KUBE_VERSION=1.31
aws eks describe-addon-versions  \
--kubernetes-version=$KUBE_VERSION \
--query 'sort_by(addons  &owner)[].{owner: owner, addonName: addonName}' \
--output table
