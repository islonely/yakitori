from django.urls import path

from . import views

app_name = "social"

urlpatterns = [
    path("y/<str:username>/followers/", views.followers_page, name="followers"),
    path("y/<str:username>/following/", views.following_page, name="following"),
    path("y/<str:username>/follow/", views.follow_toggle, name="follow-toggle"),
]
