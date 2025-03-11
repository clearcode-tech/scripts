#!/bin/bash

# Имя скрипта: switch-to-branch-and-install.sh
# Назначение скрипта: Скрипт переключения на ветку и компиляции проекта для проектов: maven, sbt, angular.
# Автор: Пашинский Михаил
# Дата: 10-01-2023
#
# Скрипт проходит циклом по заданному списку директорий и выполняет следующие действия:
#  - если заданной ветки не существует, то переходит в следующую директорию
#  - если нет локальных коммитов и незакоммиченных изменений - переключается на заданную ветку
#  - если нет локальных коммитов и незакоммиченных изменений - пуллит заданную ветку
#  - собирает проект, если тип проекта maven, sbt.
# Важно! Порядок директорий должен задаваться от менее зависимых к более зависимым.
#
# Валидации:
#  - Проверяет, что параметры заданы
#
# Параметры:
#  - branchName - Имя ветки, на которую будет выполнено переключение

# Directories for project
readonly dirs=(
  "$HOME""/Projects/hr-link/core/app-core"
  "$HOME""/Projects/hr-link/core/spring-backend"
)

# Constants for project types
readonly MAVEN_PROJECT="Maven"
readonly SBT_PROJECT="SBT"
readonly ANGULAR_PROJECT="Angular"
readonly UNRECOGNIZED_PROJECT="Unrecognized"

# Script options
NO_FETCH=false
NO_COMPILE=false
COMPILE_ONLY=false

# Check branch for uncommitted changes or local commits
function check_branch_for_uncommitted_or_local_commits() {

    if git status | grep -q 'Changes to be committed'; then
      echo "Error: You have uncommitted changes"
      exit 1
    fi

    if git status | grep -q 'Your branch is ahead of'; then
      echo "Error: You have local commits"
      exit 1
    fi
}

# Display usage
function display_usage() {

  echo "Скрипт переключения на ветку и компиляции проекта для проектов: maven, sbt, angular."
  echo "Скрипт может быть запущен из любой директории, если заданы абсолютные пути."
  echo -e "\nИспользование: $0 [имя_ветки] [опции] \n"
  echo -e "Опции:"
  echo -e "   -nf | --no-fetch    Не делать git fetch перед переключением на ветку"
  echo -e "   -nc | --no-compile  Не компилировать проект после переключения на ветку"
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

function compileProject() {

  # call the project identification function and store result in variable
  projectType=$(identify_project_type)

  echo "Project Type: ${!projectType}"

  case $projectType in

    MAVEN_PROJECT)
      mvn install -Dspring.profiles.active=dev,dev-custom -f pom.xml
      ;;

    SBT_PROJECT)
      sbt reload clean compile
      ;;

    ANGULAR_PROJECT)
      ;;

    *)
      echo "Error: Unsupported project type"
      exit 1
      ;;
  esac
}

# Parse arguments
function parseArguments() {

  while [[ $# -gt 0 ]]; do
    case $1 in
      -nf|--no-fetch)
        NO_FETCH=true
        shift
        ;;
      -nc|--no-compile)
        NO_COMPILE=true
        shift
        ;;
      -co|--compile-only)
        COMPILE_ONLY=true
        shift
        ;;
      -h|--help)
        display_usage
        exit 0
        ;;
      *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        ;;
    esac
  done
}

parseArguments "$@"
set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# If less than one argument supplied, display usage
if ! $COMPILE_ONLY ; then

  if [  $# -le 0 ]
  then
    display_usage
    exit 1
  fi
fi

echo "Fetching disabled: $NO_FETCH";
echo "Compile disabled: $NO_COMPILE";
echo "Compile only enabled: $COMPILE_ONLY";
echo "Branch to checkout: $1";
branchName=$1

for dir in "${dirs[@]}"
do
  cd "$dir" || exit 1

  if $COMPILE_ONLY ; then

    compileProject
    continue
  fi

  if ! $NO_FETCH ; then

    git fetch --all
  fi

  git show-branch remotes/origin/"$branchName" &> /dev/null
  if [ $? -eq 0 ]; then

    check_branch_for_uncommitted_or_local_commits

    echo "Checking out branch" "$dir"
    git checkout "$branchName"

    check_branch_for_uncommitted_or_local_commits

    git pull

    if ! $NO_COMPILE ; then

      compileProject
    fi

  fi
done
