"""Create meetings with duration and attendee constraints."""

import sqlalchemy as sa

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "meetings",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attendee_count", sa.Integer(), nullable=False),
        sa.CheckConstraint("ends_at > starts_at", name="meeting_positive_duration"),
        sa.CheckConstraint("attendee_count >= 0", name="meeting_nonnegative_attendees"),
    )
    op.create_index("ix_meetings_starts_at", "meetings", ["starts_at"])


def downgrade():
    op.drop_index("ix_meetings_starts_at", table_name="meetings")
    op.drop_table("meetings")
