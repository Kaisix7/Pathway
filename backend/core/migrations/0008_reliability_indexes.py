from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0007_user_order_link_and_status'),
    ]

    operations = [
        migrations.AddIndex(
            model_name='appevent',
            index=models.Index(fields=['user_email', 'event_name'], name='event_user_name_idx'),
        ),
        migrations.AddIndex(
            model_name='appevent',
            index=models.Index(fields=['created_at'], name='event_created_idx'),
        ),
        migrations.AddIndex(
            model_name='airportorder',
            index=models.Index(fields=['user_email'], name='order_user_email_idx'),
        ),
        migrations.AddIndex(
            model_name='airportorder',
            index=models.Index(fields=['created_at'], name='order_created_idx'),
        ),
        migrations.AddIndex(
            model_name='airportorder',
            index=models.Index(fields=['order_status'], name='order_status_idx'),
        ),
    ]
