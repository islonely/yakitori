import Foundation

/// Recomputes a project's headline word count from authoritative data.
///
/// Preference order:
/// 1. The latest native word-count snapshot (absolute manuscript count).
/// 2. The project's starting count plus the net change of its completed sessions
///    (covers manual entries and keystroke-estimated sessions).
///
/// Also completes any word-count milestones the project has passed.
public enum ProjectWordCountCalculator {
    public static func recompute(projectID: String, database: Database) {
        let projectRepository = ProjectRepository(database: database)
        guard var project = try? projectRepository.find(id: projectID) else { return }

        let snapshots = (try? WordCountSnapshotRepository(database: database).snapshots(forProject: projectID)) ?? []
        if let latest = snapshots.last {
            project.currentWordCount = latest.wordCount
        } else {
            let sessions = (try? SessionRepository(database: database).sessions(forProject: projectID)) ?? []
            let net = sessions.filter { $0.endedAt != nil }.reduce(0) { $0 + ($1.netWordChange ?? 0) }
            project.currentWordCount = project.startingWordCount + net
        }
        try? projectRepository.update(project)
        evaluateMilestones(projectID: projectID, currentWordCount: project.currentWordCount, database: database)
    }

    public static func evaluateMilestones(projectID: String, currentWordCount: Int, database: Database) {
        let repository = MilestoneRepository(database: database)
        let milestones = (try? repository.milestones(forProject: projectID)) ?? []
        for var milestone in milestones where milestone.metric == .words && milestone.completedAt == nil {
            if let target = milestone.targetValue, Double(currentWordCount) >= target {
                milestone.completedAt = Date()
                try? repository.update(milestone)
            }
        }
    }
}
