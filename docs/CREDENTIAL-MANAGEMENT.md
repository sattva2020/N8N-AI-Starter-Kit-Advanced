# N8N Credential Management System

Автоматизированная система управления учетными данными для N8N AI Starter Kit.

## Обзор

Этот набор инструментов обеспечивает автоматическое создание и управление учетными данными N8N для всех сервисов в проекте. Поддерживает как Personal Access Token (PAT), так и Public API Key аутентификацию.

## Возможности

- ✅ **Автоматическое создание учетных данных** для всех сервисов проекта
- ✅ **Шаблонная система** с автоматическим расширением переменных окружения
- ✅ **Пакетные операции** с поддержкой отката изменений
- ✅ **Валидация окружения** перед созданием учетных данных
- ✅ **Интерактивный режим** для пошагового создания
- ✅ **Dry-run режим** для предварительного просмотра изменений
- ✅ **Кроссплатформенность** (Linux, macOS, Windows с Git Bash)

## Быстрый старт

### 1. Создание API ключа в N8N

1. Откройте N8N в браузере: `https://n8n.localhost`
2. Перейдите в **Settings → Personal Access Token**
3. Создайте новый токен с полными правами
4. Скопируйте токен и сохраните в переменной окружения:

```bash
# Добавьте в ваш .env файл
N8N_PERSONAL_ACCESS_TOKEN=your-token-here
```

### 2. Автоматическое создание учетных данных

```bash
# Создать учетные данные для всех основных сервисов
./scripts/auto-setup-credentials.sh

# Создать только для конкретных сервисов
./scripts/auto-setup-credentials.sh --services postgres,qdrant,openai

# Предварительный просмотр без создания
./scripts/auto-setup-credentials.sh --dry-run

# Принудительное пересоздание существующих
./scripts/auto-setup-credentials.sh --force
```

### 3. Интерактивный режим

```bash
# Запустить продвинутый менеджер учетных данных
python3 scripts/credential-manager.py --interactive
```

## Поддерживаемые сервисы

| Сервис | Тип | Описание |
|--------|-----|----------|
| `postgres` | PostgreSQL | Основная база данных для N8N и приложений |
| `qdrant` | HTTP Header Auth | Векторная база данных для AI эмбеддингов |
| `redis` | Redis | Кеш для сессий и временных данных |
| `openai` | HTTP Header Auth | OpenAI API для GPT моделей |
| `ollama` | HTTP Header Auth | Локальный LLM сервер |
| `neo4j` | Neo4j | Графовая база данных для knowledge graphs |
| `clickhouse` | HTTP Header Auth | Аналитическая база данных |
| `grafana` | HTTP Basic Auth | Панель мониторинга |

## Инструменты

### 1. Bash скрипт (auto-setup-credentials.sh)

Простой и быстрый способ создания учетных данных:

```bash
# Основные команды
./scripts/auto-setup-credentials.sh --help
./scripts/auto-setup-credentials.sh --list-services
./scripts/auto-setup-credentials.sh --check-auth
./scripts/auto-setup-credentials.sh --services postgres,qdrant
```

**Особенности:**
- Минимальные зависимости (bash, curl, jq)
- Быстрая работа
- Простота использования
- Подходит для автоматизации

### 2. Python менеджер (credential-manager.py)

Расширенные возможности управления учетными данными:

```bash
# Установка зависимостей
pip install requests

# Использование
python3 scripts/credential-manager.py --setup all
python3 scripts/credential-manager.py --list
python3 scripts/credential-manager.py --validate
python3 scripts/credential-manager.py --interactive
```

**Особенности:**
- Интерактивный режим
- Расширенная валидация
- Лучшая обработка ошибок
- Подробная отчетность

### 3. Базовый менеджер (create_n8n_credential.sh)

Низкоуровневый инструмент для точного контроля:

```bash
# Создание отдельной учетной записи
./scripts/create_n8n_credential.sh --type postgres --name "My DB" --data '{
  "host": "localhost",
  "port": 5432,
  "database": "mydb",
  "username": "user",
  "password": "pass"
}'

# Массовое создание из файла
./scripts/create_n8n_credential.sh --bulk config/n8n/credentials-template.json
```

## Аутентификация

### Personal Access Token (рекомендуется)

```bash
# В .env файле
N8N_PERSONAL_ACCESS_TOKEN=n8n_pat_xxxxxxxxxxxxxxxxxxxxxxxxxx

# Или в командной строке
export N8N_PERSONAL_ACCESS_TOKEN="your-token"
./scripts/auto-setup-credentials.sh
```

### Public API Key

```bash
# В .env файле
N8N_API_KEY=n8n_api_xxxxxxxxxxxxxxxxxxxxxxxxxx

# Или в командной строке
export N8N_API_KEY="your-key"
./scripts/auto-setup-credentials.sh
```

## Конфигурация

### Переменные окружения

Основные переменные для учетных данных:

```bash
# Обязательные для основных сервисов
POSTGRES_PASSWORD=your-secure-password
QDRANT_API_KEY=your-qdrant-key

# Опциональные для дополнительных сервисов
OPENAI_API_KEY=sk-your-openai-key
NEO4J_PASSWORD=your-neo4j-password
REDIS_PASSWORD=your-redis-password
CLICKHOUSE_USER=default
GRAFANA_ADMIN_PASSWORD=your-grafana-password
```

