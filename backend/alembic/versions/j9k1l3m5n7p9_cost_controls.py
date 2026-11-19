"""cost controls: ai_usage ledger + ai_cache

Revision ID: j9k1l3m5n7p9
Revises: i8j0k2l4m6n8
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "j9k1l3m5n7p9"
down_revision: Union[str, None] = "i8j0k2l4m6n8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    insp = sa.inspect(op.get_bind())
    tables = insp.get_table_names()
    if "ai_usage" not in tables:
        op.create_table(
            "ai_usage",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("user_id", postgresql.UUID(as_uuid=True),
                      sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("feature", sa.String(40), nullable=False),
            sa.Column("units", sa.Integer, nullable=False, server_default="1"),
            sa.Column("cost_estimate", sa.Float, nullable=False, server_default="0"),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_ai_usage_user_id", "ai_usage", ["user_id"])
        op.create_index("ix_ai_usage_created_at", "ai_usage", ["created_at"])
    if "ai_cache" not in tables:
        op.create_table(
            "ai_cache",
            sa.Column("key", sa.String(128), primary_key=True),
            sa.Column("value", postgresql.JSONB, nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )


def downgrade() -> None:
    op.drop_table("ai_cache")
    op.drop_table("ai_usage")
