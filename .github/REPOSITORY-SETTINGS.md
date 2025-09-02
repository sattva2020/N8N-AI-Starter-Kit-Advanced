# GitHub Repository Settings

## 🛡️ Branch Protection Rules

### Main Branch Protection
Для обеспечения качества кода в продакшн-ветке рекомендуется настроить следующие правила:

**Settings → Branches → Add rule для `main`:**

- ✅ **Require a pull request before merging**
  - Require approvals: 1
  - Dismiss stale reviews when new commits are pushed
  - Require review from code owners

- ✅ **Require status checks to pass before merging**
  - Require branches to be up to date before merging
  - Status checks:
    - `Profile Configuration Validation`
    - `Unit Tests`
    - `Integration Tests` 
    - `Service Startup Tests`
    - `Security & Audit Tests`

- ✅ **Require conversation resolution before merging**

- ✅ **Require signed commits**

- ✅ **Include administrators** (применять правила и для администраторов)

### Developer Branch Settings
Ветка `developer` может быть менее строгой для быстрой разработки:

- ✅ **Require status checks to pass before merging** (опционально)
- ✅ **Delete head branches automatically** after merge

## 🔧 Workflow Permissions

**Settings → Actions → General:**

- ✅ **Allow GitHub Actions to create and approve pull requests**
- ✅ **Read and write permissions** для GITHUB_TOKEN
- ✅ **Allow actions and reusable workflows** от GitHub и verified creators

## 📋 Environment Secrets

**Settings → Secrets and variables → Actions:**

### Repository Secrets (если нужны):
- `DOCKER_REGISTRY_TOKEN` - для приватных Docker registry
- `SLACK_WEBHOOK_URL` - для уведомлений
- `STAGING_SERVER_KEY` - для deployment

### Environment Secrets:
- **staging**: development deployment secrets
- **production**: production deployment secrets

## 🎯 Recommended Workflow

1. **Development**: Работа в ветке `developer`
2. **Testing**: Автоматические CI/CD тесты в `developer`
3. **Review**: Pull Request из `developer` в `main`
4. **Production**: Merge в `main` только после успешного review

Этот подход обеспечивает:
- 🔒 Безопасность продакшн-кода
- ⚡ Быструю разработку в developer ветке  
- 🧪 Комплексное тестирование перед release
- 📊 Полную видимость изменений через PR