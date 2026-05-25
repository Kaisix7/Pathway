# Git workflow

## Ветки

Для каждой новой функции лучше создавать отдельную ветку:

```bash
git checkout -b feature/map-search
```

Примеры названий:

- `feature/docker-backend`
- `feature/order-payment-flow`
- `feature/map-search`
- `fix/api-errors`

## Commit

После изменений:

```bash
git add .
git commit -m "Add Docker backend setup"
```

Хорошие commit messages:

- `Add Docker backend setup`
- `Link orders to users`
- `Add payment status flow`
- `Document deployment steps`

## Push

Отправить ветку на GitHub:

```bash
git push origin feature/map-search
```

Потом открыть Pull Request в `main`.

## Проверка перед push

Перед отправкой желательно запускать:

```bash
docker compose up --build
flutter test
```

Если backend запускается, тесты проходят и приложение открывается, ветку можно отправлять.
