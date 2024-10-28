#!/bin/bash

key="$1"

error () {
  echo "$*" >&2
  exit 1
}

if [[ -f /etc/ec2_version ]]; then
  token=""
  attempt=1
  while [[ $attempt -le 5 ]]; do
    [[ -n "$token" ]] || token=`curl -sX PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600'`
    response=`curl -s -H "X-aws-ec2-metadata-token: ${token}" "http://169.254.169.254/latest/$key"`
    if [[ -n "$response" ]]; then
      echo "$response"
      exit 0
    fi
    attempt=$((attempt+1))
    sleep 1
  done

  error "Failed to fetch ec2 $key"
else
  echo foo
  error "Unknown host type"
fi
