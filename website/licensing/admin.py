from django.contrib import admin

from .models import Installation, License
from .services import set_license_status


@admin.register(License)
class LicenseAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "product", "license_type", "status", "purchased_at")
    list_filter = ("status", "license_type", "product")
    search_fields = ("user__email", "id")
    readonly_fields = ("id", "created_at", "updated_at", "payment_purchase")
    actions = ("revoke_licenses", "restore_licenses")

    @admin.action(description="Revoke selected licenses")
    def revoke_licenses(self, request, queryset):
        for license_obj in queryset:
            set_license_status(
                license_obj,
                License.Status.REVOKED,
                actor=request.user,
                reason="admin",
            )

    @admin.action(description="Restore selected licenses")
    def restore_licenses(self, request, queryset):
        for license_obj in queryset:
            set_license_status(
                license_obj,
                License.Status.ACTIVE,
                actor=request.user,
            )


@admin.register(Installation)
class InstallationAdmin(admin.ModelAdmin):
    list_display = (
        "installation_id",
        "user",
        "platform",
        "app_version",
        "last_seen_at",
        "revoked_at",
    )
    list_filter = ("platform",)
    search_fields = ("installation_id", "user__email")
    readonly_fields = ("id", "installation_id", "first_seen_at", "created_at")
