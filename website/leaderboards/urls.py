from django.urls import path

from . import views

app_name = "leaderboards"

urlpatterns = [
    path("leaderboards/", views.index, name="index"),
    path("leaderboards/<str:metric>/", views.board, name="board"),
]
