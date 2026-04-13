"""Add body model fields to users table

Revision ID: b2c4e6f8a1d3
Revises: a3f9d2e1c8b7
Create Date: 2026-03-31 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = 'b2c4e6f8a1d3'
down_revision: Union[str, None] = 'a3f9d2e1c8b7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = {c['name'] for c in inspector.get_columns('users')}

    if 'body_photo_url' not in columns:
        op.add_column('users', sa.Column('body_photo_url', sa.String(512), nullable=True))

    if 'body_silhouette_url' not in columns:
        op.add_column('users', sa.Column('body_silhouette_url', sa.String(512), nullable=True))

    if 'height_cm' not in columns:
        op.add_column('users', sa.Column('height_cm', sa.Integer(), nullable=True))

    if 'weight_kg' not in columns:
        op.add_column('users', sa.Column('weight_kg', sa.Integer(), nullable=True))

    if 'body_type' not in columns:
        op.add_column('users', sa.Column('body_type', sa.String(32), nullable=True))

    if 'body_model_ready' not in columns:
        op.add_column('users', sa.Column(
            'body_model_ready', sa.Boolean(), nullable=False, server_default='false'))


def downgrade() -> None:
    for col in ['body_photo_url', 'body_silhouette_url', 'height_cm',
                'weight_kg', 'body_type', 'body_model_ready']:
        try:
            op.drop_column('users', col)
        except Exception:
            pass
