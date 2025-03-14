#!/bin/bash

# Имя скрипта: merge-branch-and-fix-version.sh
# Назначение скрипта: Скрипт слития задачной ветки в dev ветку и создания фиксирующего версию коммита для проектов
# maven, sbt, angular.
# Автор: Пашинский Михаил
# Дата: 14-02-2024
#
# Скрипт выполняет следующие действия:
#  - переключается на ветку dev
#  - проверяет обновления в удалённой ветке и обновляет локальную ветку
#  - сливает задачную ветку в dev
#  - просит разрешить конфликты, если они есть.
#  - определяет тип проекта
#  - устанавливает версию проекта в соответствии с типом проекта, инкрементируя номер версии проекта в ветке dev.
#  Внимание! Версия проекта после слития должна содержать ключ задачи.
#  - инкрементирует версию и делает фиксирующий коммит с новой версией
#  - добавляет тег с новой версией
#  - пушит изменения в удалённый репозиторий после подтверждения пользователем операции

#
# Валидации:
#  - Проверяет, что текущая ветка не содержит незакоммиченных изменений и ветка актуальна (состояние совпадает с
#    удалённой веткой)
#
# Параметры:
#  - branchName - Имя ветки, которая будет слита в dev

# Constants for project types
readonly MAVEN_PROJECT="Maven"
readonly SBT_PROJECT="SBT"
readonly ANGULAR_PROJECT="Angular"
readonly UNRECOGNIZED_PROJECT="Unrecognized"

main() {

  # Check whether user had supplied -h or --help. If yes display usage
  if [[ ($* == "--help") ||  ($* == "-h") ]]
  then
    display_usage
    exit 0
  fi

  # If less than one argument supplied, display usage
  if [  $# -ne 2 ]
  then
    display_usage
    exit 1
  fi

  releaseBranchName=$1
  branchName=$2

  validate_args
  echo "Имя релизной ветки: $releaseBranchName"
  echo "Имя ветки для слития: $branchName"

  # Fetch all branches
  git fetch

  check_branch_for_uncommitted_or_local_commits

  git checkout "$branchName"
  git pull

  git checkout "$releaseBranchName"
  # Pull changes
  git pull

  merge_branch

  # call the project identification function and store result in variable
  projectType=$(identify_project_type)

  echo "Project Type: ${!projectType}"

  case $projectType in

    MAVEN_PROJECT)
      newVersion=$(set_maven_project_version | tail -n 1)
      ;;

    SBT_PROJECT)
      newVersion=$(set_sbt_project_version | tail -n 1)
      ;;

    ANGULAR_PROJECT)
      newVersion=$(set_angular_project_version | tail -n 1)
      ;;

    *)
      echo "Error: Unsupported project type"
      exit 1
      ;;
  esac

  make_fix_version_commit "$newVersion"

  exit 0
}

function merge_branch() {

  git merge $branchName --no-ff --no-commit

  # Проверять на наличие конфликтов пока они не будут исправлены пользователем, ожидать исправления ожиданием ввода
  while git status | grep -q 'Unmerged paths'; do
    read -n 1 -s -r -p "Есть конфликты в результате слития! Разреши конфликты и нажми любую клавишу для продолжения. Для отмены нажми Ctrl+C"
  done

  read -n 1 -s -r -p "Проверь версию после слития. Для отмены нажми Ctrl+C"
  # Нужно добавить проверку версии, если она без Strl - добавить туда ключ задачт

  git commit -m "Merge branch $branchName into $releaseBranchName"
}

# Display usage
function display_usage() {

  echo "Скрипт слития задачной ветки в релизную ветку и создания фиксирующего версию коммита для проектов maven, sbt, angular."
  echo "Скрипт должен быть запущен из директории проекта, для которого производится слитие,"
  echo "и проект должен быть на релизной ветке."
  echo -e "\nИспользование: $0 [имя_релизной_ветки] $1 [имя_сливаемой_ветки]\n"
}

# Make first commit
function make_fix_version_commit() {

    # Get the new version from first argument
    newVersion=$1
    echo "Новая версия: $1"

    git commit -m "$newVersion"

    # Add tag with new version
    git tag -a "$newVersion" -m "$newVersion"

    # Ask press any key to push changes to remote repository
    read -n 1 -s -r -p "Нажми любую клавишу для пуша изменений в удалённый репозиторий. Для отмены нажми Ctrl+C"

    # Push changes to remote repository with tags
    git push
    git push --tags

    echo "Making fix version commit"
}

# Возвращает инкрементированную версию из заданной строки
function getIncrementedVersion() {

    input_string=$1

    # Если строка пустая, то возвращаем пустую строку
    if [ -z "$input_string" ]; then
        return 0
    fi

    # Удаление подстроки между последней точкой и концом строки
    modified_string="${input_string%.*}"

    # Получение числа после последней точки
    last_number="${modified_string##*.}"

    # Увеличение числа на 1
    new_number=$((last_number + 1))

    # Замена числа в строке
    final_string="${modified_string%.*}.$new_number"

    echo "$final_string"
}

# Arguments check
function validate_args() {

    # Check that branch name parameter is set
    if [ -z "$branchName" ]; then
      echo "Error: No branch name specified."
      exit 1
    fi
}

# Check branch for uncommitted changes or local commits
function check_branch_for_uncommitted_or_local_commits() {

    if git status | grep -q 'Changes to be committed'; then
      echo "Error: You have uncommitted changes. Merge cannot be done."
      exit 1
    fi

    if git status | grep -q 'Your branch is ahead of'; then
      echo "Error: You have local commits. Merge cannot be done."
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

# Set the project version for Maven project, create new branch and add changes to commit.
function set_maven_project_version() {

    # Get current version
    currentVersion=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | grep -v '\[')

    # Increment version
    newVersion=$(getIncrementedVersion "$currentVersion")

    # Set new version
    mvn versions:set -DnewVersion="$newVersion"
    mvn versions:commit

    # Add changes to commit
    git add pom.xml

    #echo "Setting version for Maven project"
    echo "$newVersion"
}

# Set the project version for SBT project, create new branch and add changes to commit.
function set_sbt_project_version() {

    # Get version from sbt
    currentVersion=$(grep "version :=" build.sbt | cut -d '"' -f2)

    # Increment version
    newVersion=$(getIncrementedVersion "$currentVersion")

    # Set sbt project version
    sed -i "s/version := .*/version := \"$newVersion\"/" build.sbt

    # Add changes to commit
    git add build.sbt

    #echo "Setting version for SBT project"
    echo "$newVersion"
}

# Set the project version for Angular project, create new branch and add changes to commit.
function set_angular_project_version() {

    # Get version from ui project
    currentVersion=$(grep "version: string =" src/environments/version.ts | cut -d '"' -f2)

    # Increment version
    newVersion=$(getIncrementedVersion "$currentVersion")

    # Set version to ui project
    sed -i "s/version: string = .*/version: string = \"$newVersion\";/" src/environments/version.ts

    # Add changes to commit
    git add src/environments/version.ts

    #echo "Setting version for Angular project"
    echo "$newVersion"
}

main "$@";
