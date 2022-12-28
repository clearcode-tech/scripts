#!/bin/bash

echo "Branch to create: $1";
branchName=$1
taskName=$2

git fetch --all

resVar=$(mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | grep -v '\[') &> /dev/null
if [[ ${resVar} != *"-SNAPSHOT"* ]]; then
  git pull
  git checkout -b "$branchName"
  mvn versions:set -DnewVersion="$resVar"."$branchName"'-SNAPSHOT'
  mvn versions:commit
  git add pom.xml
  git commit -m "$branchName"" Версия задачи"$'\n'$'\n'"$taskName".
fi
