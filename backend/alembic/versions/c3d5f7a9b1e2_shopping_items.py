"""Add shopping_items table

Revision ID: c3d5f7a9b1e2
Revises: b2c4e6f8a1d3
Create Date: 2026-03-31 01:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = 'c3d5f7a9b1e2'
down_revision: Union[str, None] = 'b2c4e6f8a1d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Use raw SQL to reference the existing clothingcategory enum type
    # without going through SQLAlchemy's type-creation machinery.
    op.execute("""
        CREATE TABLE IF NOT EXISTS shopping_items (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            owner_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name        VARCHAR(255),
            category    clothingcategory NOT NULL,
            color_primary VARCHAR(50),
            original_image_url VARCHAR(512) NOT NULL,
            cleaned_image_url  VARCHAR(512),
            expires_at  TIMESTAMPTZ NOT NULL,
            created_at  TIMESTAMPTZ NOT NULL
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_shopping_items_owner_id
        ON shopping_items (owner_id)
    """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_shopping_items_owner_id")
    op.execute("DROP TABLE IF EXISTS shopping_items")
    # Do NOT drop clothingcategory enum — it's shared with clothing_items
