from django.urls import path

from . import api

app_name = "commerce-api"

urlpatterns = [
    path("checkout", api.checkout, name="checkout"),
    path("me/purchases", api.purchases, name="purchases"),
]
