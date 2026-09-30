from app.config import database_url


def test_local_database_url_takes_precedence(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://local/test")
    assert database_url() == "postgresql+psycopg://local/test"


def test_ecs_secret_is_safely_encoded_and_rds_identity_verified(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DB_USER", "spryadmin")
    monkeypatch.setenv("DB_PASSWORD", "special:p@ss/word")
    monkeypatch.setenv("DB_HOST", "example.rds.amazonaws.com")
    url = database_url()
    assert url.password == "special:p@ss/word"
    assert url.query["sslmode"] == "verify-full"
    assert url.query["sslrootcert"].endswith("/rds-ca.pem")
    assert "special" not in str(url)
