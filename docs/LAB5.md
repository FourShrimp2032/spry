# Lab 5 — щотижневий звіт про зустрічі (event-driven)

Щопонеділка о 07:00 за Києвом система будує CSV-звіт за минулий ISO-тиждень, кладе його в S3 і надсилає через SES. Ніхто нічого не натискає.

```
EventBridge Scheduler ─┐  {"week": null, "source": "schedule"}
make report-now ───────┴─► SQS report-requests ──(3 спроби)──► report-requests-dlq
                                  │ BatchSize 1
                                  ▼
                 report-builder (Lambda, образ backend, у VPC, без NAT)
                    │ PostgreSQL (RDS)        │ PutObject через S3 gateway endpoint
                    ▼                         ▼
                                    s3://spry-reports-<account>/reports/2026-W40.csv
                                              │ s3:ObjectCreated:* (reports/, .csv)
                                              ▼
                              report-mailer (Lambda, поза VPC) ──► SES ──► inbox
```

**Відмінність від тексту лабораторної.** Lab 4 (API на Lambda + Aurora Serverless) у цьому repository не робився: API досі працює на ECS Fargate, база — RDS PostgreSQL у приватних підмережах `spry-lab` (eu-north-1). Обмеження те саме, що описано в лабораторній: у приватних підмережах немає NAT, тож функція, яка бачить базу, не бачить інтернету. Тому builder розміщено в цих підмережах із security group backend (база вже приймає її на 5432), а все інше — як у завданні. Регіон — eu-north-1, поруч із базою.

## Що додано

| Частина | Файл | Що робить |
|---|---|---|
| Звіт | `backend/app/reports/weekly.py` | `build_weekly_report(week) -> bytes` без AWS. Тиждень — параметр (`2026-W40`), межі — понеділок 00:00 Europe/Kyiv. Кількість і години цього та попереднього тижня, зміна, п'ять найдовших зустрічей (назва, початок, тривалість, учасники). Однакові дані дають однакові байти; ім'я файлу `reports/<week>.csv` |
| Builder | `backend/app/reports/lambda_handler.py` | Приймає і прямий виклик, і SQS record. Перший рядок логу — JSON з `trigger` (`schedule` / `sqs` / `direct`), `via`, `week`. `REPORT_FAIL_WEEK` — вправа з DLQ |
| Тести | `backend/tests/test_reports.py` | Межі тижня в Києві, перехід через рік (2026-W53), підсумки, top-5, ідемпотентність, обидві форми події |
| Інфраструктура | `infra/reports.yml` | Bucket (приватний, 90 днів, лише TLS), S3 gateway endpoint, SQS + DLQ (`maxReceiveCount: 3`, visibility 360 с = 6 × 60 с), Scheduler `cron(0 7 ? * MON *)` у Europe/Kyiv → SQS, builder (образ backend, `python -m awslambdaric`), mailer (inline Python, лише `s3:GetObject` і SES), S3 notification + `Lambda::Permission`, SES identity домену (DKIM) і отримувача |
| Deploy | `scripts/deploy-reports.sh`, `make deploy-reports` | Образ, хост БД, користувач і секрет береться з task definition, яку зараз виконує ECS; приватні підмережі та їхні route tables — з VPC. Пошта — з `.env` |
| Команди | `Makefile` | `report-now WEEK=…`, `report-local WEEK=…`, `reports-ls`, `report-logs` |

Пароль БД потрапляє в змінну середовища builder через dynamic reference `{{resolve:secretsmanager:…}}` під час deploy: без NAT функція не може читати Secrets Manager під час роботи, а interface endpoint коштує ~$7/міс за AZ.

Явне ім'я bucket `spry-reports-<account>` розриває циклічну залежність: дозволу для S3 потрібен ARN bucket, а bucket з notification потребує дозволу. ARN будується через `!Sub`, і bucket просто `DependsOn` дозвіл.

## Кроки

### 0. Локально (вже перевірено)
```bash
docker compose up -d
make report-local WEEK=2026-W41
```

### 1. Новий образ backend
Commit цієї лабораторної потрібно запушити в `main`: CI проганяє тести і `make deploy-backend` збирає образ із `awslambdaric`. Дочекайтеся зеленого deploy job. `deploy-reports.sh` відмовиться працювати, якщо ECS ще виконує старий образ.

### 2. `.env`
```
REPORT_MAIL_DOMAIN=antonyivaso.dynv6.net
REPORT_RECIPIENTS=<ваш email>
```

### 3. Stack
У CloudShell (eu-north-1) або з admin profile, з кореня repository (`git pull` спершу):
```bash
make deploy-reports
```
Outputs покажуть `DkimRecord1..3` у вигляді `<name> CNAME <value>`.

### 4. SES
1. У dynv6 → zone `antonyivaso.dynv6.net` → Records додайте три CNAME з outputs (ім'я — частина перед `.antonyivaso.dynv6.net`, наприклад `abc123._domainkey`). За кілька хвилин SES console → Identities покаже домен **Verified**.
2. На `REPORT_RECIPIENTS` прийде лист від AWS — відкрийте посилання. Sandbox доставляє лише на підтверджені адреси (до 200 листів на добу).

### 5. Перевірка (item 4, 5, скриншот)
```bash
make report-now WEEK=2026-W41      # на вимогу, trigger=sqs
make reports-ls                    # aws s3 ls … --recursive
make report-logs                   # рядки "triggered" обох функцій
```
За хвилину: новий об'єкт у S3, лист із вкладенням `spry-2026-W41.csv`.

Розклад без очікування понеділка — на один запуск:
```bash
make deploy-reports SCHEDULE='rate(5 minutes)'
# дочекайтеся одного рядка trigger=schedule у make report-logs, одразу:
make deploy-reports
```
Поки стоїть `rate(5 minutes)`, звіт за минулий тиждень перебудовується кожні 5 хвилин — і кожного разу приходить лист.

### 6. Зламати і полагодити (DLQ)
```bash
make deploy-reports FAIL_WEEK=2026-W30
make report-now WEEK=2026-W30
```
Повідомлення повертається в чергу після visibility timeout (6 хв), тому три спроби займають ~12–18 хв. Потім воно в `spry-report-requests-dlq` (SQS console → Send and receive messages → Poll). Полагодити: `make deploy-reports` (без FAIL_WEEK), потім у консолі DLQ → **Start DLQ redrive** → у вихідну чергу. Прийде звіт за W30.

### 7. Двічі той самий тиждень
`make report-now WEEK=2026-W41` двічі → у S3 один файл, але два листи. Пояснення — у [LAB5-ANSWERS.md](LAB5-ANSWERS.md).

## Що здати

1. Посилання на commit цієї лабораторної (код звіту, `infra/reports.yml`, два handlers).
2. Скриншот листа від SES із CSV у вкладенні.
3. Вивід `make reports-ls`: щонайменше два звіти — від розкладу і від `make report-now`.
4. Три рядки CloudWatch з `make report-logs`: `"trigger": "schedule"` і `"trigger": "sqs"` від builder, `"trigger": "s3"` від mailer.
5. Відповіді — [LAB5-ANSWERS.md](LAB5-ANSWERS.md).

## Видалення
`aws cloudformation delete-stack --region eu-north-1 --stack-name spry-reports` — спершу спорожніть bucket (`aws s3 rm s3://spry-reports-<account> --recursive`). DNS-записи DKIM видаліть у dynv6.
