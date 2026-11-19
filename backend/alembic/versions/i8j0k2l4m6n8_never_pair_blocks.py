"""never-pair item blocks on user_style_preferences

Revision ID: i8j0k2l4m6n8
Revises: h7i9j1k3l5m7
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "i8j0k2l4m6n8"
down_revision: Union[str, None] = "h7i9j1k3l5m7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE user_style_preferences "
        "ADD COLUMN IF NOT EXISTS blocked_item_pairs JSONB NOT NULL DEFAULT '[]'::jsonb"
    )


def downgrade() -> None:
    op.drop_column("user_style_preferences", "blocked_item_pairs")
