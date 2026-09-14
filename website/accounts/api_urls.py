from django.urls import path

from . import api

app_name = "accounts-api"

urlpatterns = [
    path("auth/device/start", api.device_start, name="device-start"),
    path("auth/device/token", api.device_token, name="device-token"),
    path("me", api.me, name="me"),
    path("me/tokens", api.tokens, name="tokens"),
    path("me/tokens/current", api.current_token, name="current-token"),
    path("me/tokens/<uuid:token_id>", api.token_detail, name="token-detail"),
]
