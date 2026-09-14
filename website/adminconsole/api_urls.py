from django.urls import path

from . import api

app_name = "adminconsole-api"

urlpatterns = [
    path("admin/users", api.users, name="users"),
    path("admin/users/<uuid:user_id>", api.user_detail, name="user-detail"),
    path("admin/users/<uuid:user_id>/suspend", api.suspend_user, name="suspend"),
    path("admin/users/<uuid:user_id>/unsuspend", api.unsuspend_user, name="unsuspend"),
    path("admin/licenses/<uuid:license_id>/revoke", api.revoke_license, name="revoke-license"),
    path("admin/licenses/<uuid:license_id>/restore", api.restore_license, name="restore-license"),
    path("admin/webhooks", api.webhooks, name="webhooks"),
    path("admin/audit", api.audit_log, name="audit"),
    path("admin/reports", api.reports, name="reports"),
    path("admin/reports/<uuid:report_id>/resolve", api.resolve_report, name="resolve-report"),
    path("admin/purchase-claims", api.purchase_claims, name="purchase-claims"),
    path("admin/purchase-claims/<uuid:claim_id>/approve", api.approve_purchase_claim, name="approve-claim"),
    path("admin/purchase-claims/<uuid:claim_id>/reject", api.reject_purchase_claim, name="reject-claim"),
]
