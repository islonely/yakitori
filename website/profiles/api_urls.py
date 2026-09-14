from django.urls import path

from . import api

app_name = "profiles-api"

urlpatterns = [
    path("users/<str:username>", api.user_detail, name="user-detail"),
    path("me/profile", api.my_profile, name="my-profile"),
    path("me/username", api.change_my_username, name="my-username"),
]
