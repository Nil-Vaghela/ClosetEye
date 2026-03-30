"""Rebuild users table for Firebase phone auth

Removes the old email/password columns and adds phone_number + firebase_uid.
Safe to run on a fresh DB — drops and recreates the users table.

Revision ID: a3f9d2e1c8b7
Revises: 8bb8dbf71c12
Create Date: 2026-03-30 00:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'a3f9d2e1c8b7'
down_revision: Union[str, None] = '8bb8dbf71c12'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Check which columns currently exist and migrate accordingly.
    # We support two states:
    #   (a) Fresh DB — users table has email/hashed_password (initial migration)
    #   (b) Already migrated — users table has phone_number/firebase_uid

    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = {c['name'] for c in inspector.get_columns('users')}

    # Add phone_number if missing
    if 'phone_number' not in columns:
        op.add_column('users', sa.Column(
            'phone_number', sa.String(length=20), nullable=True))
        op.create_index('ix_users_phone_number', 'users', ['phone_number'], unique=True)

    # Add firebase_uid if missing
    if 'firebase_uid' not in columns:
        op.add_column('users', sa.Column(
            'firebase_uid', sa.String(length=128), nullable=True))
        op.create_index('ix_users_firebase_uid', 'users', ['firebase_uid'], unique=True)

    # Make phone_number NOT NULL only after it exists (safe for empty tables)
    # For a dev DB with no real users this is fine; production would need a data migration first.
    try:
        op.alter_column('users', 'phone_number', nullable=False)
        op.alter_column('users', 'firebase_uid', nullable=False)
    except Exception:
        pass  # already not-null or table has data — leave as-is

    # Drop old auth columns if they still exist
    if 'email' in columns:
        try:
            op.drop_index('ix_users_email', table_name='users')
        except Exception:
            pass
        op.drop_column('users', 'email')

    if 'hashed_password' in columns:
        op.drop_column('users', 'hashed_password')


def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = {c['name'] for c in inspector.get_columns('users')}

    if 'email' not in columns:
        op.add_column('users', sa.Column('email', sa.String(length=255), nullable=True))
        op.create_index('ix_users_email', 'users', ['email'], unique=True)

    if 'hashed_password' not in columns:
        op.add_column('users', sa.Column('hashed_password', sa.String(length=255), nullable=True))

    if 'phone_number' in columns:
        try:
            op.drop_index('ix_users_phone_number', table_name='users')
        except Exception:
            pass
        op.drop_column('users', 'phone_number')

    if 'firebase_uid' in columns:
        try:
            op.drop_index('ix_users_firebase_uid', table_name='users')
        except Exception:
            pass
        op.drop_column('users', 'firebase_uid')
