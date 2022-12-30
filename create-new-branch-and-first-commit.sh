#!/bin/bash

branchName=$1
taskName=$2

if [ -z "$branchName" ]; then
  echo "No branch name specified."
  exit
fi

if [ -z "$taskName" ]; then
  echo "No task name specified."
  exit
fi

git fetch --all

if git status | grep -q 'Changes to be committed'; then
  echo "You have uncommitted changes. New branch cannot be created."
  exit
fi

if git status | grep -q 'Your branch is ahead of'; then
  echo "You have local commits. New branch cannot be created."
  exit
fi

git pull

if ! git status | grep -q 'Your branch is up to date'; then
  echo "Your local branch state is not up to date with origin. New branch cannot be created."
  exit
fi

resVar=$(mvn org.apache.maven.plugins:maven-help-plugin:2.1.1:evaluate -Dexpression=project.version | grep -v '\[') &> /dev/null
if [[ ${resVar} != *"-SNAPSHOT"* ]]; then
  git checkout -b "$branchName"
  mvn versions:set -DnewVersion="$resVar"."$branchName"'-SNAPSHOT'
  mvn versions:commit
  git add pom.xml
  git commit -m "$branchName"" Версия задачи"$'\n'$'\n'"$taskName".
else
  echo "You are on feature branch. Checkout development branch first."
fi
