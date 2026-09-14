from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect, render
from django.views.decorators.http import require_POST

from . import services


@login_required
def license_view(request):
    license_obj = services.license_for(request.user)
    installations = request.user.installations.order_by("-last_seen_at")
    return render(
        request,
        "licensing/license.html",
        {"license": license_obj, "installations": installations},
    )


@login_required
@require_POST
def revoke_installation_view(request, installation_id):
    if services.revoke_installation(request.user, installation_id):
        messages.success(request, "Installation revoked.")
    else:
        messages.error(request, "That installation could not be found.")
    return redirect("licensing:license")
