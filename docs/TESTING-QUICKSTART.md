# Протокол тестирования N8N AI Starter Kit - Краткая инструкция

## Созданные компоненты

### 1. Основной тестовый скрипт
- **Файл**: `scripts/run-comprehensive-tests.sh`
- **Назначение**: Универсальный скрипт для запуска всех типов тестов
- **Возможности**: unit, integration, e2e, api, performance, security

### 2. Playwright E2E тесты  
- **Директория**: `tests/e2e/`
- **Конфигурация**: `playwright.config.ts`
- **Тесты**: Homepage, API, Workflow integration
- **Браузеры**: Chrome, Firefox

### 3. Тестовые сценарии
- **01-homepage.spec.ts**: Тестирование навигации и UI
- **02-api-tests.spec.ts**: Тестирование всех API endpoints
- **03-workflow-integration.spec.ts**: Интеграционные workflow тесты

## Быстрый старт

```bash
# 1. Настройка окружения
cp template.env .env.test

# 2. Установка Playwright
cd tests/e2e
npm install
npx playwright install
cd ../..

# 3. Запуск всех тестов
chmod +x scripts/run-comprehensive-tests.sh
./scripts/run-comprehensive-tests.sh

# 4. Запуск отдельных наборов
./scripts/run-comprehensive-tests.sh e2e --verbose
./scripts/run-comprehensive-tests.sh unit integration
./scripts/run-comprehensive-tests.sh api security
```

## Структура отчетов

```
test-results/
├── test-summary.html          # Общий отчет
├── e2e/playwright-report/     # Playwright HTML отчет  
├── results.json              # JSON результаты
└── performance-results.json   # Performance метрики
```

## Ключевые особенности

### Интеграция с существующей системой
- Использует существующие unit и integration тесты
- Расширяет функциональность E2E тестированием
- Совместим с текущей архитектурой проекта

### Playwright преимущества
- Кроссбраузерное тестирование
- Автоматические скриншоты при ошибках
- Возможность записи тестов
- Встроенная поддержка API тестирования

### Автоматизация
- Автоматическое развертывание тестовой среды
- Ожидание готовности сервисов
- Генерация комплексных отчетов
- Очистка окружения после тестов

## Troubleshooting

```bash
# Проверка статуса сервисов
docker compose ps
./scripts/maintenance/monitor.sh health

# Debug Playwright тестов
cd tests/e2e
npx playwright test --debug
npx playwright test --headed

# Просмотр отчетов
npx playwright show-report
```

## Рекомендации по использованию

### Для разработчиков
- Запускайте `./scripts/run-comprehensive-tests.sh unit` перед commit
- Используйте `e2e --verbose` для отладки UI проблем
- Проверяйте API тесты при изменении endpoints

### Для CI/CD
- Запускайте полный набор тестов: `./scripts/run-comprehensive-tests.sh --cleanup`
- Сохраняйте отчеты как артефакты
- Используйте тайм-ауты для долгих тестов

### Для QA
- Используйте `--verbose` для детального логирования
- Запускайте performance тесты регулярно  
- Мониторьте security audit результаты

---

Данный протокол расширяет существующую тестовую инфраструктуру проекта современными возможностями E2E тестирования с Playwright, обеспечивая комплексное покрытие всех уровней системы.