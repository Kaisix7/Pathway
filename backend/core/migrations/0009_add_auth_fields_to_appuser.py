from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0008_reliability_indexes'),
    ]

    operations = [
        migrations.AddField(
            model_name='appuser',
            name='role',
            field=models.CharField(
                choices=[('user', 'User'), ('admin', 'Admin')],
                default='user',
                max_length=20,
            ),
        ),
        migrations.AddField(
            model_name='appuser',
            name='password_hash',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='appuser',
            name='google_id',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddIndex(
            model_name='appuser',
            index=models.Index(fields=['email'], name='appuser_email_idx'),
        ),
        migrations.AddIndex(
            model_name='appuser',
            index=models.Index(fields=['created_at'], name='appuser_created_idx'),
        ),
    ]
