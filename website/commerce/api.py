from accounts.auth import api_login_required
from common.jsonapi import ApiError, api_endpoint, json_response
from common.ratelimit import enforce

from . import services
from .models import PaymentPurchase
from .providers import ProviderError


def serialize_purchase(purchase):
    return {
        "id": str(purchase.id),
        "provider": purchase.provider,
        "status": purchase.status,
        "amount": purchase.amount,
        "currency": purchase.currency,
        "purchased_at": purchase.purchased_at.isoformat()
        if purchase.purchased_at
        else None,
        "created_at": purchase.created_at.isoformat(),
    }


@api_endpoint(["POST"])
@api_login_required
def checkout(request):
    enforce(request, "checkout", scope=f"user:{request.api_user.pk}")

    owns = request.api_user.purchases.filter(
        status=PaymentPurchase.Status.COMPLETED
    ).exists()
    if owns:
        raise ApiError(409, "already_owned", "This account already owns a license.")

    try:
        purchase, checkout_session = services.start_purchase(request.api_user)
    except ProviderError as exc:
        raise ApiError(503, "checkout_unavailable", str(exc))

    return json_response(
        {
            "checkout_url": checkout_session.url,
            "purchase_id": str(purchase.id),
        }
    )


@api_endpoint(["GET"])
@api_login_required
def purchases(request):
    items = request.api_user.purchases.order_by("-created_at")
    return json_response({"purchases": [serialize_purchase(p) for p in items]})
