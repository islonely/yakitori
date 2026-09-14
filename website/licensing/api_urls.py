from django.urls import path

from . import api

app_name = "licensing-api"

urlpatterns = [
    path("me/license", api.license_detail, name="license"),
    path("me/license/validate", api.validate, name="validate"),
    path("me/installations", api.installations, name="installations"),
    path(
        "me/installations/<uuid:installation_id>",
        api.installation_detail,
        name="installation-detail",
    ),
]
