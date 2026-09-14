from django.urls import path

from . import views

app_name = "dashboard"

urlpatterns = [
    path("", views.home, name="home"),
    path("tokens/<uuid:token_id>/revoke/", views.revoke_token, name="revoke-token"),
    path("tokens/revoke-all/", views.revoke_all_tokens_view, name="revoke-all-tokens"),
]
