from django.contrib import admin
from django.urls import include, path
from django.http import HttpResponse


def home(request):
    return HttpResponse("OK")


urlpatterns = [
    path("", home),
    path("admin/", admin.site.urls),
    path("api/", include("core.urls")),
]