# Generated manually to avoid Python version mismatch

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0013_appuser_company_appuser_utm_campaign_and_more'),
    ]

    operations = [
        migrations.AddIndex(
            model_name='order',
            index=models.Index(fields=['user_email'], name='order_usr_email_idx'),
        ),
        migrations.AddIndex(
            model_name='order',
            index=models.Index(fields=['status'], name='order_status_idx'),
        ),
        migrations.AddIndex(
            model_name='order',
            index=models.Index(fields=['created_at'], name='order_created_at_idx'),
        ),
    ]
