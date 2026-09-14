from django.urls import path

from . import views

app_name = "licensing"

urlpatterns = [
    path("dashboard/license/", views.license_view, name="license"),
    path(
        "dashboard/license/installations/<uuid:installation_id>/revoke/",
        views.revoke_installation_view,
        name="revoke-installation",
    ),
]
