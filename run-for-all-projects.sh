#!/bin/bash

# Имя скрипта: run-for-all-projects.sh
# Назначение: Запускает create-new-branch-and-first-commit.sh для выбранных директорий
# Автор: Пашинский Михаил

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH_SCRIPT="$SCRIPT_DIR/create-new-branch-and-first-commit.sh"
PROJECTS_DIR="/Users/mpashinskiy/Projects/Candidate"

# ─── Цвета ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Проверка наличия основного скрипта ───────────────────────────────────────
if [ ! -f "$BRANCH_SCRIPT" ]; then
    echo -e "${RED}Ошибка: скрипт не найден: $BRANCH_SCRIPT${RESET}"
    exit 1
fi

# ─── Сбор директорий ──────────────────────────────────────────────────────────
ALL_DIRS=()
while IFS= read -r -d $'\0' dir; do
    ALL_DIRS+=("$dir")
done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [ ${#ALL_DIRS[@]} -eq 0 ]; then
    echo -e "${RED}Ошибка: директории не найдены в $PROJECTS_DIR${RESET}"
    exit 1
fi

# ─── Интерактивное меню с галочками ───────────────────────────────────────────
# selected[i]=1 — выбрана, 0 — нет
declare -a selected
for i in "${!ALL_DIRS[@]}"; do
    selected[$i]=0
done

cursor=0

function draw_menu() {
    clear
    echo -e "${BOLD}${CYAN}Выберите директории для создания ветки${RESET}"
    echo -e "${YELLOW}Управление: ↑/↓ — навигация, Пробел — выбор/снятие, A — выбрать все, N — снять все, Enter — подтвердить, Q — выход${RESET}"
    echo ""
    for i in "${!ALL_DIRS[@]}"; do
        local dir_name
        dir_name=$(basename "${ALL_DIRS[$i]}")
        local checkbox
        if [ "${selected[$i]}" -eq 1 ]; then
            checkbox="${GREEN}[✓]${RESET}"
        else
            checkbox="[ ]"
        fi
        if [ "$i" -eq "$cursor" ]; then
            echo -e "  ${BOLD}${CYAN}▶ ${checkbox} ${dir_name}${RESET}"
        else
            echo -e "    ${checkbox} ${dir_name}"
        fi
    done
    echo ""

    local count=0
    for i in "${!selected[@]}"; do
        [ "${selected[$i]}" -eq 1 ] && ((count++))
    done
    echo -e "${YELLOW}Выбрано: ${count} из ${#ALL_DIRS[@]}${RESET}"
}

# Читаем нажатие клавиши в глобальную переменную KEY.
# Используем read -rs (silent + raw), без stty — надёжнее на macOS bash 3.2.
# Стрелки посылают 3 байта: ESC, затем [ или O, затем A/B.
KEY=""
function read_key() {
    KEY=""
    local c1="" c2="" c3=""
    IFS= read -rs -n1 c1
    KEY="$c1"
    if [[ "$c1" == $'\x1b' ]]; then
        IFS= read -rs -n1 -t 1 c2
        if [[ -n "$c2" ]]; then
            KEY="${KEY}${c2}"
            IFS= read -rs -n1 -t 1 c3
            if [[ -n "$c3" ]]; then
                KEY="${KEY}${c3}"
            fi
        fi
    fi
}

# Основной цикл меню
while true; do
    draw_menu
    read_key

    case "$KEY" in
        $'\x1b[A'|$'\x1bOA'|'k')  # Стрелка вверх (VT100 и application mode)
            (( cursor > 0 )) && ((cursor--))
            ;;
        $'\x1b[B'|$'\x1bOB'|'j')  # Стрелка вниз
            (( cursor < ${#ALL_DIRS[@]} - 1 )) && ((cursor++))
            ;;
        ' ')             # Пробел — переключить выбор
            if [ "${selected[$cursor]}" -eq 1 ]; then
                selected[$cursor]=0
            else
                selected[$cursor]=1
            fi
            ;;
        'a'|'A')         # Выбрать все
            for i in "${!ALL_DIRS[@]}"; do selected[$i]=1; done
            ;;
        'n'|'N')         # Снять все
            for i in "${!ALL_DIRS[@]}"; do selected[$i]=0; done
            ;;
        $'\n'|$'\r'|'')  # Enter — подтвердить
            break
            ;;
        'q'|'Q')         # Выход
            echo -e "\n${YELLOW}Отменено.${RESET}"
            exit 0
            ;;
    esac
