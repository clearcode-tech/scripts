#!/bin/bash

# Имя скрипта: create-release-branch.sh
# Назначение скрипта: Скрипт создания релизной ветки для проектов maven, sbt, angular.
# Автор: Пашинский Михаил
# Дата: 06-05-2026
#
# Скрипт выполняет следующие действия:
#  - находит максимальную ветку, содержащую слово "release", в удалённом репозитории
#  - извлекает MAJOR-версию из найденной ветки
#  - формирует имя новой ветки: {releaseBranchPrefix}/{MAJOR}.{releaseMinor}
#  - проверяет, что такая ветка ещё не существует в remote
#  - переключается на базовую ветку и обновляет её
#  - создаёт новую релизную ветку
#  - определяет тип проекта (Maven / SBT / Angular)
#  - устанавливает версию {MAJOR}.{releaseMinor}.0 в файл проекта
#  - делает коммит с сообщением, содержащим только версию приложения
#  - добавляет тег с версией приложения
#  - просит пользователя проверить корректность
#  - пушит ветку и тег в удалённый репозиторий
#
# Валидации:
#  - Проверяет, что параметры заданы
#  - Проверяет, что releaseMinor — целое число
#  - Проверяет, что ветка с таким именем ещё не существует в remote
#  - Проверяет, что текущая ветка не содержит незакоммиченных изменений
#  - Проверяет, что локальная ветка актуальна (состояние совпадает с удалённой веткой)
#
# Параметры:
#  - releaseMinor        - MINOR-номер нового релиза (например: 5)
#  - releaseBranchPrefix - Префикс имени релизной ветки (например: release или v2_release)
#
# Пример:
#  ./create-release-branch.sh 5 release
#  ./create-release-branch.sh 3 v2_release

# Constants for project types
readonly MAVEN_PROJECT="Maven"
readonly SBT_PROJECT="SBT"
readonly ANGULAR_PROJECT="Angular"
readonly UNRECOGNIZED_PROJECT="Unrecognized"

# Cross-platform sed -i (macOS requires empty string argument, Linux does not)
function sed_inplace() {
    local expression="$1"
    local file="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i "" "$expression" "$file"
    else
        sed -i "$expression" "$file"
    fi
}

# Display usage
function display_usage() {
    echo "Скрипт создания релизной ветки для проектов: maven, sbt, angular."
    echo "Скрипт должен быть запущен из директории проекта."
    echo -e "\nИспользование: $0 [minor_номер_релиза] [префикс_ветки_релиза]\n"
    echo "Примеры:"
    echo "  $0 5 release"
    echo "  $0 3 v2_release"
}

# Arguments check
function validate_args() {

    if [ -z "$releaseMinor" ]; then
        echo "Error: Не указан MINOR-номер релиза."
        exit 1
    fi

    if ! [[ "$releaseMinor" =~ ^[0-9]+$ ]]; then
        echo "Error: MINOR-номер релиза должен быть целым числом. Получено: '$releaseMinor'."
        exit 1
    fi

    if [ -z "$releaseBranchPrefix" ]; then
        echo "Error: Не указан префикс ветки релиза."
        exit 1
    fi
}

# Check branch for uncommitted changes or local commits
function check_branch_for_uncommitted_or_local_commits() {

    if git status | grep -q 'Changes to be committed'; then
        echo "Error: Есть незакоммиченные изменения. Создание ветки невозможно."
        exit 1
    fi

    if git status | grep -q 'Your branch is ahead of'; then
        echo "Error: Есть локальные коммиты. Создание ветки невозможно."
        exit 1
    fi
}

# Check branch is up to date
function check_branch_is_up_to_date() {

    if ! git status | grep -q 'Your branch is up to date'; then
        echo "Error: Локальная ветка не актуальна. Создание ветки невозможно."
        exit 1
    fi
}

# Find the maximum branch containing word "release" from remote.
# Returns branch name without "origin/" prefix.
function find_max_release_branch() {

    local maxBranch
    maxBranch=$(git branch -r | grep 'release' | sed 's|.*origin/||' | sort -V | tail -1)

    if [ -z "$maxBranch" ]; then
        echo "Error: Не найдено ни одной ветки, содержащей слово 'release', в удалённом репозитории." >&2
        exit 1
    fi

    echo "$maxBranch"
}

# Read the current application version depending on project type.
# Returns clean MAJOR.MINOR.PATCH trimmed of any snapshot/branch suffixes.
function read_current_version() {

    local projectType="$1"

    local rawVersion
    case $projectType in
        MAVEN_PROJECT)
            rawVersion=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | grep -v '\[')
            ;;
        SBT_PROJECT)
            rawVersion=$(grep "version :=" build.sbt | cut -d '"' -f2)
            ;;
        ANGULAR_PROJECT)
            rawVersion=$(grep "version: string =" src/environments/version.ts | cut -d '"' -f2)
            ;;
        *)
            echo "Error: Неподдерживаемый тип проекта — невозможно прочитать версию." >&2
            exit 1
            ;;
    esac

    # Strip any suffix after the third numeric segment (e.g. -SNAPSHOT, .HRL-123)
    local cleanVersion
    cleanVersion=$(echo "$rawVersion" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    if [ -z "$cleanVersion" ]; then
        echo "Error: Не удалось прочитать версию проекта." >&2
        exit 1
    fi

    echo "$cleanVersion"
}

