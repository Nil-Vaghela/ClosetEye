"""Add outfit engine tables: daily_outfits, outfit_history, outfit_feedback,
user_style_preferences, notification_logs

Revision ID: h7i9j1k3l5m7
Revises: f6a8b0c2d3e5
Create Date: 2026-04-12 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'h7i9j1k3l5m7'
down_revision: Union[str, None] = 'f6a8b0c2d3e5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(conn, table_name: str) -> bool:
    inspector = sa.inspect(conn)
    return table_name in inspector.get_table_names()


def upgrade() -> None:
    conn = op.get_bind()

    if not _table_exists(conn, 'daily_outfits'):
        op.create_table(
            'daily_outfits',
            sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('outfit_date', sa.Date(), nullable=False),
            sa.Column('occasion', sa.String(50), nullable=True),
            sa.Column('weather_temp_c', sa.Float(), nullable=True),
            sa.Column('weather_condition', sa.String(100), nullable=True),
            sa.Column('weather_location', sa.String(255), nullable=True),
            sa.Column('outfits_json', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='[]'),
            sa.Column('generated_at', sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_daily_outfits_user_id', 'daily_outfits', ['user_id'])
        op.create_index('ix_daily_outfits_outfit_date', 'daily_outfits', ['outfit_date'])

    if not _table_exists(conn, 'outfit_history'):
        op.create_table(
            'outfit_history',
            sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('outfit_id', postgresql.UUID(as_uuid=True), nullable=True),
            sa.Column('items_snapshot', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'),
            sa.Column('item_ids', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='[]'),
            sa.Column('worn_date', sa.Date(), nullable=False),
            sa.Column('occasion', sa.String(50), nullable=True),
            sa.Column('note', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.ForeignKeyConstraint(['outfit_id'], ['outfits.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_outfit_history_user_id', 'outfit_history', ['user_id'])
        op.create_index('ix_outfit_history_worn_date', 'outfit_history', ['worn_date'])

    if not _table_exists(conn, 'outfit_feedback'):
        op.create_table(
            'outfit_feedback',
            sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('daily_outfit_id', postgresql.UUID(as_uuid=True), nullable=True),
            sa.Column('item_ids', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='[]'),
            sa.Column('color_pair', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='[]'),
            sa.Column('category_pair', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='[]'),
            sa.Column('feedback', sa.String(10), nullable=False),
            sa.Column('reason', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.ForeignKeyConstraint(['daily_outfit_id'], ['daily_outfits.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_outfit_feedback_user_id', 'outfit_feedback', ['user_id'])

    if not _table_exists(conn, 'user_style_preferences'):
        op.create_table(
            'user_style_preferences',
            sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('color_pair_weights', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'),
            sa.Column('category_weights', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'),
            sa.Column('occasion_counts', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'),
            sa.Column('total_likes', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('total_dislikes', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('user_id'),
        )

    if not _table_exists(conn, 'notification_logs'):
        op.create_table(
            'notification_logs',
            sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column('notification_type', sa.String(50), nullable=False),
            sa.Column('title', sa.String(255), nullable=False),
            sa.Column('message', sa.Text(), nullable=False),
            sa.Column('payload', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default='{}'),
            sa.Column('sent_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
            sa.Column('is_read', sa.Boolean(), nullable=False, server_default='false'),
            sa.ForeignKeyConstraint(['user_id'], ['users.id']),
            sa.PrimaryKeyConstraint('id'),
        )
        op.create_index('ix_notification_logs_user_id', 'notification_logs', ['user_id'])


def downgrade() -> None:
    for tbl in ['notification_logs', 'user_style_preferences', 'outfit_feedback', 'outfit_history', 'daily_outfits']:
        try:
            op.drop_table(tbl)
        except Exception:
            pass
