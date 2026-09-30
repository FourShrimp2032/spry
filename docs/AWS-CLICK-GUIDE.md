# AWS: покроково для Safari

Це альтернативна інструкція для самостійного запуску з Safari. Для вже створеного stack `spry-lab` не запускайте create повторно. Подальші релізи виконує GitHub через OIDC; постійні AWS-ключі йому не потрібні.

## Етап 1 — лише перевірка, без створення ресурсів

1. У Safari відкрийте AWS Console зі своїм чинним входом.
2. Праворуч угорі виберіть **Europe (Stockholm) / eu-north-1**.
3. Натисніть значок **CloudShell** (`>_`) у верхній панелі. Дочекайтеся командного рядка.
4. Вставте `aws sts get-caller-identity` і натисніть Enter. Тут немає access keys; результат можна показати асистенту. Якщо ARN закінчується на `:root`, спершу налаштуємо IAM/SSO адміністративний вхід і MFA, як вимагає лабораторна.
5. Завантажте `spry-aws-setup.zip` на комп'ютер. У CloudShell виберіть **Actions → Upload file → Select file → Upload** і вкажіть ZIP.
6. Вставте блок:

```bash
unzip -o spry-aws-setup.zip
cd spry-aws-setup
bash scripts/aws-preflight.sh
```

7. Надішліть результат асистенту. Скрипт лише читає account identity, наявний OIDC provider, підтримувані версії PostgreSQL, стан `spry-lab` та Fargate quota. Він не створює ресурси й не показує секрети.

Якщо якась команда поверне AccessDenied, не підставляйте випадкові admin policies: надішліть текст помилки, щоб визначити, якого доступу бракує.

## Етап 2 — перегляд ресурсів і вартості

Шаблон створює:
- VPC, дві public і дві private subnet, route table і security groups;
- приватний PostgreSQL RDS `db.t4g.micro`, 20 GB, backup 1 день;
- ECS Fargate cluster/service, ECR і CloudWatch logs (7 днів);
- Application Load Balancer;
- приватний S3 bucket і CloudFront distribution;
- Secrets Manager secrets і IAM roles;
- GitHub OIDC provider, якщо в акаунті його ще немає.

**Це не гарантовано безкоштовно.** RDS, ALB, Fargate, public IPv4, Secrets Manager та зберігання/трафік можуть тарифікуватися. Free Tier або credits залежать від акаунта. NAT gateway не створюється. До початку встановіть AWS Budget у Billing → Budgets; повідомлення бюджету не є автоматичною зупинкою витрат. Перевірте оцінку у AWS Pricing Calculator для Stockholm і створюйте ресурси лише якщо приймаєте їх вартість.

Після preflight і перевірки вартості перейдіть до наступного етапу. Успішний preflight не означає, що ресурси вже створені.

## Етап 3 — створити інфраструктуру

У тій самій папці CloudShell:

```bash
bash scripts/aws-create.sh
```

**Саме ця команда починає створення платних ресурсів та IAM-доступу GitHub.** Вона повторно використовує наявний GitHub OIDC provider, обирає підтримувану PostgreSQL 16 minor version, перевіряє template і створює stack. Повторне створення поверх існуючого stack заблоковане.

У пошуку AWS введіть **CloudFormation**, відкрийте **Stacks → spry-lab → Events**. Оновлюйте до **CREATE_COMPLETE**; RDS/CloudFront можуть створюватися довго. При **CREATE_FAILED / ROLLBACK_IN_PROGRESS / ROLLBACK_COMPLETE** відкрийте першу помилку в Events і надішліть її текст. Не видаляйте stack і не повторюйте команду навмання.

Після CREATE_COMPLETE поверніться до CloudShell:

```bash
bash scripts/aws-outputs.sh
```

Надішліть весь JSON асистенту. Це URLs і resource IDs, не паролі. Асистент встановить GitHub variables та запустить workflow. Не копіюйте Secrets Manager secret values у чат.

## Етап 4 — перша публікація

Асистент налаштовує GitHub repository variables за outputs, потім запускає **Actions → Check and deploy Spry → Run workflow → main**. CI перевіряє код, отримує temporary OIDC credentials, будує SHA-tagged backend image, виконує Alembic migration окремим task і запускає 1 Fargate web task. Потім публікує frontend і invalidates CloudFront cache.

Після цього перевірте `FrontendUrl` і `BackendHealthUrl` з outputs. На головній сторінці додайте зустріч і перезавантажте її. До завершення першого deploy CloudFront може показувати 403/502/503: bucket ще порожній і ECS desired count дорівнює 0.

Наступний push main повторює deployment. Ручний Run workflow на main теж підтримується; готовий immutable image того самого SHA повторно використовується.

## Тимчасова адреса без власного домену

CloudFront надає HTTPS-адресу `https://…cloudfront.net`. Frontend і API ділять один origin: UI на `/`, API на `/api/meetings`, перевірка на `/health`. Запити API не кешуються. S3 private, CloudFront читає його через OAC.

У цьому тимчасовому варіанті CloudFront → ALB використовує HTTP; секретний origin header обмежує прямі запити до ALB, але не замінює шифрування. Це проміжний навчальний варіант для демонстраційних даних. **Вимоги власного домену та ALB HTTPS listener ще не закриті.** Після появи домену використаємо окремі `app.DOMAIN` та `api.DOMAIN`, ACM і ALB 443. З'єднання backend → RDS уже використовує TLS із перевіркою CA та hostname.

## Пізніше: власний домен

Template має 4 параметри: `FrontendDomain`, `BackendDomain`, `FrontendCertificateArn`, `BackendCertificateArn`. Заповнювати треба всі разом. Frontend certificate — ACM us-east-1, backend certificate — ACM eu-north-1. Спершу ACM validation CNAME, потім routing CNAME/ALIAS для app/api.

Не оновлюйте stack початковим template без плану: його ECS DesiredCount=0 і bootstrap TaskDefinition призначені для першого старту. Перед domain update асистент підготує update-template, який збереже актуальні task definition/image і desired count, та оновить GitHub VITE_API_URL. Після DNS/cert changes потрібен redeploy frontend і backend CORS.

## Після захисту

Зупинка ECS не прибирає вартість ALB/RDS. Для повного teardown потрібен окремий контрольований крок. Видалення stack залишає S3 bucket/objects, ECR images, database secret і фінальний RDS snapshot, щоб не втратити дані; їх потрібно прибрати окремо, коли вони більше не потрібні. Не видаляйте спільний GitHub OIDC provider. Асистент допоможе перевірити список ресурсів перед видаленням.

## Офіційні довідки

- [CloudShell: запуск і завантаження файлу](https://docs.aws.amazon.com/cloudshell/latest/userguide/getting-started.html)
- [CloudFront → ALB: обмеження доступу](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/restrict-access-to-load-balancer.html)
- [TLS для RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
