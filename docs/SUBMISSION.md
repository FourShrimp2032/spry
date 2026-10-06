# Матеріали для здачі

Lab 3 (Cognito) — у [LAB3.md](LAB3.md#що-здати). Стан Lab 2 — тег [`lab2`](https://github.com/FourShrimp2032/spry/tree/lab2).

## Lab 2

- Repository: https://github.com/FourShrimp2032/spry (public).
- Frontend HTTPS: https://d310vkwtz8a1f0.cloudfront.net
- Backend HTTPS: https://d310vkwtz8a1f0.cloudfront.net/api/meetings
- Health: https://d310vkwtz8a1f0.cloudfront.net/health
- Screenshot реального AWS frontend: [meetings-screenshot.jpg](meetings-screenshot.jpg).
- [Успішний deploy через OIDC](https://github.com/FourShrimp2032/spry/actions/runs/36727682803/attempts/2).

### Що прикріпити у систему здачі

1. Посилання на repository вище.
2. Файл `meetings-screenshot.jpg` із цієї папки.
3. Frontend HTTPS URL та Backend HTTPS URL вище.
4. Додатково: [успішний автоматичний deploy після push](https://github.com/FourShrimp2032/spry/actions/runs/36767908459).

Поточну CloudFront адресу залишено за рішенням власника. У поясненні до здачі вкажіть, що власний домен не підключено; формальна вимога own domain поки не виконана.

### Виконано

- [x] Клон course repository зі збереженням Git history, власний GitHub repository.
- [x] PROJECT.md перед генерацією коду, monorepo, Docker Compose, API та UI.
- [x] Перевірено створення зустрічей та збереження після reload локально й на AWS.
- [x] Ruff, ESLint, Prettier, 14 backend tests, frontend build, infrastructure validation.
- [x] Навмисно невдалий lint [red](https://github.com/FourShrimp2032/spry/actions/runs/36719971295) і [green після виправлення](https://github.com/FourShrimp2032/spry/actions/runs/36720151761).
- [x] S3/CloudFront, ECR/ECS Fargate/ALB, private RDS, OIDC для конкретного repository/main, Makefile deploy.
- [x] HTTPS на тимчасовій AWS адресі, screenshot із трьома демонстраційними зустрічами.

### Для повної відповідності завданню

- [ ] Власний домен із DNS/ACM, окремі app/api адреси та ALB HTTPS listener. Наразі власного домену немає; CloudFront → ALB використовує HTTP з обмеженням за secret origin header. Це не виконання вимоги own domain.
- [x] Репозиторій публічний — викладач може відкрити його без запрошення.
- [ ] Точне порівняння дизайну з Lab 1 — reference image не надано.

Подальший push до main автоматично запускає перевірки й deployment. Ресурси AWS залишаються активними та можуть тарифікуватися; teardown описано у [AWS.md](AWS.md).
