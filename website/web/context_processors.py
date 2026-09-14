from django.conf import settings


def platform(request):
    """Values every template can rely on.

    Kept deliberately small: branding, product policy, and whether the current
    request is in the authenticated account area (for navigation).
    """
    return {
        "platform_name": settings.PLATFORM_NAME,
        "product_name": settings.PRODUCT_NAME,
        "product_price_amount": settings.PRODUCT_PRICE_AMOUNT,
        "product_price_currency": settings.PRODUCT_PRICE_CURRENCY,
        "product_currency_symbol": "$"
        if settings.PRODUCT_PRICE_CURRENCY.lower() == "usd"
        else settings.PRODUCT_PRICE_CURRENCY.upper(),
        "license_offline_grace_days": settings.LICENSE_OFFLINE_GRACE_DAYS,
    }
