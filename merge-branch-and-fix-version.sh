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
#  - проверяет пулл-реквест в GitLab: целевую ветку, наличие, предлагает исправить или создать
#  - сливает задачную ветку в dev
#  - просит разрешить конфликты, если они есть.
#  - определяет тип проекта
#  - устанавливает версию проекта в соответствии с типом проекта, инкрементируя номер версии проекта в ветке dev.
#  Внимание! Версия проекта после слития должна содержать ключ задачи.
#  - инкрементирует версию и делает фиксирующий коммит с новой версией
#  - добавляет тег с новой версией
#  - пушит изменения в удалённый репозиторий после подтверждения пользователем операции
#
# Зависимости:
#  - glab  (GitLab CLI): brew install glab && glab auth login
#  - jq    (JSON-парсер): brew install jq
#
# Валидации:
#  - Проверяет, что текущая ветка не содержит незакоммиченных изменений и ветка актуальна (состояние совпадает с
#    удалённой веткой)
#
# Параметры:
#  - releaseBranchName - Имя релизной ветки, в которую будет произведено слитие
#  - branchName        - Имя ветки, которая будет слита

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

  # Check required dependencies
  if ! command -v glab &> /dev/null; then
    echo "Error: glab (GitLab CLI) не установлен."
    echo "Установи: brew install glab && glab auth login"
    exit 1
  fi

  if ! command -v jq &> /dev/null; then
    echo "Error: jq не установлен."
    echo "Установи: brew install jq"
    exit 1
  fi

  validate_args
  echo "Имя релизной ветки: $releaseBranchName"
  echo "Имя ветки для слития: $branchName"

  # Fetch all branches
  git fetch

  check_branch_for_uncommitted_or_local_commits

  git checkout "$releaseBranchName"
  # Pull changes
  git pull

  check_and_fix_pull_request

  merge_branch

  # call the project identification function and store result in variable
  projectType=$(identify_project_type)

  echo "Project Type: $projectType"

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

  git fetch origin "$branchName"
  git merge "origin/$branchName" --no-ff --no-commit

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

    # Push changes to remote repository with tags.
    # --set-upstream безопасно инициализирует tracking, если его ещё нет.
    git push --set-upstream origin "$releaseBranchName"
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

    # Check that release branch exists in remote repository
    if ! git rev-parse --verify "origin/$releaseBranchName" &>/dev/null; then
      echo "Error: Ветка '$releaseBranchName' не найдена в удалённом репозитории."
      exit 1
    fi

    # Check that source branch exists in remote repository
    if ! git rev-parse --verify "origin/$branchName" &>/dev/null; then
      echo "Error: Ветка '$branchName' не найдена в удалённом репозитории."
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
# Supports two layouts:
#   1. Standard: <version>1.2.3</version>  → updated via mvn versions:set
#   2. Revision: <version>${revision}</version> with <revision>…</revision> in <properties>
#      → only the <revision> property is updated via sed (mvn versions:set would overwrite ${revision})
function set_maven_project_version() {

    # Detect whether the project uses the ${revision} CI-friendly layout
    local uses_revision
    uses_revision=$(grep -c '<version>\${revision}</version>' pom.xml || true)

    if [ "$uses_revision" -gt 0 ]; then
        # Read current version from the <revision> property
        currentVersion=$(grep -m1 '<revision>' pom.xml | sed 's/.*<revision>\(.*\)<\/revision>.*/\1/' | tr -d '[:space:]')

        # Increment version
        newVersion=$(getIncrementedVersion "$currentVersion")

        # Update only the first <revision> property (inside <properties>).
        # awk is used instead of sed because BSD sed (macOS) does not support the 0,/pattern/ address.
        local tmpfile
        tmpfile=$(mktemp)
        awk -v ver="$newVersion" \
            '!replaced && /<revision>.*<\/revision>/ { sub(/<revision>.*<\/revision>/, "<revision>" ver "</revision>"); replaced=1 } { print }' \
            pom.xml > "$tmpfile" && mv "$tmpfile" pom.xml
    else
        # Standard Maven layout — use the versions plugin
        currentVersion=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout | grep -v '\[')

        newVersion=$(getIncrementedVersion "$currentVersion")

        mvn versions:set -DnewVersion="$newVersion"
        mvn versions:commit
    fi

    # Add changes to commit
    git add pom.xml

    echo "$newVersion"
}

