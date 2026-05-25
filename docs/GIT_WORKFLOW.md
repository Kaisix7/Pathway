# Git workflow

## Ветки

В проекте используется разделение веток:

- `main` - стабильная основная ветка.
- `feature/*` - ветки для новых функций и изменений.

Для каждой новой задачи создается отдельная feature-ветка:

```bash
git checkout main
git pull origin main
git checkout -b feature/map-search
```

Примеры названий:

- `feature/docker-backend`
- `feature/order-payment-flow`
- `feature/map-search`
- `feature/test-change`

## Commit

После изменений:

```bash
git add .
git commit -m "Add branch protection documentation"
```

Хорошие commit messages:

- `Add Docker backend setup`
- `Link orders to users`
- `Add payment status flow`
- `Document deployment steps`

## Push

Отправить feature-ветку на GitHub:

```bash
git push origin feature/map-search
```

После push на GitHub открывается Pull Request из `feature/*` в `main`.

## Branch protection

Ветка `main` защищена.

Правила:

- нельзя пушить напрямую в `main`
- новые изменения делаются в ветках `feature/*`
- merge в `main` выполняется через Pull Request
- перед merge должен пройти CI
- review-комментарии видны во вкладке Pull Request на GitHub

## Code review

Минимальный процесс code review:

1. Разработчик создает ветку `feature/*`.
2. Разработчик открывает Pull Request в `main`.
3. Reviewer оставляет комментарий во вкладке `Files changed`.
4. После успешного CI и review Pull Request можно слить в `main`.

## Проверка перед push

Перед отправкой желательно запускать:

```bash
docker compose up --build
flutter test
```

Если backend запускается, тесты проходят и приложение открывается, ветку можно отправлять.
