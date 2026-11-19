"""users.avatar_url (AI digital twin for try-on)

Revision ID: k1m3n5p7q9r1
Revises: j9k1l3m5n7p9
"""
from typing import Sequence, Union

from alembic import op

revision: str = "k1m3n5p7q9r1"
down_revision: Union[str, None] = "j9k1l3m5n7p9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url VARCHAR(512)")


def downgrade() -> None:
    op.drop_column("users", "avatar_url")
