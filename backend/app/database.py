from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import database_url

engine = create_engine(database_url(), pool_pre_ping=True, connect_args={"connect_timeout": 5})
SessionLocal = sessionmaker(bind=engine)


class Base(DeclarativeBase):
    pass


def get_session():
    with SessionLocal() as session:
        try:
            yield session
        except Exception:
            session.rollback()
            raise
