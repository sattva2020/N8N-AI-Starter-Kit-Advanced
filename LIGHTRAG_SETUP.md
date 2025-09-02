# LightRAG Integration Setup Guide

## Краткая инструкция по настройке LightRAG

### 1. Обязательные переменные окружения

Добавьте в ваш `.env` файл:

```bash
# OpenAI API (обязательно для LightRAG)
OPENAI_API_KEY=your_openai_api_key_here

# LightRAG настройки (опционально, есть значения по умолчанию)
LIGHTRAG_PORT=8003
LIGHTRAG_WORKERS=1
LIGHTRAG_LLM_MODEL=gpt-4o-mini
LIGHTRAG_EMBEDDING_MODEL=text-embedding-3-small
LIGHTRAG_MAX_TOKENS=32768
LIGHTRAG_CHUNK_SIZE=1200
LIGHTRAG_OVERLAP_SIZE=100
OPENAI_API_BASE=  # оставьте пустым для стандартного API OpenAI
```

### 2. Запуск с LightRAG

```bash
# Запуск с профилем developer (включает LightRAG)
./start.sh --profile default,developer,monitoring
```

### 3. Проверка работы

```bash
# Проверка здоровья сервиса
curl http://localhost:8003/health

# Загрузка тестового документа
curl -X POST "http://localhost:8003/documents/ingest" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "LightRAG - это система для извлечения и генерации знаний на основе графов.",
    "metadata": {"source": "test"},
    "source": "test_document"
  }'

# Запрос к графу знаний
curl -X POST "http://localhost:8003/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Что такое LightRAG?",
    "mode": "hybrid"
  }'
```

### 4. Интеграция с N8N

LightRAG доступен по адресу `https://api.localhost/lightrag` через Traefik. 
Вы можете использовать HTTP Request узлы в N8N для интеграции:

- **Загрузка документов**: `POST /lightrag/documents/ingest`
- **Запросы к графу**: `POST /lightrag/query`
- **Список документов**: `GET /lightrag/documents`

### 5. Режимы запросов

- **naive**: Простой семантический поиск
- **local**: Локальный поиск по графу
- **global**: Глобальный анализ графа
- **hybrid**: Комбинированный подход (рекомендуется)

### 6. Мониторинг

LightRAG экспортирует метрики Prometheus:
- Количество обработанных документов
- Время выполнения запросов
- Статус здоровья сервиса

Метрики доступны в Grafana при использовании профиля `monitoring`.

### 7. Тестирование

Запустите включенный тестовый скрипт:

```bash
./services/lightrag/test_lightrag.sh
```

### Часто задаваемые вопросы

**Q: LightRAG не запускается**
A: Проверьте, что установлен правильный OPENAI_API_KEY в файле .env

**Q: Медленные ответы**
A: LightRAG использует OpenAI API, время ответа зависит от модели и сложности запроса

**Q: Высокое потребление памяти**
A: При первом запуске модели загружаются в память, это нормально

Для получения подробной информации см. `services/lightrag/README.md`.