from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0008_reliability_indexes'),
    ]

    operations = [
        migrations.AddField(
            model_name='appuser',
            name='role',
            field=models.CharField(choices=[('guest', 'Guest'), ('user', 'User'), ('admin', 'Admin')], default='guest', max_length=10),
        ),
        migrations.AddField(
            model_name='appuser',
            name='password_hash',
            field=models.CharField(blank=True, default='', max_length=128),
        ),
        migrations.AddField(
            model_name='appuser',
            name='google_sub',
            field=models.CharField(blank=True, max_length=255, null=True, unique=True),
        ),
    ]
