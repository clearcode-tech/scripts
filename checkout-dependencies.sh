#!/bin/bash

# Массив проектов
readonly project_paths=(
  "$HOME""/Projects/hr-link/candidate/candidate-api-gateway"
  "$HOME""/Projects/hr-link/candidate/candidate-auth"
  "$HOME""/Projects/hr-link/candidate/candidate-candidate"
  "$HOME""/Projects/hr-link/candidate/candidate-file"
  "$HOME""/Projects/hr-link/candidate/candidate-id"
  "$HOME""/Projects/hr-link/candidate/candidate-invitation"
  "$HOME""/Projects/hr-link/candidate/candidate-notification"
  "$HOME""/Projects/hr-link/candidate/candidate-request-logger"
  "$HOME""/Projects/hr-link/candidate/candidate-session"
  "$HOME""/Projects/hr-link/candidate/candidate-tenant"
  "$HOME""/Projects/hr-link/candidate/candidate-websocket"
)

# Ассоциативные массивы для соответствия пакета и пути к локальному репозиторию Git
# Массив путей к репозиториям Git (указывается абсолютный путь)
declare -A package_disk_paths
package_disk_paths["commons"]="$HOME""/Projects/hr-link/candidate/candidate-commons"
package_disk_paths["spring-backend"]="$HOME""/Projects/hr-link/core/spring-backend"
# Добавьте другие пакеты и соответствующие пути к репозиториям Git здесь

# Массив имён версий пакетов в pom.xml
declare -A packages
packages["commons"]="tech.clearcode.candidate.candidate-commons.version"
packages["spring-backend"]="tech.clearcode.core.spring-backend.version"
# Добавьте другие пакеты для pom.xml здесь

# Функция для выполнения git checkout и компиляции для указанного пакета
function process_package {

  local PACKAGE=$1
  local GIT_REPO_PATH=${package_disk_paths[$PACKAGE]}

  # Получить версию из pom.xml для указанного пакета
  local VERSION=$(mvn help:evaluate -Dexpression=${packages[$PACKAGE]} -q -DforceStdout | grep -v '\[')
  if [ -z "$GIT_REPO_PATH" ] || [ -z "$VERSION" ] || [ "$VERSION" == "null object or invalid expression" ]; then

      echo "Пакет '$PACKAGE' не найден в справочнике или не удалось получить версию из pom.xml."
      return
  fi

  # Перейти в директорию локального репозитория Git
  cd $GIT_REPO_PATH

  # Выполнить checkout по указанной версии и пути
  git checkout $VERSION

  # Проверить, прошел ли checkout успешно
  if [ $? -eq 0 ]; then
      # Если checkout прошел успешно, скомпилировать Maven проект
      mvn clean
      mvn install
      if [ $? -eq 0 ]; then
          echo "Проект '$PACKAGE' скомпилирован успешно."
      else
          echo "Ошибка: Не удалось скомпилировать проект '$PACKAGE'."
      fi
  else
      echo "Ошибка: Не удалось выполнить checkout для пакета '$PACKAGE'."
  fi

  process_all_packages
}

# Функция для выполнения сборки всех зависимостей
function process_all_packages {

  # Перебрать все пакеты и выполнить git checkout и компиляцию для каждого из них
  for PACKAGE in "${!packages[@]}"; do

      process_package $PACKAGE
  done
}

for project_path in "${project_paths[@]}"; do

  echo ""
  echo "=================== Получение и сборка зависимостей проекта: ""$project_path""==================="
  echo ""

  cd "$project_path" || exit 1
  process_all_packages

  echo ""
  echo "=================== Сборка проекта: ""$project_path""==================="
  echo ""

  cd "$project_path" || exit 1
  mvn clean
  mvn install

done
