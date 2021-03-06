#!/bin/bash
# ===============LICENSE_START=======================================================
# Acumos Apache-2.0
# ===================================================================================
# Copyright (C) 2018 AT&T Intellectual Property & Tech Mahindra. All rights reserved.
# ===================================================================================
# This Acumos software file is distributed by AT&T and Tech Mahindra
# under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# This file is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===============LICENSE_END=========================================================
#
#. What this is: Script to aid in testing an Acumos solution/model as deployed
#. by deploy.sh
#. 
#. Prerequisites:
#. - Ubuntu Xenial or Centos 7 server
#. - Via the Acumos platform, download a solution.zip deployment package for
#.   a specific solution/revision, and unzip the package into a folder.
#. - Install the solution via deploy.sh (see the script for details)
#. Usage:
#. - bash test-model.sh "<input>" "<host>"
#.   input: quoted string of test data to pass to the model
#.   host: host (name or IP address) where the model is deployed at port 30555

trap 'fail' ERR

function fail() {
  log "$1"
  exit 1
}

function log() {
  set +x
  fname=$(caller 0 | awk '{print $2}')
  fline=$(caller 0 | awk '{print $1}')
  echo; echo "$fname:$fline ($(date)) $1"
  set -x
}

function setup_prereqs() {
  if [[ "$(dpkg -l | grep jq)" == "" ]]; then
    log "Install jq"
    sudo apt install -y jq
  fi

  if [[ "$(dpkg -l | grep golang-go)" == "" ]]; then
    log "Install golang-go"
    sudo apt install -y golang-go
  fi

  if [[ "$(dpkg -l | grep unzip)" == "" ]]; then
    log "Install unzip"
    sudo apt install -y unzip
  fi

  if [[ "$(ls ~/protoc/bin/protoc)" == "" ]]; then
    log "Download and install protobuf 3 (protoc) in ~/protoc"
    # Per https://github.com/protocolbuffers/protobuf/releases
    wget https://github.com/protocolbuffers/protobuf/releases/download/v3.6.1/protoc-3.6.1-linux-x86_64.zip
    unzip protoc-3.6.1-linux-x86_64.zip -d ~/protoc
  fi
}

function find_node() {
  nodes=$(jq '.nodes | length' blueprint.json)
  n=0; inputnode=''
  while [[ $n -lt $nodes ]] ; do
    name=$(jq -r ".nodes[$n].container_name" blueprint.json)
    if [[ $name == $1 ]]; then
      node=$n
    fi
    n=$[$n+1]
  done
}

function test_model() {
  firstms=$(jq -r '.input_ports[0].container_name' blueprint.json)
  find_node $firstms
  if [[ $(jq -r ".nodes[$node].node_type" blueprint.json) == DataBroker ]]; then
    firstms=$(jq -r ".nodes[$node].operation_signature_list[0].connected_to[0].container_name" blueprint.json)
    find_node $firstms
  fi

  firstop=$(jq -r ".nodes[$node].operation_signature_list[0].operation_signature.operation_name" blueprint.json)
  firstmsg=$(jq -r ".nodes[$node].operation_signature_list[0].operation_signature.input_message_name" blueprint.json)
  firstpkg=$(grep package microservice/$firstms/model.proto | cut -d ' ' -f 2 | sed 's/;//')
  nextms=$(jq -r ".nodes[$node].operation_signature_list[0].connected_to[0].container_name" blueprint.json)
  while [[ $nextms != null ]] ; do
    find_node $nextms
    lastms=$(jq -r ".nodes[$node].container_name" blueprint.json)
    lastmsg=$(jq -r ".nodes[$node].operation_signature_list[0].operation_signature.output_message_name" blueprint.json)
    lastpkg=$(grep package microservice/$lastms/model.proto | cut -d ' ' -f 2 | sed 's/;//')
    nextms=$(jq -r ".nodes[$node].operation_signature_list[0].connected_to[0].container_name" blueprint.json)
  done
  set -x
  echo "$input" \
		| ~/protoc/bin/protoc --encode=$firstpkg.$firstmsg \
		    --proto_path=microservice/$firstms microservice/$firstms/model.proto \
		| curl -s --request POST --header "Content-Type: application/protobuf" \
		    --data-binary @- http://$host:30555/$firstop \
		| ~/protoc/bin/protoc --decode $lastpkg.$lastmsg \
		    --proto_path=microservice/$lastms microservice/$lastms/model.proto
  set +x
}

input="$1"
host=$2

setup_prereqs
test_model
