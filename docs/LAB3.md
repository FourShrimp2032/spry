# Lab 3 — вхід через Cognito

Стан Lab 2 зафіксовано тегом [`lab2`](https://github.com/FourShrimp2032/spry/tree/lab2). Lab 3 лише додає вхід: поки repository variable `AUTH_STACK` порожня, CI збирає сайт так само, як у Lab 2, а API лишається публічним, доки не ввімкнено `PROTECT_API=1`.

## Що додано

| Частина | Файл | Що робить |
|---|---|---|
| User pool як код | `infra/auth.yml` | UserPool (Essentials, email як логін, self sign-up, політика паролів, тег `PROJECT_NAME`), публічний клієнт без секрету з code flow, Google IdP із mapping email/email_verified/name, домен managed login v2, ManagedLoginBranding |
| Маршрути сайту | `infra/aws-stack.json` | CloudFront Function віддає `index.html` для `/login/` і `/auth/callback/` (S3 REST origin не має index documents). Deploy role GitHub отримує лише `cloudformation:DescribeStacks` на `spry-auth`, щоб Makefile читав outputs |
| Оновлення stack | `scripts/aws-update-stack.sh`, `scripts/add-sign-in-routes.py` | Бере шаблон, який реально розгорнуто в AWS (він відрізняється від `infra/aws-stack.json`), додає лише зміни для входу, створює change set зі старими значеннями параметрів; відмовляє, якщо змінюється щось, крім Distribution, SpaRouteFunction і GitHubDeployRole (БД і ECS service захищені) |
| Deploy auth | `make deploy-auth` | Бере URL сайту з outputs `spry-lab`, Google client із `.env`, секрет іде як NoEcho параметр |
| Frontend | `frontend/src/auth.js`, `LoginPage.jsx`, `main.jsx`, `App.jsx` | `react-oidc-context` + `oidc-client-ts`; кнопка Sign in, email і Sign out у header; `/login/` одразу викликає `signinRedirect()`; вихід через Cognito `/logout` |
| Build-змінні | `Makefile` | `VITE_COGNITO_AUTHORITY`, `VITE_COGNITO_CLIENT_ID`, `VITE_COGNITO_DOMAIN` читаються з outputs auth stack, не копіюються вручну |
| Stretch: захист API | `backend/app/auth.py` | Перевіряє access token: підпис за JWKS (ключі кешуються), `exp`, `iss`, `client_id`, `token_use=access`. Без токена — 401. `/health` лишається публічним для ALB |

Callback: `https://<сайт>/auth/callback/`, logout: `https://<сайт>/`, плюс те саме для `http://localhost:5173`. Слеш у кінці обов'язковий — Cognito порівнює URL точно.

## Кроки (виконує власник акаунтів)

### 1. Префікс домену Cognito
Оберіть унікальний префікс, наприклад `spry-fourshrimp`. Не можна використовувати слова `aws`, `amazon`, `cognito`. Домен буде `https://<prefix>.auth.us-east-1.amazoncognito.com`.

### 2. Google OAuth client
У Google Cloud console, у власному project:
1. **Google Auth Platform → Branding**: назва застосунку `Spry`, support email. **Audience**: External.
2. **Data access**: лише `openid`, `email`, `profile`.
3. **Audience → Publish app** — статус має бути **In production**. У Testing викладач отримає помилку.
4. **Clients → Create client → Web application**:
   - Authorised JavaScript origin: `https://<prefix>.auth.us-east-1.amazoncognito.com`
   - Authorised redirect URI: `https://<prefix>.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`
5. Скопіюйте Client ID і Client secret у `.env` (файл у `.gitignore`):
   ```
   COGNITO_DOMAIN_PREFIX=spry-fourshrimp
   GOOGLE_CLIENT_ID=....apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=GOCSPX-...
   ```

### 3. Оновити `spry-lab` (CloudFront Function + право читати outputs)
У CloudShell (eu-north-1) або з admin profile, з кореня repository:
```bash
make update-stack
```
Скрипт покаже таблицю змін. Очікувано: `Add SpaRouteFunction`, `Modify Distribution`, `Modify GitHubDeployRole`, без Replacement. Підтвердіть `y`. Будь-яка інша зміна — скрипт сам скасує change set.

### 4. Створити auth stack (us-east-1)
```bash
make deploy-auth
```
Наприкінці друкуються outputs. `GoogleRedirectUri` має збігатися з URI з кроку 2.

### 5. Увімкнути вхід у CI і задеплоїти frontend
GitHub → Settings → Secrets and variables → Actions → Variables: додайте `AUTH_STACK = spry-auth`. Потім push у main або **Actions → Run workflow**. Локальна альтернатива з тими самими змінними, що й у CI: `make deploy-frontend`.

### 6. Перевірка «як незнайомець»
Email і пароль, у приватному вікні:
1. `https://d310vkwtz8a1f0.cloudfront.net/login/` → сторінка Cognito з формою і **Continue with Google**.
2. Sign up з email, який ви читаєте → код підтвердження → повернення на сайт, email у header.
3. Sign out → знову `/login/` → sign in.

Google, у новому приватному вікні: `/login/` → Continue with Google → акаунт, якого немає серед test users → email у header.

У консолі Cognito → Users: Google-користувач має username `google_…` і є окремим користувачем, навіть з тим самим email.

Зробіть два скриншоти з email у header (пароль і Google) і збережіть як `docs/signin-password.png` та `docs/signin-google.png`.

### 7. (Stretch) захистити API
Додайте repository variable `PROTECT_API = 1` і перезапустіть workflow. Backend отримає `COGNITO_*` із outputs auth stack. Перевірка:
```bash
curl -i https://d310vkwtz8a1f0.cloudfront.net/api/meetings   # 401
curl -i https://d310vkwtz8a1f0.cloudfront.net/health         # 200
```
Після цього неавторизований відвідувач бачить «Sign in to see and create meetings». Вимкнути: видаліть змінну й перезапустіть workflow.

## Локально
`make auth-env` друкує три рядки `VITE_COGNITO_*`; додайте їх у `.env` і запустіть `docker compose up --build`. `http://localhost:5173` уже є серед callback/logout URL. Для локального захисту API задайте ще `COGNITO_REGION`, `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`.

## Що здати
1. URL: `https://d310vkwtz8a1f0.cloudfront.net/login/`
2. Скриншоти: `docs/signin-password.png`, `docs/signin-google.png`
3. Посилання на коміт з `infra/auth.yml` і зміною frontend.

Self sign-up має лишатися ввімкненим, Google app — у статусі In production.

## Ліміти й teardown
- Вбудований sender Cognito: ~50 листів на добу на акаунт.
- Essentials: перші 10 000 MAU безкоштовно.
- Видалення: `aws cloudformation delete-stack --region us-east-1 --stack-name spry-auth` (видаляє всіх користувачів).
