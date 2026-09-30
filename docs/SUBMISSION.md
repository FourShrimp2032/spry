# Матеріали для здачі

- Repository: https://github.com/FourShrimp2032/spry (private).
- Frontend HTTPS: https://d310vkwtz8a1f0.cloudfront.net
- Backend HTTPS: https://d310vkwtz8a1f0.cloudfront.net/api/meetings
- Health: https://d310vkwtz8a1f0.cloudfront.net/health
- Screenshot реального AWS frontend: [meetings-screenshot.jpg](meetings-screenshot.jpg).
- [Успішний deploy через OIDC](https://github.com/FourShrimp2032/spry/actions/runs/36727682803/attempts/2).

## Виконано

- [x] Клон course repository зі збереженням Git history, власний GitHub repository.
- [x] PROJECT.md перед генерацією коду, monorepo, Docker Compose, API та UI.
- [x] Перевірено створення зустрічей та збереження після reload локально й на AWS.
- [x] Ruff, ESLint, Prettier, 14 backend tests, frontend build, infrastructure validation.
- [x] Навмисно невдалий lint [red](https://github.com/FourShrimp2032/spry/actions/runs/36719971295) і [green після виправлення](https://github.com/FourShrimp2032/spry/actions/runs/36720151761).
- [x] S3/CloudFront, ECR/ECS Fargate/ALB, private RDS, OIDC для конкретного repository/main, Makefile deploy.
- [x] HTTPS на тимчасовій AWS адресі, screenshot із трьома демонстраційними зустрічами.

## Для повної відповідності завданню

- [ ] Власний домен із DNS/ACM, окремі app/api адреси та ALB HTTPS listener. Наразі власного домену немає; CloudFront → ALB використовує HTTP з обмеженням за secret origin header. Це не виконання вимоги own domain.
- [ ] Доступ викладача до private repository — потрібен його GitHub username.
- [ ] Точне порівняння дизайну з Lab 1 — reference image не надано.

Подальший push до main автоматично запускає перевірки й deployment. Ресурси AWS залишаються активними та можуть тарифікуватися; teardown описано у [AWS.md](AWS.md).
