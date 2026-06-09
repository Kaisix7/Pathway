from django.db import migrations


def repair_auth_columns(apps, schema_editor):
    table_name = 'core_appuser'
    with schema_editor.connection.cursor() as cursor:
        existing_columns = {
            column.name
            for column in schema_editor.connection.introspection.get_table_description(cursor, table_name)
        }

    statements = []
    if 'role' not in existing_columns:
        statements.append("ALTER TABLE core_appuser ADD COLUMN role varchar(20) NOT NULL DEFAULT 'user'")
    if 'password_hash' not in existing_columns:
        statements.append("ALTER TABLE core_appuser ADD COLUMN password_hash varchar(255) NOT NULL DEFAULT ''")
    if 'google_id' not in existing_columns:
        statements.append("ALTER TABLE core_appuser ADD COLUMN google_id varchar(255) NOT NULL DEFAULT ''")

    for statement in statements:
        schema_editor.execute(statement)

    schema_editor.execute("CREATE INDEX IF NOT EXISTS appuser_email_idx ON core_appuser (email)")
    schema_editor.execute("CREATE INDEX IF NOT EXISTS appuser_created_idx ON core_appuser (created_at)")


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0009_add_auth_fields_to_appuser'),
    ]

    operations = [
        migrations.RunPython(repair_auth_columns, migrations.RunPython.noop),
    ]
