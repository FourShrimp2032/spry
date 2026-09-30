import os
from pathlib import Path

from sqlalchemy.engine import URL


def database_url():
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    # ECS injects the password directly from Secrets Manager. URL.create safely
    # handles reserved characters without ever printing a connection string.
    return URL.create(
        "postgresql+psycopg",
        username=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        host=os.environ["DB_HOST"],
        port=int(os.getenv("DB_PORT", "5432")),
        database=os.getenv("DB_NAME", "spry"),
        query={
            "sslmode": os.getenv("DB_SSLMODE", "verify-full"),
            "sslrootcert": str(Path(__file__).resolve().parent.parent / "rds-ca.pem"),
        },
    )
