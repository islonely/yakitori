from django.contrib import admin

from .models import Profile, ReservedUsername, UsernameChange


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = (
        "username",
        "display_name",
        "profile_visibility",
        "stats_visibility",
        "leaderboard_visibility",
    )
    list_filter = ("profile_visibility", "stats_visibility", "leaderboard_visibility")
    search_fields = ("username", "display_name", "user__email")
    readonly_fields = ("username_normalized", "created_at", "updated_at")


@admin.register(UsernameChange)
class UsernameChangeAdmin(admin.ModelAdmin):
    list_display = ("profile", "old_username", "new_username", "created_at")
    search_fields = ("old_username", "new_username", "profile__username")


@admin.register(ReservedUsername)
class ReservedUsernameAdmin(admin.ModelAdmin):
    list_display = ("name", "reason", "created_at")
    search_fields = ("name",)
