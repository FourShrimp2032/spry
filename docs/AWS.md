# AWS deployment runbook

Це інструкція налаштування, а не доказ створених ресурсів. Потрібні AWS account, MFA, адміністративний доступ для bootstrap, GitHub repo та контроль DNS власного домену. Довготривалі ключі не комітити. Локально краще AWS SSO/profile; GitHub використовує OIDC.

## 1. Мережа і PostgreSQL
Обраний AWS region: `eu-north-1` (Stockholm). Створіть VPC із двома AZ, public subnets для ALB і private subnets для RDS. Створіть PostgreSQL 16 RDS database `spry` з encryption, backups і без public access. DB security group дозволяє 5432 тільки від backend security group. Backend SG дозволяє 8000 тільки від ALB SG; ALB SG — 80/443 з internet.

ECS tasks можна розмістити у private subnets із NAT/VPC endpoints для ECR, S3, CloudWatch та Secrets Manager. Дешевший lab варіант — public subnets із public IP, але inbound усе одно тільки від ALB SG. Для нього задайте `ECS_ASSIGN_PUBLIC_IP=ENABLED`. За замовчуванням scripts використовують DISABLED.

Створіть Secrets Manager secret зі звичайним рядком DATABASE_URL:
`postgresql+psycopg://USER:URL_ENCODED_PASSWORD@RDS_HOST:5432/spry?sslmode=require`.
Database password у URI обов'язково URL-encode. Для повної server identity verification у production додайте RDS CA bundle в образ і `sslmode=verify-full`.

## 2. Registry, roles, logs, ECS
Створіть ECR repo `spry` з tag immutability і vulnerability scanning; CloudWatch log group `/ecs/spry` з retention. Execution role довіряє `ecs-tasks.amazonaws.com`, має AmazonECSTaskExecutionRolePolicy і `secretsmanager:GetSecretValue` тільки на database secret (та KMS decrypt на конкретний key, якщо customer-managed). Застосунку AWS API не потрібен, тому task role можна не створювати.

Підставте значення у `infra/task-definition.json`. Створіть ECS cluster і task definition. Створіть IP target group port 8000, HTTP health path `/health`, success code 200. Створіть ALB у двох public subnets, HTTPS listener 443 і HTTP 80 redirect на HTTPS. ECS service: Fargate, desired count 1, target group/container backend:8000, health grace period 60 секунд, deployment circuit breaker з rollback. Не запускайте production міграції через container startup command.

Для першого запуску спочатку завантажте backend image з SHA першого коміту у ECR, зареєструйте task definition і створіть service з desired count 0. Запустіть `make deploy-backend`: він запустить migration task і оновить definition. Потім підніміть desired count до 1 і дочекайтеся healthy target. Подальші deploy працюють зі збереженим desired count.

## 3. Private S3 і CloudFront
Створіть S3 bucket із Block Public Access та Bucket owner enforced. CloudFront: REST S3 origin (не website), Origin Access Control з SigV4 signing, default root object `index.html`, viewer protocol redirect-to-https, compression on. Alias `app.YOUR_DOMAIN`.

Шаблон: `infra/cloudfront-bucket-policy.json`. Bucket policy має дозволяти `s3:GetObject` на `arn:aws:s3:::BUCKET/*` лише service principal `cloudfront.amazonaws.com` за умови `AWS:SourceArn == arn:aws:cloudfront::ACCOUNT:distribution/DISTRIBUTION_ID`. Public read не потрібен. Поточний односторінковий застосунок використовує тільки `/`, SPA route fallback не потрібен.

## 4. DNS та certificates
ACM certificate для CloudFront замовляється у `us-east-1`, для ALB — у region ALB. Додайте ACM validation CNAME записи та дочекайтеся Issued. Прикріпіть cert до CloudFront і ALB 443 listener. Додайте routing CNAME/Route53 Alias: `app` → CloudFront, `api` → ALB. Validation records залиште для автоматичного renew. Перевірте HTTPS, DNS та redirect 80→443.

