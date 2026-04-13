"""Add price and total_wears to clothing_items

Revision ID: d4e6f8c2a0b3
Revises: c3d5f7a9b1e2
Create Date: 2026-03-31 02:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'd4e6f8c2a0b3'
down_revision: Union[str, None] = 'c3d5f7a9b1e2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = {c['name'] for c in inspector.get_columns('clothing_items')}

    if 'price' not in columns:
        op.add_column('clothing_items', sa.Column('price', sa.Float(), nullable=True))

    if 'total_wears' not in columns:
        op.add_column('clothing_items', sa.Column('total_wears', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    for col in ['price', 'total_wears']:
        try:
            op.drop_column('clothing_items', col)
        except Exception:
            pass
