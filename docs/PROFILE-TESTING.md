# Тестирование профилей развертывания

Система N8N AI Starter Kit поддерживает комплексное тестирование различных профилей развертывания Docker Compose для обеспечения корректной работы во всех конфигурациях.

## Доступные профили

### Основные профили
- **`default`**: Базовые сервисы (Traefik, n8n, PostgreSQL)
- **`developer`**: + Qdrant, Web Interface, Document Processor, LightRAG  
- **`monitoring`**: + Grafana, Prometheus
- **`analytics`**: + ETL Processor, ClickHouse
- **`gpu`**: + GPU-ускоренные AI сервисы с локальными моделями

### Комбинированные профили
- **`default,developer`**: Разработка с AI функциями
- **`default,monitoring`**: Базовая система с мониторингом
- **`default,developer,monitoring`**: Полная разработческая среда
- **`default,developer,monitoring,analytics`**: Максимальная конфигурация
- **`default,developer,gpu`**: Разработка с GPU-ускорением

## Инструменты тестирования

### 1. Основной скрипт тестирования профилей

```bash
# Базовое тестирование конфигураций
./scripts/test-profiles.sh

# Расширенное тестирование всех комбинаций
./scripts/test-profiles.sh extended --dry-run

# Тестирование GPU профилей
./scripts/test-profiles.sh gpu --verbose

# Тестирование продакшн конфигураций
./scripts/test-profiles.sh production

# Тестирование конкретного профиля
./scripts/test-profiles.sh custom "default,monitoring"
```

### 2. Параметры тестирования

#### Основные опции
- **`--dry-run`**: Только валидация конфигураций без запуска сервисов
- **`--with-startup`**: Полное тестирование с запуском сервисов
- **`--timeout N`**: Таймаут запуска в секундах (по умолчанию: 300)
- **`--verbose`**: Подробный вывод
- **`--report`**: Генерация детального отчета

#### Наборы профилей
- **`basic`**: Основные комбинации профилей (по умолчанию)
- **`extended`**: Все возможные комбинации профилей  
- **`gpu`**: Профили с GPU поддержкой
- **`production`**: Рекомендуемые продакшн конфигурации
- **`custom`**: Пользовательский профиль

### 3. Интеграция с comprehensive test runner

```bash
# Запуск всех тестов включая профили
./scripts/run-comprehensive-tests.sh all

# Только тестирование профилей
./scripts/run-comprehensive-tests.sh profiles

# Тестирование профилей с подробным выводом
./scripts/run-comprehensive-tests.sh profiles --verbose
```

## Процесс тестирования

### Этапы валидации профилей

1. **Проверка конфигурации Docker Compose**
   - Валидация YAML синтаксиса
   - Проверка определений сервисов
   - Валидация зависимостей между сервисами

2. **Анализ состава сервисов**
   - Подсчет количества сервисов в профиле
   - Проверка наличия обязательных сервисов
   - Валидация профиль-специфичных требований

3. **Проверка требований профилей**
   - **GPU профили**: наличие GPU сервисов
   - **Monitoring профили**: наличие Grafana/Prometheus
   - **Analytics профили**: наличие ClickHouse/ETL
   - **Developer профили**: наличие AI сервисов
   - **Default профили**: наличие базовых сервисов

4. **Тестирование запуска (опционально)**
   - Запуск сервисов с указанным профилем
   - Проверка health endpoints
   - Валидация доступности сервисов
   - Корректное завершение работы

### Проверка здоровья сервисов

Система автоматически проверяет health endpoints для:

```
traefik     -> http://localhost:8080/ping
n8n         -> http://localhost:5678/healthz  
web-interface -> http://localhost:8000/health
document-processor -> http://localhost:8001/health
etl-processor -> http://localhost:8002/health
lightrag    -> http://localhost:8003/health
grafana     -> http://localhost:3000/api/health
prometheus  -> http://localhost:9090/-/healthy
qdrant      -> http://localhost:6333/health
```

