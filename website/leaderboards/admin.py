from django.contrib import admin

from .models import LeaderboardAggregate, StatisticSubmission


@admin.register(LeaderboardAggregate)
class LeaderboardAggregateAdmin(admin.ModelAdmin):
    list_display = ("user", "metric", "period", "period_start", "value", "source")
    list_filter = ("metric", "period", "source")
    search_fields = ("user__email",)
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(StatisticSubmission)
class StatisticSubmissionAdmin(admin.ModelAdmin):
    list_display = ("user", "status", "app_version", "submitted_at")
    list_filter = ("status",)
    search_fields = ("user__email",)
    readonly_fields = [field.name for field in StatisticSubmission._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
