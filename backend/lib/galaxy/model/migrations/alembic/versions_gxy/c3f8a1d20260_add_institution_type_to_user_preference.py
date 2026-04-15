"""Add institution_type column to user_preference table

Revision ID: c3f8a1d20260
Revises: fb16d09348db
Create Date: 2026-04-12 00:00:00.000000

institution_type stores the user's organisation category, chosen during
registration/profile setup.  Allowed values (enforced at the API layer):
  academic | pharma | biotech | hospital | cro | other
"""

import sqlalchemy as sa

from galaxy.model.migrations.util import (
    add_column,
    drop_column,
)

# revision identifiers, used by Alembic.
revision = "c3f8a1d20260"
down_revision = "fb16d09348db"
branch_labels = None
depends_on = None

# database object names used in this revision
table_name = "user_preference"
column_name = "institution_type"


def upgrade():
    column = sa.Column(
        column_name,
        sa.Unicode(32),
        nullable=True,
        default=None,
    )
    add_column(table_name, column)


def downgrade():
    drop_column(table_name, column_name)
