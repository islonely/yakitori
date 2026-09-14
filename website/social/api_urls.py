from django.urls import path

from . import api

app_name = "social-api"

urlpatterns = [
    path("users/<str:username>/follow", api.follow_user, name="follow"),
    path("users/<str:username>/followers", api.followers, name="followers"),
    path("users/<str:username>/following", api.following, name="following"),
    path("users/<str:username>/block", api.block_user, name="block"),
    path("users/<str:username>/report", api.report_user, name="report"),
]
