import SwiftUI
import SwiftData

/// First-launch onboarding: name, handicap, favorite courses, then explore-or-play. Each step is
/// its own screen with exactly one question — nothing to scroll past, nothing to skip over by
/// accident.
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext

    enum FinishAction {
        case explore
        case startRound(OpenGolfCourse?)
    }

    let onFinish: (FinishAction) -> Void

    @State private var path = NavigationPath()
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var handicap: Double?
    @State private var favorites: [OpenGolfCourse] = []

    private enum Step: Hashable { case handicap, favorites, finish }

    private var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingNameStep(firstName: $firstName, lastName: $lastName) { path.append(Step.handicap) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .handicap:
                        OnboardingHandicapStep(handicap: $handicap) { path.append(Step.favorites) }
                    case .favorites:
                        OnboardingFavoritesStep(favorites: $favorites) { path.append(Step.finish) }
                    case .finish:
                        OnboardingFinishStep(name: firstName, firstFavorite: favorites.first) { action in complete(with: action) }
                    }
                }
        }
        .interactiveDismissDisabled()
    }

    private func complete(with action: FinishAction) {
        let me = PlayerRecord(name: fullName.isEmpty ? "Me" : fullName, handicapIndex: handicap)
        modelContext.insert(me)
        // Remembered so every future round can default this seat in automatically — the whole
        // point of onboarding asking your name once instead of every round asking again.
        UserDefaults.standard.set(me.id.uuidString, forKey: "myPlayerID")
        for course in favorites {
            modelContext.insert(FavoriteCourseRecord(
                openGolfID: course.id, name: course.name, city: course.city, state: course.state
            ))
        }
        try? modelContext.save()
        onFinish(action)
    }
}

// MARK: - Shared onboarding text

/// Onboarding runs at arm's length on the first tee — big and willing to wrap beats compact.
private func onboardingHeadline(_ text: String) -> some View {
    Text(text)
        .font(RoundPlayFont.archivo(38, .black))
        .tracking(-1)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
}

private func onboardingSubtitle(_ text: String) -> some View {
    Text(text)
        .font(RoundPlayFont.archivo(18))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
}

// MARK: - Step 1: name

private struct OnboardingNameStep: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onContinue: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field { case first, last }

    private var trimmedFirst: String { firstName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "flag.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(RoundPlayColors.accent)

            onboardingHeadline("What's your name?")
                .padding(.horizontal, 24)
            onboardingSubtitle("So your scores and money are yours, not \"Player 1.\"")
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                TextField("First name", text: $firstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .first)
                    .multilineTextAlignment(.center)
                    .font(RoundPlayFont.archivo(21, .semiBold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RoundPlayColors.fillSecondary))
                    .submitLabel(.next)
                    .onSubmit { focusedField = .last }

                TextField("Last name (optional)", text: $lastName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .last)
                    .multilineTextAlignment(.center)
                    .font(RoundPlayFont.archivo(21, .semiBold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RoundPlayColors.fillSecondary))
                    .submitLabel(.next)
                    .onSubmit { if !trimmedFirst.isEmpty { onContinue() } }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()

            Button(action: onContinue) {
                Text("Next")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoundPlayColors.accent)
            .disabled(trimmedFirst.isEmpty)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
        .onAppear { focusedField = .first }
    }
}

// MARK: - Step 2: handicap

private struct OnboardingHandicapStep: View {
    @Binding var handicap: Double?
    let onContinue: () -> Void

    /// `nil` represented as -1 on the wheel; every other value is a whole-number handicap 0...40.
    private var wheelValue: Binding<Int> {
        Binding(
            get: { handicap.map { Int($0.rounded()) } ?? -1 },
            set: { handicap = $0 < 0 ? nil : Double($0) }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            onboardingHeadline("What's your handicap?")
                .padding(.horizontal, 24)
            onboardingSubtitle("Optional — it's how strokes get split fairly. Skip it if you don't know it yet.")
                .padding(.horizontal, 32)

            RoundPlayList.plain {
                Picker("Handicap", selection: wheelValue) {
                    Text("No handicap").tag(-1)
                    ForEach(0...40, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .listRowSeparator(.hidden)
            }
            .scrollDisabled(true)
            .frame(height: 216)

            Spacer()

            Button(action: onContinue) {
                Text("Next")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoundPlayColors.accent)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Step 3: favorite courses

private struct OnboardingFavoritesStep: View {
    @Binding var favorites: [OpenGolfCourse]
    let onContinue: () -> Void

    @State private var catalog = OpenGolfCourseCatalog.shared
    @State private var locator = NearbyCourseLocator()
    @State private var searchText = ""

    private var results: [OpenGolfCourse] {
        if !searchText.isEmpty { return catalog.search(searchText) }
        if case .located(let location) = locator.state { return catalog.nearest(to: location, limit: 15) }
        return []
    }

    var body: some View {
        RoundPlayList.plain {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Favorite courses?")
                        .font(RoundPlayFont.archivo(32, .black))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Optional — pick the ones you play most. You can search even without sharing your location.")
                        .font(RoundPlayFont.archivo(16))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search courses", text: $searchText)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(RoundPlayColors.fillSecondary))

                    Button {
                        locator.requestLocation()
                    } label: {
                        Label("Courses near me", systemImage: "location.fill")
                            .font(RoundPlayFont.archivo(15, .semiBold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(RoundPlayColors.accent)
                }
                .listRowSeparator(.hidden)
            }

            if catalog.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(results.prefix(20)) { course in
                    Button {
                        toggle(course)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                RoundPlayTypography.headline(course.name)
                                if let cityState = course.cityState {
                                    Text(cityState)
                                        .font(RoundPlayFont.archivo(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: isFavorite(course) ? "star.fill" : "star")
                                .foregroundStyle(isFavorite(course) ? RoundPlayColors.pin : .secondary)
                        }
                    }
                    .buttonStyle(RoundPlayRowButtonStyle())
                    .roundPlayListRowSeparatorFullWidth()
                }
            }
        }
        .task { await catalog.load() }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text(favorites.isEmpty ? "Skip" : "Next")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoundPlayColors.accent)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func isFavorite(_ course: OpenGolfCourse) -> Bool {
        favorites.contains { $0.id == course.id }
    }

    private func toggle(_ course: OpenGolfCourse) {
        if isFavorite(course) {
            favorites.removeAll { $0.id == course.id }
        } else {
            favorites.append(course)
        }
    }
}

// MARK: - Step 4: explore or play

private struct OnboardingFinishStep: View {
    let name: String
    let firstFavorite: OpenGolfCourse?
    let onChoose: (OnboardingFlowView.FinishAction) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(RoundPlayColors.accent)

            onboardingHeadline("You're set, \(name.isEmpty ? "golfer" : name).")
                .padding(.horizontal, 24)

            Spacer()
            Spacer()

            Button {
                onChoose(.startRound(firstFavorite))
            } label: {
                Text("Start a Round")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(RoundPlayColors.accent)
            .padding(.horizontal, 24)

            Button {
                onChoose(.explore)
            } label: {
                Text("Just Look Around")
                    .font(RoundPlayFont.archivo(17, .semiBold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            .tint(RoundPlayColors.accent)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
    }
}

#Preview("Light") {
    OnboardingFlowView { _ in }.modelContainer(PreviewData.container)
}

#Preview("Dark") {
    OnboardingFlowView { _ in }
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
