# Відповіді до захисту

## Чому monorepo?
Один коміт змінює схему, API і UI разом. Агент бачить модель, міграцію, endpoint та компонент у тому самому дереві і не вгадує контракт. Для невеликої команди це важливіше за незалежні релізи трьох репозиторіїв. Недолік — більше спільних правил і потенційно довший CI; з ростом можна додати path filters, зберігаючи спільний контракт.

## Docker Compose
- `services` описує три процеси; `image` використовує готовий образ, `build` будує образ за Dockerfile.
- `ports` публікує container port на host. Тут 8000 і 5173 доступні тільки на localhost. `expose` документує внутрішній порт, але не публікує його; контейнери однієї мережі можуть зв'язуватись без нього.
- `environment` задає runtime конфігурацію. Локальний пароль у compose навмисно навчальний; production використовує Secrets Manager, а не цей файл.
- `volumes` зберігає PostgreSQL між перезапусками. Видалення контейнера не дорівнює видаленню volume.
- `command` замінює CMD образу. Локально запускає Alembic, а потім через exec — Uvicorn. Помилка міграції зупиняє запуск API.
- `healthcheck` активно перевіряє готовність. `depends_on: condition: service_healthy` чекає позитивної перевірки; сам `depends_on` гарантував би тільки порядок запуску.
- У production не використовуємо Vite dev server, локальні паролі або Compose volume замість керованої persistent БД.

Compose керує взаємодією сервісів; Dockerfile описує один образ. При переході в ECS Dockerfile backend залишається, Compose замінюють task definition, service, networking та managed database. Frontend на AWS — статичний bundle.

Якщо PostgreSQL зникає вже після старту, Compose не врятує запит. SQLAlchemy pre-ping перевіряє connection при отриманні з pool, failed session rollback-иться, API повертає 503 при connection failure. Наступний запит може відновитися після повернення БД. POST не повторюється автоматично: повтор міг би створити дубль. Для реального продукту варто додати idempotency keys.

## Base images
Образ — файлове середовище й runtime, побудовані шарами. Python slim містить Python і мінімальні Debian бібліотеки; повний Debian-варіант має більше системних інструментів та build dependencies. Slim менший, але пакети без binary wheels можуть вимагати compiler та headers. Alpine використовує musl замість glibc: менший початковий образ не гарантує простішої чи швидшої збірки Python dependencies. Вибір base image визначає частину security updates; pinned tag забезпечує вибір версії, digest дає суворішу незмінність. Оновлення треба робити окремо й перевіряти.

## Backend
`main.py` — HTTP/CORS/status codes; `schemas.py` — вхід і вихід; `models.py` — persistent mapping та database constraints; `services.py` — операції; `database.py` — engine/session. Такий поділ дозволяє змінювати транспорт окремо від зберігання.

SQLAlchemy дає параметризовані запити, mapping, transactions, identity map і composition. Він не скасовує SQL: складні joins, N+1 або повільний query plan треба аналізувати на рівні БД, іноді писати явний SQL.

Alembic зберігає історію schema changes. `create_all()` створює відсутні таблиці, але не є планом безпечної зміни таблиці з існуючими даними. Міграції не виконуються під час build: тоді не має бути доступу до production БД. Локально вони виконуються на startup; на AWS — окремим одноразовим task. Для production використовуємо backward-compatible expand/contract migrations; rollback образу не автоматично відкочує схему.

## CI/CD і YAML
`on` — події; `jobs` — одиниці роботи; `runs-on` — runner; `steps` — послідовність; `uses` — готова action; `run` — команда. Backend і frontend checks йдуть паралельно; deploy чекає обидва через `needs`. YAML потребує пробілів, коректних рівнів відступу й списків через `-`.

CI перевіряє кожну зміну. CD використовує перевірений commit SHA для delivery в AWS. Makefile зберігає одну deploy-рецептуру для локального запуску й CI.

Щоб продемонструвати red pipeline, на окремій гілці додайте unused Python import, зробіть commit і push, зафіксуйте посилання на failed run. Потім видаліть import, зробіть наступний commit і push, зафіксуйте green run. Цей крок потребує реального GitHub repo; локальний провал Ruff не є доказом red GitHub Actions.

## AWS
CloudFront забезпечує CDN і HTTPS для власного домену перед private S3. Використовується bucket REST origin та OAC; S3 website endpoint не є private origin для цього варіанта. Certificate видає ACM; CloudFront його використовує.

ECR зберігає container images; ECS запускає їх. Fargate прибирає управління серверами; ALB дає стабільну точку входу, TLS і routing до живих tasks.

`/health` перевіряє SELECT 1, тому контейнер без БД не вважається готовим. ALB вилучає unhealthy targets із нормальної маршрутизації; ECS service scheduler замінює unhealthy tasks. Якщо всі targets unhealthy, ALB може fail-open, тому health check не є гарантією відсутності помилок. Спільна відмова БД не лікується нескінченними рестартами; потрібні monitoring і recovery БД.

Validation CNAME доводить ACM контроль над DNS. Routing CNAME/Route53 Alias направляє клієнтів до CloudFront або ALB. Це різні записи з різними цілями.

Викрадений довготривалий key працює до відкликання. OIDC дає тимчасовий доступ тільки через дозволений repo/branch і permissions role. Компрометація дозволеного workflow все ще небезпечна: branch protection, review та least privilege потрібні й тут.

На 1000 організацій можна залишити monorepo, S3/CloudFront, ECR/ECS, ALB і managed PostgreSQL. Поточний застосунок не має tenant isolation, auth, pagination та rate limits: це треба додати до реального multi-tenant запуску. Який performance bottleneck буде першим, покаже load test; ймовірні кандидати — безмежний list endpoint, database connections та queries. Не можна чесно назвати один без вимірювань.
