from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import ApiToken, DeviceAuthorization, LoginChallenge, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ("email",)
    list_display = ("email", "status", "is_staff", "is_active", "created_at")
    list_filter = ("status", "is_staff", "is_superuser")
    search_fields = ("email",)
    readonly_fields = (
        "email_normalized",
        "created_at",
        "updated_at",
        "last_login",
        "date_joined",
    )

    fieldsets = (
        (None, {"fields": ("email", "password")}),
        (
            "Lifecycle",
            {
                "fields": (
                    "status",
                    "email_verified_at",
                    "deleted_at",
                    "is_active",
                )
            },
        ),
        (
            "Permissions",
            {
                "fields": (
                    "is_staff",
                    "is_superuser",
                    "groups",
                    "user_permissions",
                )
            },
        ),
        ("Dates", {"fields": ("last_login", "date_joined", "created_at", "updated_at")}),
    )

    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": (
                    "email",
                    "password1",
                    "password2",
                    "status",
                    "is_staff",
                    "is_superuser",
                ),
            },
        ),
    )


@admin.register(LoginChallenge)
class LoginChallengeAdmin(admin.ModelAdmin):
    list_display = ("email_normalized", "created_at", "expires_at", "consumed_at", "attempts")
    search_fields = ("email_normalized",)
    readonly_fields = ("token_hash", "code_hash")


@admin.register(ApiToken)
class ApiTokenAdmin(admin.ModelAdmin):
    list_display = ("label", "user", "installation_uuid", "created_at", "last_used_at", "revoked_at")
    search_fields = ("user__email", "label")
    readonly_fields = ("token_hash",)


@admin.register(DeviceAuthorization)
class DeviceAuthorizationAdmin(admin.ModelAdmin):
    list_display = ("user_code", "client_name", "status", "user", "created_at", "expires_at")
    list_filter = ("status",)
    search_fields = ("user_code", "user__email")
    readonly_fields = ("device_code_hash",)
