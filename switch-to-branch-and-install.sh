#!/bin/bash

echo "Branch to checkout: $1";
branchName=$1
dirPrefix="candidate"
dirs=("commons" "api-gateway" "auth" "candidate" "file" "id" "invitation" "notification" "request-logger" "session" "tenant" "websocket")

git fetch --all
for dir in "${dirs[@]}"
do
  cd $(echo $dirPrefix-$dir)
  git show-branch remotes/origin/"$branchName" &> /dev/null
  if [ $? -eq 0 ]; then
    git checkout "$branchName"
    git pull
    mvn install
  fi
  cd ../
done
