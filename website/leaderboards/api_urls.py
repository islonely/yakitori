from django.urls import path

from . import api

app_name = "leaderboards-api"

urlpatterns = [
    path("leaderboards/<str:metric>", api.leaderboard_view, name="leaderboard"),
    path("leaderboards/<str:metric>/me", api.my_standing, name="my-standing"),
    path("statistics/aggregates", api.submit_statistics, name="submit-statistics"),
]
