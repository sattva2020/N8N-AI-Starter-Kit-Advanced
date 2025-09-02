#!/bin/bash
# =============================================================================
# N8N AI STARTER KIT - ПРОСТОЙ ТЕСТ ПРОФИЛЕЙ
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1" >&2; }
print_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
print_error() { echo -e "${RED}✗${NC} $1" >&2; }
print_header() { echo -e "${CYAN}=== $1 ===${NC}" >&2; }

# Тест одного профиля
test_profile() {
    local profile="$1"
    local verbose="${2:-false}"
    
    print_info "Тестирование профиля: $profile"
    
    # Проверка конфигурации Docker Compose
    if ! COMPOSE_PROFILES="$profile" docker compose config >/dev/null 2>&1; then
        print_error "Невалидная конфигурация профиля: $profile"
        return 1
    fi
    
    print_success "Конфигурация валидна"
    
    # Подсчет сервисов
    local service_count
    service_count=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null | wc -l)
    print_info "Количество сервисов в профиле: $service_count"
    
    if [[ "$verbose" == "true" ]]; then
        print_info "Список сервисов:"
        COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null | sed 's/^/  - /' >&2
    fi
    
    # Проверка специфичных требований профиля
    local services
    services=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null)
    
    # Проверка базовых сервисов для default профилей
    if [[ "$profile" == *"default"* ]]; then
        if echo "$services" | grep -E "(traefik|postgres|n8n)" >/dev/null; then
            print_success "Найдены базовые сервисы в default профиле"
        else
            print_error "Отсутствуют базовые сервисы в default профиле"
            return 1
        fi
    fi
    
    # Проверка сервисов мониторинга
    if [[ "$profile" == *"monitoring"* ]]; then
        if echo "$services" | grep -E "(grafana|prometheus)" >/dev/null; then
            print_success "Найдены сервисы мониторинга"
        else
            print_warning "Не найдены сервисы мониторинга в monitoring профиле"
        fi
    fi
    
    # Проверка сервисов разработки
    if [[ "$profile" == *"developer"* ]]; then
        if echo "$services" | grep -E "(document-processor|lightrag|web-interface)" >/dev/null; then
            print_success "Найдены сервисы разработки"
        else
            print_warning "Не найдены сервисы разработки в developer профиле"
        fi
    fi
    
    # Проверка GPU сервисов
    if [[ "$profile" == *"gpu"* ]]; then
        if echo "$services" | grep -q "gpu"; then
            print_success "Найдены GPU сервисы"
        else
            print_warning "Не найдены GPU сервисы в gpu профиле"
        fi
    fi
    
    print_success "Тест профиля прошел: $profile"
    return 0
}

# Основная функция
main() {
    cd "$PROJECT_ROOT"
    
    print_header "Тестирование профилей N8N AI Starter Kit"
    
    # Проверка Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker недоступен"
        exit 1
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose недоступен"
        exit 1
    fi
    
    # Определение профилей для тестирования
    local profiles_to_test=(
        "default"
        "default,developer"
        "default,monitoring"
        "default,developer,monitoring"
    )
    
    local verbose="false"
    if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
        verbose="true"
    fi
    
    print_info "Тестирование ${#profiles_to_test[@]} профилей..."
    echo >&2
    
    local passed=0
    local failed=0
    
    # Тестирование каждого профиля
    for profile in "${profiles_to_test[@]}"; do
        if test_profile "$profile" "$verbose"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    # Итоги
    print_header "Результаты тестирования"
    print_info "Всего профилей протестировано: $((passed + failed))"
    print_success "Прошли тест: $passed"
    
    if [[ $failed -gt 0 ]]; then
        print_error "Не прошли тест: $failed"
        exit 1
    else
        print_success "Все тесты пройдены успешно!"
    fi
}

# Запуск основной функции
main "$@"