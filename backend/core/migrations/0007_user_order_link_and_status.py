from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0006_appevent_appuser_otp_code_appuser_otp_expires_at_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='appuser',
            name='plan',
            field=models.CharField(default='free', max_length=20),
        ),
        migrations.AddField(
            model_name='airportorder',
            name='user',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='orders',
                to='core.appuser',
            ),
        ),
        migrations.AddField(
            model_name='airportorder',
            name='user_email',
            field=models.EmailField(blank=True, max_length=254),
        ),
        migrations.AlterField(
            model_name='airportorder',
            name='order_status',
            field=models.CharField(
                choices=[
                    ('pending', 'Pending'),
                    ('done', 'Done'),
                    ('cancelled', 'Cancelled'),
                ],
                default='pending',
                max_length=50,
            ),
        ),
    ]
