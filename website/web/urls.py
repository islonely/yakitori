from django.urls import path

from . import views

app_name = "web"

urlpatterns = [
    path("", views.home, name="home"),
    path("pricing/", views.pricing, name="pricing"),
    path("download/", views.download, name="download"),
    path("support/", views.support, name="support"),
    path("privacy/", views.privacy_policy, name="privacy"),
    path("terms/", views.terms, name="terms"),
]
