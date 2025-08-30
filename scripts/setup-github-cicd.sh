#!/bin/bash
# =============================================================================
# СКРИПТ ДЛЯ НАСТРОЙКИ GITHUB REPOSITORY И ОТПРАВКИ CI/CD КОДА
# =============================================================================

echo "🚀 Настройка GitHub repository для тестирования CI/CD конвейера..."

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() { echo -e "${BLUE}📋 $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }

# Проверяем, что пользователь создал репозиторий
print_step "Убедитесь, что вы создали GitHub репозиторий 'N8N-AI-Starter-Kit-Advanced'"
print_warning "Если вы еще не создали репозиторий, перейдите на https://github.com/new"

# Получаем имя пользователя GitHub
read -p "Введите ваше имя пользователя GitHub: " GITHUB_USERNAME

if [[ -z "$GITHUB_USERNAME" ]]; then
    echo "❌ Имя пользователя не может быть пустым"
    exit 1
fi

REPO_URL="https://github.com/$GITHUB_USERNAME/N8N-AI-Starter-Kit-Advanced.git"

print_step "Настройка remote origin..."
git remote add origin "$REPO_URL"

print_step "Проверка remote настроек..."
git remote -v

print_step "Отправка кода в GitHub..."
git push -u origin main

print_success "✨ Код успешно отправлен в GitHub!"

echo ""
print_step "🎯 Следующие шаги для тестирования CI/CD:"
echo "1. Перейдите в ваш репозиторий: https://github.com/$GITHUB_USERNAME/N8N-AI-Starter-Kit-Advanced"
echo "2. Откройте вкладку 'Actions' для просмотра запущенных workflow"
echo "3. Проверьте результаты тестирования в секции 'Comprehensive Testing Pipeline'"
echo ""

print_warning "Примечание: GitHub Actions может потребовать несколько минут для первого запуска"

echo ""
print_step "📊 Мониторинг CI/CD процесса:"
echo "• Profile Validation - проверка конфигураций профилей"
echo "• Unit Tests - модульные тесты Python сервисов"
echo "• Integration Tests - интеграционные тесты с запуском сервисов"
echo "• Startup Tests - тестирование запуска различных профилей"
echo "• Security Tests - проверки безопасности"
echo ""

print_success "🎉 CI/CD конвейер готов к тестированию!"