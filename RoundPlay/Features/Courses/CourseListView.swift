import SwiftUI
import SwiftData
import CoreLocation

/// Find a course — nearest, favorited, recently played, or searched from the bundled OpenGolf
/// catalog. Manual entry (`CourseEntryView`) is the fallback for a course the catalog doesn't
/// have, not the default path anymore.
struct CourseListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\CourseRecord.lastPlayedAt, order: .reverse),
                  SortDescriptor(\CourseRecord.name)])
    private var recentCourses: [CourseRecord]

    @Query(sort: \FavoriteCourseRecord.favoritedAt, order: .reverse)
    private var favorites: [FavoriteCourseRecord]

    @State private var catalog = OpenGolfCourseCatalog.shared
    @State private var locator = NearbyCourseLocator()
    @State private var searchText = ""
    @State private var isAddingCourse = false
    @State private var catalogCourseToVerify: OpenGolfCourse?

    /// False when reused as a standalone "change the course" sheet (e.g. Play Again) rather than
    /// step 1 of the round builder — hides the "Step 1 of 6" chrome that wouldn't make sense there.
    var showsStepHeader: Bool = true
    let onSelect: (CourseRecord) -> Void

    private var searchResults: [OpenGolfCourse] {
        catalog.search(searchText, nearestTo: searchLocation)
    }

    private var favoriteSearchResults: [OpenGolfCourse] {
        let favoriteIDs = Set(favorites.map(\.openGolfID))
        return searchResults.filter { favoriteIDs.contains($0.id) }
    }

    private var previouslyPlayedSearchResults: [OpenGolfCourse] {
        let favoriteIDs = Set(favoriteSearchResults.map(\.id))
        let playedIDs = Set(recentCourses.compactMap(\.openGolfID))
        return searchResults.filter {
            !favoriteIDs.contains($0.id) && playedIDs.contains($0.id)
        }
    }

    private var otherSearchResults: [OpenGolfCourse] {
        let prioritizedIDs = Set(favoriteSearchResults.map(\.id) + previouslyPlayedSearchResults.map(\.id))
        return searchResults.filter { !prioritizedIDs.contains($0.id) }
    }

    private var searchLocation: CLLocation? {
        guard case .located(let location) = locator.state else { return nil }
        return location
    }

    private var nearestCourses: [OpenGolfCourse] {
        guard case .located(let location) = locator.state else { return [] }
        return catalog.nearest(to: location, limit: 10)
    }

    /// `recentCourses` can carry pre-existing duplicate rows for the same catalog course from
    /// before `selectCatalogCourse` started reusing an existing record — collapse those here so a
    /// course already played doesn't show up twice, without touching the underlying data.
    private var dedupedRecentCourses: [CourseRecord] {
        var seenOpenGolfIDs = Set<String>()
        return recentCourses.filter { course in
            guard let openGolfID = course.openGolfID else { return true }
            return seenOpenGolfIDs.insert(openGolfID).inserted
        }
    }

    var body: some View {
        RoundPlayList.plain {
            if showsStepHeader {
                RoundBuilderStepHeader(step: 1, totalSteps: 6, title: "What course are you playing?")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search courses", text: $searchText)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RoundPlayColors.fillSecondary))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))

            if catalog.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading courses…")
                    Spacer()
                }
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
            } else if !searchText.isEmpty {
                searchSection
            } else {
                favoritesSection
                nearestSection
                recentSection
            }

            Section {
                Button("Can't find it? Add manually", systemImage: "plus.circle") { isAddingCourse = true }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    RoundPlayTypography.caption("30 seconds off the physical scorecard, then it's shared with everyone.")
                    RoundPlayTypography.caption("Course data from OpenGolf, ODbL licensed.")
                }
                .foregroundStyle(.secondary)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(showsStepHeader ? "" : "Course")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await catalog.load()
            locator.requestLocation()
        }
        .sheet(isPresented: $isAddingCourse) {
            NavigationStack {
                CourseEntryView { course in onSelect(course) }
            }
        }
        .sheet(item: $catalogCourseToVerify) { course in
            NavigationStack {
                CourseEntryView(
                    model: CourseEntryModel(prefilledFrom: course),
                    openGolfID: course.id
                ) { record in onSelect(record) }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if catalog.isLoaded && searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            if !favoriteSearchResults.isEmpty {
                Section {
                    ForEach(favoriteSearchResults) { course in
                        catalogRow(course)
                    }
                } header: {
                    courseSectionHeader("Favorites")
                }
            }

            if !previouslyPlayedSearchResults.isEmpty {
                Section {
                    ForEach(previouslyPlayedSearchResults) { course in
                        catalogRow(course)
                    }
                } header: {
                    courseSectionHeader("Previously Played")
                }
            }

            Section {
                ForEach(otherSearchResults.prefix(30)) { course in
                    catalogRow(course)
                }
            } header: {
                courseSectionHeader(searchLocation == nil ? "Results" : "Nearest Results")
            }
        }
    }

    @ViewBuilder
    private var nearestSection: some View {
        switch locator.state {
        case .located where !nearestCourses.isEmpty:
            Section {
                ForEach(nearestCourses.prefix(5)) { course in
                    catalogRow(course)
                }
            } header: {
                courseSectionHeader("Nearby")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !favorites.isEmpty {
            Section {
                ForEach(favorites) { favorite in
                    if let course = catalog.course(id: favorite.openGolfID) {
                        catalogRow(course)
                    }
                }
            } header: {
                courseSectionHeader("Favorites")
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !dedupedRecentCourses.isEmpty {
            Section {
                ForEach(dedupedRecentCourses) { course in
                    HStack(spacing: 8) {
                        Button {
                            onSelect(course)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundPlayTypography.headline(course.name)
                                    Text("Par \(course.totalPar) · 18 holes")
                                        .font(RoundPlayFont.archivo(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RoundPlayRowButtonStyle())

                        // Only courses imported from the catalog can be favorited — a manually
                        // entered course has no `openGolfID` for `FavoriteCourseRecord` to key on.
                        if let openGolfID = course.openGolfID {
                            Button {
                                toggleFavorite(openGolfID: openGolfID, name: course.name)
                            } label: {
                                Image(systemName: isFavorite(openGolfID) ? "star.fill" : "star")
                                    .foregroundStyle(isFavorite(openGolfID) ? RoundPlayColors.pin : .secondary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .roundPlayListRowSeparatorFullWidth()
                }
            } header: {
                courseSectionHeader("Recently Played")
            }
        }
    }

    private func isFavorite(_ openGolfID: String) -> Bool {
        favorites.contains { $0.openGolfID == openGolfID }
    }

    private func toggleFavorite(openGolfID: String, name: String) {
        if let existing = favorites.first(where: { $0.openGolfID == openGolfID }) {
            modelContext.delete(existing)
        } else if let catalogCourse = catalog.course(id: openGolfID) {
            modelContext.insert(FavoriteCourseRecord(
                openGolfID: openGolfID, name: catalogCourse.name, city: catalogCourse.city, state: catalogCourse.state
            ))
        } else {
            modelContext.insert(FavoriteCourseRecord(openGolfID: openGolfID, name: name, city: nil, state: nil))
        }
        try? modelContext.save()
    }

    private func courseSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(RoundPlayFont.archivo(17, .bold))
            .foregroundStyle(RoundPlayColors.accent)
            .textCase(nil)
    }

    private func catalogRow(_ course: OpenGolfCourse) -> some View {
        CatalogCourseRow(
            course: course,
            isFavorite: favorites.contains { $0.openGolfID == course.id },
            distance: distanceLabel(to: course)
        ) {
            selectCatalogCourse(course)
        } onToggleFavorite: {
            toggleFavorite(course)
        }
        .roundPlayListRowSeparatorFullWidth()
    }

    /// Catalog rows open the scorecard review. Sparse source data must never silently become
    /// authoritative par or stroke-index data used for net wagers.
    private func selectCatalogCourse(_ course: OpenGolfCourse) {
        if let existing = recentCourses.first(where: { $0.openGolfID == course.id }) {
            onSelect(existing)
            return
        }
        catalogCourseToVerify = course
    }

    private func distanceLabel(to course: OpenGolfCourse) -> String? {
        guard case .located(let location) = locator.state else { return nil }
        let miles = location.distance(from: CLLocation(latitude: course.latitude, longitude: course.longitude)) / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func toggleFavorite(_ course: OpenGolfCourse) {
        if let existing = favorites.first(where: { $0.openGolfID == course.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteCourseRecord(
                openGolfID: course.id, name: course.name, city: course.city, state: course.state
            ))
        }
        try? modelContext.save()
    }
}

/// One catalog course: name, location, distance if known, and a favorite star.
private struct CatalogCourseRow: View {
    let course: OpenGolfCourse
    let isFavorite: Bool
    let distance: String?
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        RoundPlayTypography.headline(course.name)
                        HStack(spacing: 6) {
                            if let cityState = course.cityState {
                                Text(cityState)
                                    .font(RoundPlayFont.archivo(13))
                                    .foregroundStyle(.secondary)
                            }
                            if let distance {
                                RoundPlayTypography.eyebrow(distance)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RoundPlayRowButtonStyle())

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? RoundPlayColors.pin : .secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Light") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
}

#Preview("Dark") {
    NavigationStack { CourseListView { _ in } }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
