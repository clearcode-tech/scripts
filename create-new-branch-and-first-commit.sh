#!/bin/bash

# Имя скрипта: create-new-branch-and-first-commit.sh
# Назначение скрипта: Скрипт создания задачной ветки и начального коммита для проектов maven, sbt, angular.
# Автор: Пашинский Михаил
# Дата: 10-01-2023
#
# Скрипт выполняет следующие действия:
#  - обновляет ветку
#  - проверяет, что репозиторий находится не на задачной ветке по значению версии maven-проекта
#  - создаёт новую ветку
#  - определяет тип проекта
#  - устанавливает версию проекта в соответствии с типом проекта
#  - делает первый коммит к задаче
#  - создаёт пулл-реквесты в ветку dev, и если задан ключ -hf | --hotfix, то и в мастер
#
# Валидации:
#  - Проверяет, что параметры заданы
#  - Проверяет, что текущая ветка не содержит незакоммиченных изменений и ветка актуальна (состояние совпадает с
#    удалённой веткой)
#
# Параметры:
#  - branchName - Имя ветки, которая будет создана
#  - taskName - Название задачи, которое будет добавлено в первый комментарий
#  - key:  - Ключ запуска скрипта:
#               -hf | --hotfix если задача выпускается как хотфикс и нужен дополнительный пулл-реквест в мастер-ветку

# Constants for project types
readonly MAVEN_PROJECT="Maven"
readonly SBT_PROJECT="SBT"
readonly ANGULAR_PROJECT="Angular"
readonly UNRECOGNIZED_PROJECT="Unrecognized"

# Arguments check
function validate_args() {

    # Check that branch name parameter is set
    if [ -z "$branchName" ]; then
      echo "Error: No branch name specified."
      exit 1
    fi

    # Check that task name parameter is set
    if [ -z "$taskName" ]; then
      echo "Error: No task name specified."
      exit 1
    fi
}

# Check branch for uncommitted changes or local commits
function check_branch_for_uncommitted_or_local_commits() {

    if git status | grep -q 'Changes to be committed'; then
      echo "Error: You have uncommitted changes. New branch cannot be created."
      exit 1
    fi

    if git status | grep -q 'Your branch is ahead of'; then
      echo "Error: You have local commits. New branch cannot be created."
      exit 1
    fi
}

# Check branch is up to date
function check_branch_is_up_to_date() {

    if ! git status | grep -q 'Your branch is up to date'; then
      echo "Error: Your local branch state is not up to date with origin. New branch cannot be created."
      exit 1
    fi
}

# Identify the project type
function identify_project_type() {

    if [ -f "pom.xml" ]; then
        echo MAVEN_PROJECT
    elif [ -f "build.sbt" ]; then
        echo SBT_PROJECT
    elif [ -f "src/environments/version.ts" ]; then
        echo ANGULAR_PROJECT
    else
        echo UNRECOGNIZED_PROJECT
    fi
}

# Create new branch
function create_new_branch() {

    git checkout -b "$branchName"

    echo "Creating new branch "$branchName
}

# Check current branch is not feature branch by project version
function check_for_feature_branch() {

    # If current version contains -SNAPSHOT or HRL- or STRL- then it is feature branch
    if [[ $1 == *"-SNAPSHOT"* || $1 == *"HRL-"* || $1 == *"STRL-"* ]]; then

      read -p "Ты создаёшь ветку от задачной ветки. Продолжить? Для отмены нажми Ctrl+C"
      return 1
    fi
    # If current version does not contain -SNAPSHOT or HRL- or STRL- then it is not feature branch
    return 0
}

# Set the project version for Maven project, create new branch and add changes to commit.
function set_maven_project_version() {

    # Get current version
    currentVersion=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | grep -v '\[')
    check_for_feature_branch "$currentVersion"
    # if function check_for_feature_branch returned 1, then exclude from version STRL-111-SNAPSHOT or STRL-111-SNAPSHOT or HRL-111 or STRL-2222
    if [[ $? -eq 1 ]]; then
      currentVersion=$(echo "$currentVersion" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    fi

    create_new_branch

    # Set new version
    mvn versions:set -DnewVersion="$currentVersion"."$branchName"'-SNAPSHOT'
    mvn versions:commit

    # Add changes to commit
    git add pom.xml

    echo "Setting version for Maven project"
}