CORS_ORIGINS у task definition має дорівнювати `https://app.YOUR_DOMAIN` без trailing slash. `VITE_API_URL=https://api.YOUR_DOMAIN` задається під час frontend build і доступний публічно; це не місце для секретів.

## 5. GitHub OIDC і permissions
Створіть IAM OIDC provider `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`. Створіть deploy role із trust template `infra/github-oidc-trust.json`. Замініть ACCOUNT_ID; repo вже обмежено до FourShrimp2032/spry. Exact `sub` дозволяє лише main саме вашого repo; wildcard за repo не допускається.

Прикріпіть `infra/github-deploy-policy.json`, замінивши placeholders і назви ресурсів на створені. У ньому такі мінімальні дії й обмеження:
- `ecr:GetAuthorizationToken` на `*`; upload layer, check layer, PutImage на конкретний ECR repo.
- `ecs:DescribeTaskDefinition`, `ecs:RegisterTaskDefinition` (де API не підтримує resource scoping — `*`).
- `ecs:RunTask` на `spry-backend:*` із condition конкретного cluster; `ecs:DescribeTasks` на tasks свого cluster.
- `ecs:UpdateService`, `ecs:DescribeServices` тільки конкретного service.
- `iam:PassRole` тільки task execution role (і task role, якщо додано), condition `iam:PassedToService=ecs-tasks.amazonaws.com`.
- `s3:ListBucket` на frontend bucket; `s3:GetObject`, `s3:PutObject` на його objects.
- `cloudfront:CreateInvalidation` на свою distribution.

Deploy role не потребує читання database secret: secret читає task execution role.

## 6. Repository variables
Задайте GitHub Settings → Secrets and variables → Actions → Variables:
`AWS_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `TASK_FAMILY`, `ECS_SUBNETS` (comma-separated subnet IDs), `ECS_SECURITY_GROUP`, `ECS_ASSIGN_PUBLIC_IP` (ENABLED/DISABLED), `FRONTEND_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID`, `VITE_API_URL`.

Локально export ті самі variables (окрім AWS_ROLE_ARN), виконайте AWS login/configure і запускайте Makefile. Потрібні AWS CLI v2, Docker buildx, Python 3, Node/npm, Git та Make.

На push main workflow чекає green checks, отримує temporary credentials, запускає той самий Makefile. Backend deploy будує linux/amd64 image із SHA, пушить, реєструє нову task revision, запускає окрему migration, перевіряє exit code, оновлює ECS service і чекає stable. Frontend deploy публікує immutable hashed assets, потім index, тоді invalidation. Старі assets не видаляються одразу, щоб відкриті вкладки не зламались.

## 7. Перевірка й rollback
Перевірте `https://api.YOUR_DOMAIN/health`, GET list, створення через HTTPS UI та reload. Перевірте latest workflow, task image SHA і CloudWatch logs. Зробіть скриншот реального списку. Rollback backend — update service на попередній task definition із відомим SHA, потім wait stable; schema має залишатися сумісною. Frontend rollback — rebuild попереднього commit і ті самі S3/CloudFront операції. Для першої destructive schema migration rollback треба планувати окремо.

## 8. Вартість і teardown
RDS, Fargate, ALB, NAT і public IPv4 можуть коштувати навіть без трафіку. Перед створенням встановіть AWS Budget. Після захисту збережіть потрібні дані й видаліть service/tasks, ALB/listeners/target groups, RDS (snapshot за потреби), CloudFront (спершу disable), S3 objects/bucket, ECR images/repo, log group, secret, roles, NAT/endpoints, зайві IP і VPC. DNS записи та ACM certificates очищайте тільки якщо вони більше ніде не використовуються. Перевірте Billing після видалення.

Офіційні довідки: https://docs.aws.amazon.com/cli/latest/reference/ecs/run-task.html ; https://vite.dev/guide/static-deploy.html ; https://fastapi.tiangolo.com/deployment/docker/ .