# Set the project version for SBT project, create new branch and add changes to commit.
function set_sbt_project_version() {

    # Get version from sbt
    currentVersion=$(grep "version :=" build.sbt | cut -d '"' -f2)

    # Increment version
    newVersion=$(getIncrementedVersion "$currentVersion")

    # Set sbt project version
    sed_inplace "s/version := .*/version := \"$newVersion\"/" build.sbt

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
    sed_inplace "s/version: string = .*/version: string = \"$newVersion\";/" src/environments/version.ts

    # Add changes to commit
    git add src/environments/version.ts

    #echo "Setting version for Angular project"
    echo "$newVersion"
}

# Check pull request in GitLab before merging.
# Scenarios:
#   1. No open MRs for the branch          → offer to create one
#   2. MR targeting the correct branch     → continue
#   3. Exactly 1 MR with a wrong target    → offer to fix automatically
#   4. Multiple MRs all with wrong targets → show links, ask user to fix manually
function check_and_fix_pull_request() {

  echo ""
  echo "Проверка пулл-реквеста в GitLab для ветки '$branchName'..."

  local mr_json
  mr_json=$(glab mr list --source-branch "$branchName" --output json 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$mr_json" ] || [ "$mr_json" = "null" ] || [ "$mr_json" = "[]" ]; then
    mr_json="[]"
  fi

  local mr_count
  mr_count=$(echo "$mr_json" | jq 'length')

  # Сценарий 1: MR не существует
  if [ "$mr_count" -eq 0 ]; then
    echo "Открытых пулл-реквестов для ветки '$branchName' не найдено."
    read -r -p "Создать MR в ветку '$releaseBranchName'? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "Создание MR: '$branchName' → '$releaseBranchName'..."
      glab mr create \
        --source-branch "$branchName" \
        --target-branch "$releaseBranchName" \
        --title "$branchName" \
        --yes
    fi
    echo ""
    return
  fi

  # Проверяем есть ли MR с нужной целевой веткой
  local correct_count
  correct_count=$(echo "$mr_json" | jq --arg target "$releaseBranchName" '[.[] | select(.target_branch == $target)] | length')

  # Сценарий 2: уже есть MR с правильной целевой веткой
  if [ "$correct_count" -gt 0 ]; then
    local correct_url
    correct_url=$(echo "$mr_json" | jq -r --arg target "$releaseBranchName" '.[] | select(.target_branch == $target) | .web_url' | head -1)
    echo "✓ Пулл-реквест уже направлен в нужную ветку '$releaseBranchName'."
    echo "  Ссылка: $correct_url"
    echo ""
    return
  fi

  # Все MR направлены в другие ветки
  # Сценарий 3: ровно 1 MR с неправильной целевой веткой
  if [ "$mr_count" -eq 1 ]; then
    local mr_iid mr_target mr_url
    mr_iid=$(echo "$mr_json"  | jq -r '.[0].iid')
    mr_target=$(echo "$mr_json" | jq -r '.[0].target_branch')
    mr_url=$(echo "$mr_json"  | jq -r '.[0].web_url')

    echo "Пулл-реквест направлен в ветку '$mr_target', а не в '$releaseBranchName'."
    echo "  Ссылка: $mr_url"
    read -r -p "Изменить целевую ветку на '$releaseBranchName' автоматически? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      echo "Изменение целевой ветки MR !$mr_iid → '$releaseBranchName'..."
      glab mr update "$mr_iid" --target-branch "$releaseBranchName"
      echo "✓ Целевая ветка обновлена."
    fi
    echo ""
    return
  fi

  # Сценарий 4: несколько MR, все с неправильными целевыми ветками
  echo "Найдено несколько открытых пулл-реквестов для ветки '$branchName', ни один не направлен в '$releaseBranchName':"
  echo "$mr_json" | jq -r '.[] | "  MR !\(.iid)  →  \(.target_branch)  \(.web_url)"'
  echo ""
  read -n 1 -s -r -p "Исправь целевые ветки MR вручную и нажми любую клавишу для продолжения. Для отмены нажми Ctrl+C"
  echo ""
}

main "$@";