# Set the project version for SBT project, create new branch and add changes to commit.
function set_sbt_project_version() {

    # Get version from sbt
    currentVersion=$(grep "version :=" build.sbt | cut -d '"' -f2)
    check_for_feature_branch "$currentVersion"
    if [[ $? -eq 1 ]]; then
      currentVersion=$(echo "$currentVersion" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    fi

    create_new_branch

    # Set sbt project version
    sed -i "s/version := .*/version := \"$currentVersion.$branchName\"/" build.sbt

    # Add changes to commit
    git add build.sbt

    echo "Setting version for SBT project"
}

# Set the project version for Angular project, create new branch and add changes to commit.
function set_angular_project_version() {

    # Get version from ui project
    currentVersion=$(grep "version: string =" src/environments/version.ts | cut -d '"' -f2)
    check_for_feature_branch "$currentVersion"
    if [[ $? -eq 1 ]]; then
      currentVersion=$(echo "$currentVersion" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    fi

    create_new_branch

    # Set version to ui project
    sed -i "s/version: string = .*/version: string = \"$currentVersion.$branchName\";/" src/environments/version.ts

    # Add changes to commit
    git add src/environments/version.ts

    echo "Setting version for Angular project"
}

# Make first commit
function make_first_commit() {

    read -p "Создание первого коммита. Ветка: $branchName, имя задачи: $taskName. Для создания коммита нажми любую клавишу. Для завершения работы нажми Ctrl+C"

    git commit -m "$branchName"" Версия задачи"$'\n'$'\n'"$taskName".
}

# Create pull requests
function create_pull_requests() {

    create_pull_request_to_dev
    if [[ $key == "-hf" || $key == "--hotfix" ]]; then

      #сделать пустой коммит для создания пулл-реквеста в мастер
      git commit --allow-empty -m "$branchName"" ""$taskName"$'\n'$'\n'"Пустой коммит для создания пулл-реквеста в мастер-ветку".

      create_pull_request_to_master
    fi
}

# Create pull request to dev
function create_pull_request_to_dev() {

    echo "Создание пулл-реквеста в ветку $pull_request_target_branch"
    git push -o mr.create -o mr.target="$pull_request_target_branch" -o mr.title="$branchName"" ""$taskName" -o mr.description="$taskName""." origin "$branchName"
}

# Create pull request to master
function create_pull_request_to_master() {

    echo "Создание пулл-реквеста в ветку master"
    git push -o mr.create -o mr.target=master -o mr.title="$branchName"" ""$taskName" -o mr.description="$taskName""." origin "$branchName"
}

function display_usage() {

  echo "Скрипт создания задачной ветки и начального коммита для проектов: maven, sbt, angular."
  echo "Скрипт должен быть запущен из директории проекта, для которого создаётся ветка,"
  echo "и проект должен быть не на задачной ветке, а на ветке dev или master."
  echo -e "\nИспользование: $0 [имя_создаваемой_ветки] [название_задачи_без_точки_в_кавычках] [ветка_релиза] \n"
}

# Check whether user had supplied -h or --help. If yes display usage
if [[ ($* == "--help") ||  ($* == "-h") ]]
then
  display_usage
  exit 0
fi

# If less than two arguments supplied, display usage
if [  $# -le 2 ]
then
  display_usage
  exit 1
fi

branchName=$1
taskName=$2
pull_request_target_branch=$3
key=$4

validate_args

echo "Branch name: $branchName"
echo "Task name: $taskName"
echo "Pull request target branch: $pull_request_target_branch"

# Fetch all branches
git fetch --all

check_branch_for_uncommitted_or_local_commits

# Pull changes
git pull

check_branch_is_up_to_date

# call the project identification function and store result in variable
projectType=$(identify_project_type)

echo "Project Type: ${!projectType}"

case $projectType in

  MAVEN_PROJECT)
    set_maven_project_version
    ;;

  SBT_PROJECT)
    set_sbt_project_version
    ;;

  ANGULAR_PROJECT)
    set_angular_project_version
    ;;

  *)
    echo "Error: Unsupported project type"
    exit 1
    ;;
esac

make_first_commit

#Запросить нажатие клавиши для создания пулл-реквестов
read -p "Для создания пулл-реквестов нажми любую клавишу. Для завершения работы нажми Ctrl+C"
create_pull_requests

exit 0
