# Developer Branch - Workflow Guide

## 🔧 Процесс разработки

Ветка `developer` используется для тестирования всех изменений перед их внедрением в `main`.

### 📋 Рабочий процесс:

1. **Разработка**: Все изменения сначала коммитятся в ветку `developer`
2. **Тестирование**: CI/CD автоматически запускает полный набор тестов
3. **Валидация**: Проверяем результаты в GitHub Actions
4. **Перенос**: После успешного тестирования создаем Pull Request в `main`

## 🚀 Запуск автоматических тестов

При push в ветку `developer` автоматически запускаются:

### GitHub Actions Workflows:
- **Comprehensive Testing Pipeline**: Полный набор тестов
- **Docker Build & Deploy**: Сборка и тестирование Docker образов

### Компоненты тестирования:
- ✅ **Profile Validation** - Проверка конфигураций профилей
- ✅ **Unit Tests** - Модульные тесты Python сервисов
- ✅ **Integration Tests** - Интеграционные тесты
- ✅ **Startup Tests** - Тестирование запуска различных профилей
- ✅ **Security Tests** - Проверки безопасности

## 🔍 Локальное тестирование

Перед push рекомендуется провести локальное тестирование:

```bash
# Базовое тестирование профилей
./scripts/test-profiles.sh basic --verbose

# Комплексное тестирование
./scripts/run-comprehensive-tests.sh all --verbose

# Тестирование конкретного профиля с запуском
./scripts/test-profiles.sh custom "default,developer" --with-startup --timeout 300

# Мониторинг системы
./scripts/advanced-monitor.sh check --verbose

# Проверка backup системы
./scripts/backup-disaster-recovery.sh list
```

## 📊 Мониторинг результатов

### GitHub Actions Dashboard:
https://github.com/sattva2020/N8N-AI-Starter-Kit-Advanced/actions

### Ожидаемые результаты:
- ✅ **Profile Configuration Validation** - Все профили должны пройти валидацию
- ✅ **Unit Tests** - Все Python тесты должны выполниться успешно
- ✅ **Integration Tests** - API endpoints должны отвечать корректно
- ✅ **Service Startup Tests** - Все matrix комбинации должны запускаться
- ✅ **Security & Audit Tests** - Проверки безопасности должны пройти

## 🎯 Критерии готовности для merge в main

Перед созданием Pull Request убедитесь, что:

- [ ] Все GitHub Actions тесты проходят успешно (зеленые галочки)
- [ ] Нет критических ошибок в логах CI/CD
- [ ] Локальное тестирование выполнено успешно
- [ ] Документация обновлена (если нужно)
- [ ] Конфигурационные файлы проверены

## 🔄 Создание Pull Request

1. Убедитесь, что все тесты в `developer` проходят
2. Перейдите на GitHub: https://github.com/sattva2020/N8N-AI-Starter-Kit-Advanced
3. Создайте Pull Request из `developer` в `main`
4. Заполните template с результатами тестирования
5. Дождитесь финального review и merge

## ⚡ Быстрые команды

```bash
# Переключение на developer ветку
git checkout developer

# Добавление изменений и commit
git add .
git commit -m "feat: описание изменений"

# Push изменений (запустит CI/CD)
git push origin developer

# Проверка статуса тестов
echo "Проверьте: https://github.com/sattva2020/N8N-AI-Starter-Kit-Advanced/actions"
```

## 🛡️ Политика безопасности

- Никогда не коммитьте реальные секреты или пароли
- Используйте только placeholder значения в template.env
- Все переменные окружения должны быть задокументированы
- CI/CD автоматически проверяет на наличие hardcoded secrets

---

**Счастливого кодинга! 🚀**