from django.conf import settings
from django.shortcuts import render


def home(request):
    return render(
        request,
        "web/home.html",
        {
            "price_amount": settings.PRODUCT_PRICE_AMOUNT,
            "price_currency": settings.PRODUCT_PRICE_CURRENCY,
        },
    )


def pricing(request):
    return render(
        request,
        "web/pricing.html",
        {
            "price_amount": settings.PRODUCT_PRICE_AMOUNT,
            "price_currency": settings.PRODUCT_PRICE_CURRENCY,
        },
    )


def download(request):
    return render(request, "web/download.html")


def support(request):
    return render(request, "web/support.html")


def privacy_policy(request):
    return render(request, "web/privacy.html")


def terms(request):
    return render(request, "web/terms.html")