done

clear

# ─── Формируем список выбранных директорий ────────────────────────────────────
declare -a CHOSEN_DIRS
for i in "${!ALL_DIRS[@]}"; do
    [ "${selected[$i]}" -eq 1 ] && CHOSEN_DIRS+=("${ALL_DIRS[$i]}")
done

if [ ${#CHOSEN_DIRS[@]} -eq 0 ]; then
    echo -e "${YELLOW}Ни одна директория не выбрана. Выход.${RESET}"
    exit 0
fi

echo -e "${BOLD}Выбранные директории:${RESET}"
for d in "${CHOSEN_DIRS[@]}"; do
    echo -e "  ${GREEN}✓${RESET} $(basename "$d")"
done
echo ""

# ─── Запрос параметров ────────────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Введите имя ветки:${RESET} ")" branchName
if [ -z "$branchName" ]; then
    echo -e "${RED}Ошибка: имя ветки не может быть пустым.${RESET}"
    exit 1
fi

read -rp "$(echo -e "${BOLD}Введите название задачи:${RESET} ")" taskName
if [ -z "$taskName" ]; then
    echo -e "${RED}Ошибка: название задачи не может быть пустым.${RESET}"
    exit 1
fi

read -rp "$(echo -e "${BOLD}Введите ветку-цель для пулл-реквеста (оставьте пустым для автоопределения release/):${RESET} ")" prTargetBranch

read -rp "$(echo -e "${BOLD}Хотфикс? Введите -hf для создания PR в мастер, или оставьте пустым:${RESET} ")" hotfixKey

echo ""
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Ветка:        ${GREEN}$branchName${RESET}"
echo -e "${BOLD}  Задача:       ${GREEN}$taskName${RESET}"
echo -e "${BOLD}  PR в ветку:   ${GREEN}${prTargetBranch:-"авто (max release/)"}${RESET}"
echo -e "${BOLD}  Хотфикс:      ${GREEN}${hotfixKey:-"нет"}${RESET}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${RESET}"
echo ""
read -rp "$(echo -e "${BOLD}Запустить скрипт для ${#CHOSEN_DIRS[@]} директорий? [y/N]:${RESET} ")" confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${YELLOW}Отменено.${RESET}"
    exit 0
fi

# ─── Запуск скрипта для каждой выбранной директории ───────────────────────────
FAILED_DIRS=()
SUCCESS_DIRS=()

for dir in "${CHOSEN_DIRS[@]}"; do
    dir_name=$(basename "$dir")
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Проект: ${YELLOW}$dir_name${RESET}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════${RESET}"

    (
        cd "$dir" || exit 1
        args=("$branchName" "$taskName")
        [ -n "$prTargetBranch" ] && args+=("$prTargetBranch")
        [ -n "$hotfixKey" ] && args+=("$hotfixKey")
        bash "$BRANCH_SCRIPT" "${args[@]}"
    )

    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        SUCCESS_DIRS+=("$dir_name")
        echo -e "${GREEN}✓ $dir_name — успешно${RESET}"
    else
        FAILED_DIRS+=("$dir_name")
        echo -e "${RED}✗ $dir_name — ошибка (код: $exit_code)${RESET}"
        read -rp "$(echo -e "${YELLOW}Продолжить со следующим проектом? [y/N]:${RESET} ")" cont
        if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
            echo -e "${YELLOW}Остановлено пользователем.${RESET}"
            break
        fi
    fi
done

# ─── Итоговый отчёт ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}═══════════════ ИТОГ ═══════════════${RESET}"
if [ ${#SUCCESS_DIRS[@]} -gt 0 ]; then
    echo -e "${GREEN}Успешно (${#SUCCESS_DIRS[@]}):${RESET}"
    for d in "${SUCCESS_DIRS[@]}"; do echo -e "  ${GREEN}✓ $d${RESET}"; done
fi
if [ ${#FAILED_DIRS[@]} -gt 0 ]; then
    echo -e "${RED}С ошибками (${#FAILED_DIRS[@]}):${RESET}"
    for d in "${FAILED_DIRS[@]}"; do echo -e "  ${RED}✗ $d${RESET}"; done
fi
echo -e "${BOLD}${CYAN}════════════════════════════════════${RESET}"

exit 0

