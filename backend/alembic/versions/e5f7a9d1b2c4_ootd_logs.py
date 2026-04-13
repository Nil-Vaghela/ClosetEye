"""Add ootd_logs table

Revision ID: e5f7a9d1b2c4
Revises: d4e6f8c2a0b3
Create Date: 2026-03-31 03:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'e5f7a9d1b2c4'
down_revision: Union[str, None] = 'd4e6f8c2a0b3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'ootd_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('outfit_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('custom_item_ids', postgresql.ARRAY(postgresql.UUID(as_uuid=True)), nullable=True),
        sa.Column('logged_date', sa.Date(), nullable=False),
        sa.Column('note', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['outfit_id'], ['outfits.id'], ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_ootd_logs_user_id'), 'ootd_logs', ['user_id'], unique=False)
    op.create_index(op.f('ix_ootd_logs_logged_date'), 'ootd_logs', ['logged_date'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_ootd_logs_logged_date'), table_name='ootd_logs')
    op.drop_index(op.f('ix_ootd_logs_user_id'), table_name='ootd_logs')
    op.drop_table('ootd_logs')
