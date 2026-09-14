from django.urls import path

from . import views

app_name = "profiles"

urlpatterns = [
    path("y/<str:username>/", views.public_profile, name="public-profile"),
    path("dashboard/profile/", views.edit_profile, name="edit"),
    path("dashboard/username/", views.change_username, name="change-username"),
    path("dashboard/privacy/", views.privacy_settings, name="privacy"),
]