## Примеры использования

### Быстрая проверка конфигураций

```bash
# Проверить все базовые профили
./scripts/test-profiles.sh basic --dry-run

# Результат:
# ✓ Profile configuration valid: default
# ✓ Profile configuration valid: default,developer  
# ✓ Profile configuration valid: default,monitoring
# ✓ Profile configuration valid: default,developer,monitoring
```

### Полное тестирование с запуском

```bash
# Тестирование с реальным запуском сервисов
./scripts/test-profiles.sh basic --with-startup --verbose

# Результат включает:
# - Валидацию конфигурации
# - Запуск сервисов
# - Проверку health endpoints
# - Корректное завершение
```

### Тестирование GPU конфигурации

```bash
# Проверка GPU профилей
./scripts/test-profiles.sh gpu --dry-run --verbose

# Автоматическая проверка:
# - Наличие GPU сервисов в профиле
# - Правильность конфигурации GPU ресурсов
# - Валидация CUDA настроек
```

### Генерация отчета

```bash
# Создание детального отчета
./scripts/test-profiles.sh extended --report

# Создает файл: test-results/profile-test-report-YYYYMMDD_HHMMSS.md
```

## Интеграция с CI/CD

### В пайплайне сборки

```yaml
# .github/workflows/test.yml
- name: Test Docker Compose Profiles
  run: |
    ./scripts/test-profiles.sh basic --dry-run
    ./scripts/test-profiles.sh production --dry-run
```

### Pre-commit hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
./scripts/test-profiles.sh basic --dry-run || exit 1
```

## Отчеты и логирование

### Структура отчета

```markdown
# Profile Testing Report

**Generated:** 2024-01-15 14:30:00
**Profile Set:** extended
**Test Mode:** Configuration Only

## Summary
- **Profiles Tested:** 11
- **Profiles Passed:** 11  
- **Profiles Failed:** 0
- **Success Rate:** 100%

## Test Configuration
- Dry Run: true
- With Startup: false
- Timeout: 300s
- Verbose: true
```

### Логи выполнения

```
ℹ Testing profile: default,developer,monitoring
✓ Configuration valid
ℹ Services in profile: 8
ℹ Service list:
  - traefik
  - postgres
  - n8n
  - qdrant
  - web-interface
  - document-processor
  - lightrag
  - grafana
✓ Core services found in default profile
✓ Developer services found in developer profile  
✓ Monitoring services found in monitoring profile
✓ Profile test passed: default,developer,monitoring
```

## Устранение неполадок

### Частые проблемы

**1. Конфигурация невалидна**
```
✗ Profile configuration invalid: default,gpu
```
**Решение**: Проверить наличие GPU сервисов в docker-compose.yml

**2. Сервисы не запускаются**
```
✗ Services failed to start within timeout for profile: default,monitoring
```
**Решение**: Увеличить таймаут или проверить ресурсы системы

**3. Health check не проходит**
```
⚠ Failed health checks: grafana prometheus
```
**Решение**: Дождаться полной инициализации сервисов или проверить логи

### Отладочные команды

```bash
# Проверить конфигурацию профиля
COMPOSE_PROFILES="default,monitoring" docker compose config

# Посмотреть логи при запуске
docker compose logs --follow

# Проверить статус сервисов
docker compose ps

# Ручная проверка health endpoint
curl http://localhost:3000/api/health
```

## Расширение тестирования

### Добавление новых профилей

1. Обновить `PROFILE_SETS` в `scripts/test-profiles.sh`
2. Добавить валидацию в `validate_profile_requirements()`
3. Обновить health endpoints в `check_profile_health()`

### Кастомные проверки

```bash
# Добавить новую функцию валидации
validate_custom_profile() {
    local profile="$1"
    # Пользовательская логика проверки
}
```

Эта система тестирования профилей обеспечивает надежность развертывания во всех поддерживаемых конфигурациях и предотвращает проблемы в продакшн среде.