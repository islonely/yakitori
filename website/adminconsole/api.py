"""Administrative JSON API.

Authorization is server-side only: `api_admin_required` checks the authenticated
account's staff/superuser flag. An `is_admin` value supplied by a browser is
never trusted. Every mutation is audited.
"""

from django.db.models import Q
from django.utils import timezone

from accounts.auth import api_admin_required
from accounts.models import User
from audit.models import AuditEvent
from audit.services import record
from commerce import services as commerce_services
from commerce.models import PurchaseClaim, WebhookEvent
from common.jsonapi import ApiError, api_endpoint, json_body, json_response
from common.ratelimit import enforce
from licensing.models import License
from licensing.services import set_license_status
from social.models import Report


def _admin_audit(request, action, target=None, **metadata):
    record(
        AuditEvent.Type.ADMIN_ACTION,
        actor=request.api_user,
        target=target,
        source="admin-api",
        action=action,
        **metadata,
    )


def _get_or_404(model, pk, label):
    obj = model.objects.filter(pk=pk).first()
    if obj is None:
        raise ApiError(404, "not_found", f"No such {label}.")
    return obj


def _serialize_user(user):
    profile = getattr(user, "profile", None)
    return {
        "id": str(user.pk),
        "email": user.email,
        "status": user.status,
        "username": profile.username if profile else None,
        "created_at": user.created_at.isoformat(),
    }


@api_endpoint(["GET"])
@api_admin_required
def users(request):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    query = request.GET.get("q", "").strip()
    queryset = User.objects.select_related("profile").order_by("-created_at")
    if query:
        queryset = queryset.filter(
            Q(email__icontains=query)
            | Q(email_normalized__icontains=query)
            | Q(profile__username__icontains=query)
            | Q(profile__display_name__icontains=query)
        )
    return json_response({"users": [_serialize_user(u) for u in queryset[:50]]})


