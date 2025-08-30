#!/bin/bash
set -euo pipefail

echo "Начало тестирования"

profiles=("default" "default,developer" "default,monitoring")

for profile in "${profiles[@]}"; do
    echo "Тестирование профиля: $profile"
    
    if COMPOSE_PROFILES="$profile" docker compose config >/dev/null 2>&1; then
        echo "✓ $profile - валиден"
        
        service_count=$(COMPOSE_PROFILES="$profile" docker compose config --services 2>/dev/null | wc -l)
        echo "  Сервисов: $service_count"
    else
        echo "✗ $profile - невалиден"
    fi
    
    echo "---"
done

echo "Тестирование завершено"