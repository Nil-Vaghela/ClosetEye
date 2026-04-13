"""Add ai_suggestions table

Revision ID: f6a8b0c2d3e5
Revises: e5f7a9d1b2c4
Create Date: 2026-04-12 19:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'f6a8b0c2d3e5'
down_revision: Union[str, None] = 'e5f7a9d1b2c4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'ai_suggestions',
        sa.Column('id',             postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('owner_id',       postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('suggestions',    postgresql.JSONB(),             nullable=False, server_default='[]'),
        sa.Column('occasion',       sa.String(100),                 nullable=True),
        sa.Column('season',         sa.String(50),                  nullable=True),
        sa.Column('wardrobe_hash',  sa.String(64),                  nullable=True),
        sa.Column('is_stale',       sa.Boolean(),                   nullable=False, server_default='false'),
        sa.Column('generated_at',   sa.DateTime(timezone=True),     nullable=False, server_default=sa.text('now()')),
        sa.Column('updated_at',     sa.DateTime(timezone=True),     nullable=False, server_default=sa.text('now()')),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('owner_id'),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_ai_suggestions_owner_id', 'ai_suggestions', ['owner_id'])


def downgrade() -> None:
    op.drop_index('ix_ai_suggestions_owner_id', table_name='ai_suggestions')
    op.drop_table('ai_suggestions')
