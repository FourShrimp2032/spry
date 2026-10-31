# Non-secret values only. google_client_secret is a sensitive variable in the HCP Terraform
# workspace spry-dev.

cognito_domain_prefix = "spry-fourshrimp"
google_client_id      = "329595439342-r7cm8ulo0ate0j5rjsc3uikalhvvkbvo.apps.googleusercontent.com"

# The image the ECS service runs (CI pushes one per commit). The report builder and the agenda
# parser run it with other entry points; a new image reaches them through a pull request here.
backend_image = "751501312355.dkr.ecr.eu-north-1.amazonaws.com/spry-lab-repository-z9icrgeullmp:6fdc767c3181b7bc53c2b4299f65117537d90307"

# The database subnets: their route table has no route to an internet gateway.
private_subnet_ids      = ["subnet-0c56e2f7462370036", "subnet-06362baeb0feeb2a8"]
private_route_table_ids = ["rtb-0374d2e5252ce97ea"]

db_host       = "spry-lab-database-4dr8stcwpmhw.c7eq8c2e0c6q.eu-north-1.rds.amazonaws.com"
db_user       = "spryadmin"
db_secret_arn = "arn:aws:secretsmanager:eu-north-1:751501312355:secret:DatabaseSecret-3PWVHmTm68BT-BTnRyR"

mail_domain = "antonyivaso.dynv6.net"
recipients  = ["antonenko.pn@ucu.edu.ua"]

# Claude's quota on this account is 0 until AWS Support lifts it (ADR 0006).
parser_model = "us.amazon.nova-pro-v1:0"

budget_email = "antonenko.pn@ucu.edu.ua"
