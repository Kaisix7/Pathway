"""
URL configuration for backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import include, path, re_path
from core.views import health, metrics, frontend, _calculate_kpi_values

original_index = admin.site.index

def custom_admin_index(request, extra_context=None):
    if extra_context is None:
        extra_context = {}
    try:
        extra_context['kpis'] = _calculate_kpi_values()
    except Exception:
        extra_context['kpis'] = None
    return original_index(request, extra_context=extra_context)

admin.site.index = custom_admin_index

urlpatterns = [
    path('health', health),
    path('health/', health),
    path('metrics', metrics),
    path('metrics/', metrics),
    path('admin/', admin.site.urls),
    path('api/', include('core.urls')),
    re_path(r'^.*$', frontend),
]