# Extract MAJOR from a version string like "1.4.7"
function extract_major_from_version() {

    local version="$1"
    local major="${version%%.*}"

    if [ -z "$major" ] || ! [[ "$major" =~ ^[0-9]+$ ]]; then
        echo "Error: Не удалось извлечь MAJOR из версии '$version'." >&2
        exit 1
    fi

    echo "$major"
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

# Set version for Maven project and stage the change
function set_maven_project_version() {

    local newVersion="$1"

    mvn versions:set -DnewVersion="$newVersion"
    mvn versions:commit

    git add pom.xml

    echo "Версия Maven-проекта установлена: $newVersion"
}

# Set version for SBT project and stage the change
function set_sbt_project_version() {

    local newVersion="$1"

    sed_inplace "s/version := .*/version := \"$newVersion\"/" build.sbt

    git add build.sbt

    echo "Версия SBT-проекта установлена: $newVersion"
}

# Set version for Angular project and stage the change
function set_angular_project_version() {

    local newVersion="$1"

    sed_inplace "s/version: string = .*/version: string = \"$newVersion\";/" src/environments/version.ts

    git add src/environments/version.ts

    echo "Версия Angular-проекта установлена: $newVersion"
}

# Make release commit and tag, then push after user confirmation
function commit_tag_and_push() {

    local newVersion="$1"
    local newBranchName="$2"

    git commit -m "$newVersion"

    git tag -a "$newVersion" -m "$newVersion"

    echo ""
    echo "============================================"
    echo "  Итог:"
    echo "  Базовая ветка   : $baseReleaseBranch"
    echo "  Новая ветка     : $newBranchName"
    echo "  Версия проекта  : $newVersion"
    echo "  Тег             : $newVersion"
    echo "============================================"
    echo ""

    read -n 1 -s -r -p "Проверь корректность версии и ветки. Для пуша нажми любую клавишу. Для отмены нажми Ctrl+C"
    echo ""

    git push origin "$newBranchName"
    git push --tags

    echo ""
    echo "✓ Ветка '$newBranchName' и тег '$newVersion' успешно запушены."
}

main() {

    # Check whether user had supplied -h or --help. If yes display usage
    if [[ ($* == "--help") || ($* == "-h") ]]; then
        display_usage
        exit 0
    fi

    # If not exactly two arguments supplied, display usage
    if [ $# -ne 2 ]; then
        display_usage
        exit 1
    fi

    releaseMinor=$1
    releaseBranchPrefix=$2

    validate_args

    # Fetch all branches
    git fetch --all

    check_branch_for_uncommitted_or_local_commits

    # Find max release branch
    echo "Поиск максимальной ветки, содержащей слово 'release'..."
    baseReleaseBranch=$(find_max_release_branch)
    echo "Найдена базовая ветка: $baseReleaseBranch"

    # Switch to base release branch and update
    git checkout "$baseReleaseBranch"
    git pull

    check_branch_is_up_to_date

    # Identify project type
    projectType=$(identify_project_type)
    echo "Тип проекта: $projectType"

    # Read MAJOR from the actual project version
    currentVersion=$(read_current_version "$projectType")
    echo "Текущая версия проекта: $currentVersion"

    releaseMajor=$(extract_major_from_version "$currentVersion")
    echo "MAJOR-версия: $releaseMajor"

    # Build new branch name and version
    newBranchName="${releaseBranchPrefix}/${releaseMinor}"
    newVersion="${releaseMajor}.${releaseMinor}.0"

    echo "Имя новой ветки : $newBranchName"
    echo "Новая версия    : $newVersion"

    # Check that new branch does not already exist in remote
    if git branch -r | grep -q "origin/$newBranchName"; then
        echo "Error: Ветка '$newBranchName' уже существует в удалённом репозитории."
        exit 1
    fi

    # Create new release branch
    git checkout -b "$newBranchName"
    echo "Создана ветка '$newBranchName'"


    case $projectType in

        MAVEN_PROJECT)
            set_maven_project_version "$newVersion"
            ;;

        SBT_PROJECT)
            set_sbt_project_version "$newVersion"
            ;;

        ANGULAR_PROJECT)
            set_angular_project_version "$newVersion"
            ;;

        *)
            echo "Error: Неподдерживаемый тип проекта. Ожидается наличие pom.xml, build.sbt или src/environments/version.ts."
            exit 1
            ;;
    esac

    commit_tag_and_push "$newVersion" "$newBranchName"

    exit 0
}

main "$@"

