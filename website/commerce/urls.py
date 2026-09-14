from django.urls import path

from . import views

app_name = "commerce"

urlpatterns = [
    path("buy/", views.buy, name="buy"),
    path("buy/success/", views.success, name="success"),
    path("buy/cancel/", views.cancel, name="cancel"),
    path("buy/mock/<uuid:purchase_id>/", views.mock_checkout, name="mock-checkout"),
    path("v1/webhooks/stripe", views.stripe_webhook, name="stripe-webhook"),
]
