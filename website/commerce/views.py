from django.conf import settings
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.http import Http404, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods, require_POST

from . import services
from .models import PaymentPurchase
from .providers import EventKind, ProviderError, SignatureError, get_provider


@login_required
@require_http_methods(["GET", "POST"])
def buy(request):
    # A completed purchase already grants a lifetime license; sending the buyer
    # through checkout again would be a mistake.
    owns = request.user.purchases.filter(
        status=PaymentPurchase.Status.COMPLETED
    ).exists()
    if owns:
        messages.success(request, "You already own a lifetime license.")
        return redirect("dashboard:home")

    try:
        _purchase, checkout = services.start_purchase(request.user)
    except ProviderError as exc:
        messages.error(request, f"Checkout is currently unavailable. ({exc})")
        return redirect("web:pricing")

    return redirect(checkout.url)


@login_required
@require_http_methods(["GET", "POST"])
def mock_checkout(request, purchase_id):
    provider = get_provider()
    if not provider.supports_mock_completion():
        raise Http404

    purchase = get_object_or_404(
        PaymentPurchase, pk=purchase_id, user=request.user
    )

    if request.method == "POST":
        action = request.POST.get("action")
        if action == "pay":
            services.simulate_event(purchase, EventKind.PURCHASE_COMPLETED)
            return redirect("commerce:success")
        if action == "cancel":
            if purchase.status == PaymentPurchase.Status.PENDING:
                purchase.status = PaymentPurchase.Status.CANCELLED
                purchase.save(update_fields=["status", "updated_at"])
            return redirect("commerce:cancel")

    return render(
        request,
        "commerce/mock_checkout.html",
        {
            "purchase": purchase,
            "product_name": settings.PRODUCT_NAME,
            "amount": purchase.amount,
            "currency": purchase.currency.upper(),
        },
    )


def success(request):
    return render(request, "commerce/success.html")


def cancel(request):
    return render(request, "commerce/cancel.html")


@csrf_exempt
@require_POST
def stripe_webhook(request):
    try:
        _webhook, created = services.process_webhook(request)
    except SignatureError:
        return JsonResponse({"error": "invalid_signature"}, status=400)
    except ProviderError as exc:
        return JsonResponse({"error": "provider_error", "message": str(exc)}, status=400)

    return JsonResponse({"received": True, "duplicate": not created}, status=200)
