from django.urls import path

from . import views

app_name = "accounts"

urlpatterns = [
    path("sign-in/", views.sign_in, name="sign-in"),
    path("sign-in/sent/", views.sign_in_sent, name="sign-in-sent"),
    path("sign-in/code/", views.sign_in_code, name="sign-in-code"),
    path("sign-in/<str:token>/", views.verify_token, name="sign-in-verify"),
    path("sign-up/", views.sign_up, name="sign-up"),
    path("sign-up/sent/", views.sign_up_sent, name="sign-up-sent"),
    path("sign-out/", views.sign_out, name="sign-out"),
    path("device/", views.device_authorize, name="device-authorize"),
]
