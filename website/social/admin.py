from django.contrib import admin

from .models import Block, Follow, Report


@admin.register(Follow)
class FollowAdmin(admin.ModelAdmin):
    list_display = ("follower", "followed", "created_at")
    search_fields = ("follower__email", "followed__email")


@admin.register(Block)
class BlockAdmin(admin.ModelAdmin):
    list_display = ("blocker", "blocked", "created_at")
    search_fields = ("blocker__email", "blocked__email")


@admin.register(Report)
class ReportAdmin(admin.ModelAdmin):
    list_display = ("target", "category", "status", "created_at", "reviewed_by")
    list_filter = ("status", "category")
    search_fields = ("target__email", "reporter__email")
    readonly_fields = ("id", "created_at")