@api_endpoint(["GET"])
@api_admin_required
def user_detail(request, user_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    user = _get_or_404(User, user_id, "user")

    licenses = [
        {
            "id": str(item.id),
            "product": item.product,
            "status": item.status,
            "license_type": item.license_type,
        }
        for item in user.licenses.all()
    ]
    purchases = [
        {
            "id": str(item.id),
            "provider": item.provider,
            "status": item.status,
            "amount": item.amount,
            "currency": item.currency,
        }
        for item in user.purchases.all()
    ]
    installations = [
        {
            "installation_id": str(item.installation_id),
            "app_version": item.app_version,
            "last_seen_at": item.last_seen_at.isoformat(),
            "revoked": item.revoked_at is not None,
        }
        for item in user.installations.all()
    ]
    claims = [
        {
            "id": str(item.id),
            "status": item.status,
            "purchase": str(item.purchase_id),
        }
        for item in user.purchase_claims.all()
    ]

    return json_response(
        {
            "user": _serialize_user(user),
            "licenses": licenses,
            "purchases": purchases,
            "installations": installations,
            "claims": claims,
        }
    )


@api_endpoint(["POST"])
@api_admin_required
def suspend_user(request, user_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    user = _get_or_404(User, user_id, "user")
    if user.pk == request.api_user.pk:
        raise ApiError(400, "cannot_suspend_self", "You cannot suspend yourself.")

    user.status = User.Status.SUSPENDED
    user.save(update_fields=["status", "is_active", "updated_at"])

    record(AuditEvent.Type.ACCOUNT_SUSPENDED, actor=request.api_user, target=user, source="admin-api")
    _admin_audit(request, "user_suspend", target=user)
    return json_response({"user": _serialize_user(user)})


@api_endpoint(["POST"])
@api_admin_required
def unsuspend_user(request, user_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    user = _get_or_404(User, user_id, "user")
    user.status = User.Status.ACTIVE
    user.deleted_at = None
    user.save(update_fields=["status", "deleted_at", "is_active", "updated_at"])

    _admin_audit(request, "user_unsuspend", target=user)
    return json_response({"user": _serialize_user(user)})


@api_endpoint(["POST"])
@api_admin_required
def revoke_license(request, license_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    license_obj = _get_or_404(License, license_id, "license")
    set_license_status(
        license_obj,
        License.Status.REVOKED,
        actor=request.api_user,
        reason="admin",
        source="admin-api",
    )
    _admin_audit(request, "license_revoke", target=license_obj.user, license=str(license_obj.id))
    return json_response({"license": {"id": str(license_obj.id), "status": license_obj.status}})


@api_endpoint(["POST"])
@api_admin_required
def restore_license(request, license_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    license_obj = _get_or_404(License, license_id, "license")
    set_license_status(
        license_obj,
        License.Status.ACTIVE,
        actor=request.api_user,
        source="admin-api",
    )
    _admin_audit(request, "license_restore", target=license_obj.user, license=str(license_obj.id))
    return json_response({"license": {"id": str(license_obj.id), "status": license_obj.status}})


@api_endpoint(["GET"])
@api_admin_required
def webhooks(request):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    status = request.GET.get("status")
    queryset = WebhookEvent.objects.all()
    if status:
        queryset = queryset.filter(status=status)
    items = [
        {
            "external_id": item.external_id,
            "provider": item.provider,
            "event_type": item.event_type,
            "status": item.status,
            "received_at": item.received_at.isoformat(),
            "processed_at": item.processed_at.isoformat() if item.processed_at else None,
        }
        for item in queryset[:100]
    ]
    return json_response({"webhooks": items})


@api_endpoint(["GET"])
@api_admin_required
def audit_log(request):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    event_type = request.GET.get("event_type")
    queryset = AuditEvent.objects.all()
    if event_type:
        queryset = queryset.filter(event_type=event_type)
    items = [
        {
            "id": str(item.id),
            "event_type": item.event_type,
            "actor": str(item.actor_user_id_id) if item.actor_user_id_id else None,
            "target": str(item.target_user_id_id) if item.target_user_id_id else None,
            "metadata": item.metadata,
            "created_at": item.created_at.isoformat(),
        }
        for item in queryset[:200]
    ]
    return json_response({"events": items})


@api_endpoint(["GET"])
@api_admin_required
def reports(request):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    items = [
        {
            "id": str(item.id),
            "category": item.category,
            "status": item.status,
            "target": str(item.target_id) if item.target_id else None,
            "created_at": item.created_at.isoformat(),
        }
        for item in Report.objects.all()[:100]
    ]
    return json_response({"reports": items})


@api_endpoint(["POST"])
@api_admin_required
def resolve_report(request, report_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    body = json_body(request)
    status = body.get("status", Report.Status.ACTIONED)
    if status not in Report.Status.values:
        raise ApiError(400, "invalid_status", "Unknown report status.")

    report_obj = _get_or_404(Report, report_id, "report")
    report_obj.status = status
    report_obj.reviewed_at = timezone.now()
    report_obj.reviewed_by = request.api_user
    report_obj.save(update_fields=["status", "reviewed_at", "reviewed_by"])

    _admin_audit(request, "report_resolve", target=report_obj.target, status=status)
    return json_response({"report": {"id": str(report_obj.id), "status": report_obj.status}})


@api_endpoint(["GET"])
@api_admin_required
def purchase_claims(request):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    status = request.GET.get("status", PurchaseClaim.Status.PENDING)
    queryset = PurchaseClaim.objects.select_related("user", "purchase").all()
    if status:
        queryset = queryset.filter(status=status)
    items = [
        {
            "id": str(item.id),
            "user": _serialize_user(item.user),
            "purchase": {
                "id": str(item.purchase_id),
                "provider": item.purchase.provider,
                "status": item.purchase.status,
                "amount": item.purchase.amount,
            },
            "status": item.status,
            "created_at": item.created_at.isoformat(),
        }
        for item in queryset[:100]
    ]
    return json_response({"claims": items})


@api_endpoint(["POST"])
@api_admin_required
def approve_purchase_claim(request, claim_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    claim = _get_or_404(PurchaseClaim, claim_id, "claim")
    try:
        commerce_services.approve_claim(claim, request.api_user)
    except commerce_services.ClaimError as exc:
        raise ApiError(409, "claim_resolved", str(exc))
    claim.refresh_from_db()
    _admin_audit(request, "purchase_claim_approve", target=claim.user, claim=str(claim.id))
    return json_response({"claim": {"id": str(claim.id), "status": claim.status}})


@api_endpoint(["POST"])
@api_admin_required
def reject_purchase_claim(request, claim_id):
    enforce(request, "admin", scope=f"user:{request.api_user.pk}")
    body = json_body(request)
    claim = _get_or_404(PurchaseClaim, claim_id, "claim")
    try:
        commerce_services.reject_claim(claim, request.api_user, body.get("note", ""))
    except commerce_services.ClaimError as exc:
        raise ApiError(409, "claim_resolved", str(exc))
    claim.refresh_from_db()
    _admin_audit(request, "purchase_claim_reject", target=claim.user, claim=str(claim.id))
    return json_response({"claim": {"id": str(claim.id), "status": claim.status}})
