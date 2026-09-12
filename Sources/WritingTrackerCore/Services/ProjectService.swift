import Foundation

public final class ProjectService {
    private let database: Database
    private let projectRepository: ProjectRepository
    private let documentRepository: DocumentRepository
    private let milestoneRepository: MilestoneRepository
    private let ruleRepository: AssociationRuleRepository

    public init(database: Database) {
        self.database = database
        self.projectRepository = ProjectRepository(database: database)
        self.documentRepository = DocumentRepository(database: database)
        self.milestoneRepository = MilestoneRepository(database: database)
        self.ruleRepository = AssociationRuleRepository(database: database)
    }

    // MARK: - Projects

    @discardableResult
    public func createProject(
        title: String,
        type: ProjectType = .novel,
        description: String? = nil,
        targetWordCount: Int? = nil,
        startingWordCount: Int = 0,
        deadline: Date? = nil,
        autoCreateMilestones: Bool = true
    ) throws -> Project {
        var project = Project(
            title: title,
            type: type,
            description: description,
            status: .planning,
            targetWordCount: targetWordCount,
            startingWordCount: startingWordCount,
            currentWordCount: startingWordCount,
            deadline: deadline,
            startedAt: Date()
        )
        try projectRepository.insert(project)
        if autoCreateMilestones, let target = targetWordCount, target > 0 {
            try createDefaultMilestones(for: project, target: target)
        }
        project = try projectRepository.find(id: project.id) ?? project
        return project
    }

    public func update(_ project: Project) throws {
        var updated = project
        if updated.status.isCompleted, updated.completedAt == nil {
            updated.completedAt = Date()
        }
        if updated.status == .archived, updated.archivedAt == nil {
            updated.archivedAt = Date()
        }
        try projectRepository.update(updated)
    }

    public func delete(projectID: String) throws {
        try projectRepository.delete(id: projectID)
    }

    public func archive(projectID: String) throws {
        guard var project = try projectRepository.find(id: projectID) else { return }
        project.status = .archived
        project.archivedAt = Date()
        try projectRepository.update(project)
    }

    public func allProjects(includeArchived: Bool = true) throws -> [Project] {
        try projectRepository.all(includeArchived: includeArchived)
    }

    public func activeProjects() throws -> [Project] {
        try projectRepository.active()
    }

    public func completedProjects() throws -> [Project] {
        try projectRepository.completed()
    }

    public func project(id: String) throws -> Project? {
        try projectRepository.find(id: id)
    }

    /// Recomputes a project's current word count from the latest snapshot or,
    /// failing that, from its starting count plus the net change of its sessions.
    public func recalculateCurrentWordCount(projectID: String) throws {
        guard try projectRepository.find(id: projectID) != nil else { return }
        ProjectWordCountCalculator.recompute(projectID: projectID, database: database)
    }

    // MARK: - Milestones

    @discardableResult
    public func createDefaultMilestones(for project: Project, target: Int) throws -> [Milestone] {
        let existing = try milestoneRepository.milestones(forProject: project.id)
        guard existing.isEmpty else { return existing }
        let fractions: [(String, Double)] = [
            ("25,000 words", 0.25), ("50,000 words", 0.5),
            ("75,000 words", 0.75), ("\(target.formatted()) words", 1.0)
        ]
        var created: [Milestone] = []
        for (title, fraction) in fractions {
            let milestone = Milestone(
                projectID: project.id,
                title: fraction >= 1.0 ? "Reach target" : title,
                targetValue: Double(target) * fraction,
                metric: .words
            )
            try milestoneRepository.insert(milestone)
            created.append(milestone)
        }
        return created
    }

    @discardableResult
    public func addMilestone(projectID: String, title: String, targetValue: Double? = nil, metric: GoalMetric? = .words) throws -> Milestone {
        let milestone = Milestone(projectID: projectID, title: title, targetValue: targetValue, metric: metric)
        try milestoneRepository.insert(milestone)
        return milestone
    }

    public func milestones(forProject projectID: String) throws -> [Milestone] {
        try milestoneRepository.milestones(forProject: projectID)
    }

    public func completeMilestone(id: String, at date: Date = Date()) throws {
        guard var milestone = try milestoneRepository.find(id: id) else { return }
        milestone.completedAt = date
        try milestoneRepository.update(milestone)
    }

    public func reopenMilestone(id: String) throws {
        guard var milestone = try milestoneRepository.find(id: id) else { return }
        milestone.completedAt = nil
        try milestoneRepository.update(milestone)
    }

    public func deleteMilestone(id: String) throws {
        try milestoneRepository.delete(id: id)
    }

    /// Marks word-count milestones complete when the project passes them.
    public func evaluateMilestones(projectID: String, currentWordCount: Int) throws {
        let milestones = try milestoneRepository.milestones(forProject: projectID)
        for var milestone in milestones where milestone.metric == .words && milestone.completedAt == nil {
            if let target = milestone.targetValue, Double(currentWordCount) >= target {
                milestone.completedAt = Date()
                try milestoneRepository.update(milestone)
            }
        }
    }

    // MARK: - Association rules

    @discardableResult
    public func addRule(projectID: String, type: AssociationRule.RuleType, value: String) throws -> AssociationRule {
        let rule = AssociationRule(projectID: projectID, type: type, value: value)
        try ruleRepository.insert(rule)
        return rule
    }

    public func rules(forProject projectID: String) throws -> [AssociationRule] {
        try ruleRepository.rules(forProject: projectID)
    }

    public func deleteRule(id: String) throws {
        try ruleRepository.delete(id: id)
    }

    // MARK: - Documents

    public func documents(forProject projectID: String) throws -> [Document] {
        try documentRepository.documents(forProject: projectID)
    }

    public func assignDocument(documentID: String, toProject projectID: String?) throws {
        try documentRepository.assignProject(documentID: documentID, projectID: projectID)
    }

    public func allDocuments() throws -> [Document] {
        try documentRepository.all()
    }
}
