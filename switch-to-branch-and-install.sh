#!/bin/bash

# Имя скрипта: switch-to-branch-and-install.sh
# Назначение скрипта: Скрипт переключения на ветку и компиляции проекта для проектов: maven, sbt, angular.
# Автор: Пашинский Михаил
# Дата: 10-01-2023
#
# Скрипт проходит циклом по заданному списку директорий и выполняет следующие действия:
#  - если заданной ветки не существует, то переходи в следующую директорию
#  - переключается на заданную ветку
#  - пуллит заданную ветку
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

# Display usage
function display_usage() {

  echo "Скрипт переключения на ветку и компиляции проекта для проектов: maven, sbt, angular."
  echo "Скрипт может быть запущен из любой директории, если заданы абсолютные пути."
  echo -e "\nИспользование: $0 [имя_ветки] \n"
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

# Check whether user had supplied -h or --help. If yes display usage
if [[ ($* == "--help") ||  ($* == "-h") ]]
then
  display_usage
  exit 0
fi

# If less than two arguments supplied, display usage
if [  $# -le 0 ]
then
  display_usage
  exit 1
fi

echo "Branch to checkout: $1";
branchName=$1

for dir in "${dirs[@]}"
do
  cd "$dir" || exit 1
  git fetch --all
  git show-branch remotes/origin/"$branchName" &> /dev/null
  if [ $? -eq 0 ]; then

    echo "Checking out for" "$dir"
    git checkout "$branchName"
    git pull

    # call the project identification function and store result in variable
    projectType=$(identify_project_type)

    echo "Project Type: ${!projectType}"

    case $projectType in

      MAVEN_PROJECT)
        mvn install
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
  fi
done
