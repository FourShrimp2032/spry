"""Store a meeting's agenda and what the AI suggested for it."""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("meetings", sa.Column("agenda", postgresql.JSONB(), nullable=True))
    # The parser's suggestion, model and prompt version, kept next to what the user saved.
    op.add_column("meetings", sa.Column("ai_suggestion", postgresql.JSONB(), nullable=True))


def downgrade():
    op.drop_column("meetings", "ai_suggestion")
    op.drop_column("meetings", "agenda")