### Настройка N8N

```bash
# URL N8N (по умолчанию)
N8N_BASE_URL=http://localhost:5678

# Для HTTPS
N8N_BASE_URL=https://n8n.yourdomain.com
```

## Шаблоны учетных данных

Файл `config/n8n/credentials-template.json` содержит готовые шаблоны для всех сервисов. Переменные автоматически заменяются значениями из `.env`:

```json
{
  "name": "PostgreSQL - Main Database",
  "type": "postgres",
  "description": "Main PostgreSQL database for N8N",
  "data": {
    "host": "${POSTGRES_HOST:-postgres}",
    "port": "${POSTGRES_PORT:-5432}",
    "database": "${POSTGRES_DB:-n8n}",
    "username": "${POSTGRES_USER:-n8n_user}",
    "password": "${POSTGRES_PASSWORD}",
    "ssl": "disable"
  }
}
```

## Примеры использования

### Создание учетных данных для разработки

```bash
# 1. Настройка окружения
./scripts/setup.sh

# 2. Запуск сервисов
./start.sh --profile default,developer

# 3. Создание учетных данных
./scripts/auto-setup-credentials.sh --services postgres,qdrant,ollama
```

### Создание учетных данных для продакшна

```bash
# 1. Создание всех учетных данных с валидацией
python3 scripts/credential-manager.py --validate
python3 scripts/credential-manager.py --setup all --force

# 2. Проверка созданных учетных данных
python3 scripts/credential-manager.py --list
```

### Обновление существующих учетных данных

```bash
# Принудительное обновление с новыми паролями
./scripts/auto-setup-credentials.sh --force --services postgres,qdrant

# Или интерактивно выбрать что обновлять
python3 scripts/credential-manager.py --interactive
```

## Рабочие процессы (Workflows)

После создания учетных данных, вы можете использовать готовые шаблоны workflow:

### Импорт демонстрационного workflow

```bash
# Шаблон в config/n8n/workflow-templates/service-integration-demo.json
# Демонстрирует интеграцию с:
# - PostgreSQL (запросы к БД)
# - Qdrant (управление коллекциями)
# - LightRAG (AI запросы)
# - Ollama (локальные LLM)
```

### Использование учетных данных в workflow

```javascript
// В Node.js Code узлах
const credentials = {
  postgres: 'PostgreSQL - Main Database',
  qdrant: 'Qdrant - Vector Database',
  openai: 'OpenAI - API Service',
  ollama: 'Ollama - Local LLM Server'
};

// HTTP запрос с авторизацией
{
  "url": "http://qdrant:6333/collections",
  "headers": {
    "api-key": "{{ $credential('Qdrant - Vector Database').value }}"
  }
}
```

## Устранение неполадок

### Проблемы с аутентификацией

```bash
# Проверка подключения
./scripts/auto-setup-credentials.sh --check-auth

# Тестирование API
curl -H "Authorization: Bearer $N8N_PERSONAL_ACCESS_TOKEN" \
     http://localhost:5678/api/v1/credentials
```

### Проблемы с переменными окружения

```bash
# Валидация переменных
python3 scripts/credential-manager.py --validate

# Проверка загрузки .env
source .env && env | grep -E "(POSTGRES|QDRANT|OPENAI)"
```

### Проблемы с сервисами

```bash
# Проверка доступности сервисов
./scripts/maintenance/monitor.sh health

# Проверка логов N8N
docker logs n8n-app
```

## API Reference

### Bash скрипт API

```bash
# Синтаксис
./scripts/auto-setup-credentials.sh [OPTIONS]

# Опции
--services LIST     # Список сервисов через запятую
--dry-run          # Предварительный просмотр
--force            # Перезаписать существующие
--skip-existing    # Пропустить существующие (по умолчанию)
--list-services    # Показать доступные сервисы
--check-auth       # Проверить аутентификацию
```

### Python API

```bash
# Синтаксис
python3 scripts/credential-manager.py [OPTIONS]

# Опции
--setup SERVICES   # Создать учетные данные
--list            # Список существующих
--interactive     # Интерактивный режим
--validate        # Валидация окружения
--test-connection # Тест подключения
--force           # Перезаписать существующие
--dry-run         # Предварительный просмотр
```

## Безопасность

### Рекомендации

1. **Никогда не коммитьте .env файлы** с реальными паролями
2. **Используйте сильные пароли** генерируемые `./scripts/setup.sh`
3. **Ограничьте доступ к API ключам** только необходимыми правами
4. **Регулярно ротируйте токены** и пароли
5. **Мониторьте использование API** через логи N8N

### Управление секретами

```bash
# Генерация безопасных паролей
./scripts/setup.sh  # Автоматическая генерация

# Ручная генерация
openssl rand -base64 32

# Проверка силы паролей
grep -E "change_this|123456|password" .env  # Не должно найти ничего
```

## Заключение

Система управления учетными данными N8N AI Starter Kit обеспечивает:

- **Автоматизацию** создания и управления учетными данными
- **Безопасность** с использованием сильной аутентификации
- **Гибкость** с поддержкой различных типов сервисов
- **Простоту** использования для разработчиков
- **Надежность** с валидацией и обработкой ошибок

Это позволяет быстро развернуть полнофункциональную AI платформу с автоматически настроенными интеграциями между всеми сервисами.