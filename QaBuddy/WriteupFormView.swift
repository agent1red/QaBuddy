//
//  WriteupFormView.swift
//  QA Buddy PU/NC Template System - Write-up Form View
//  Phase 3.2 - Subtask 2.1: Create Dynamic Write-up Form View
//
//  This view dynamically adapts to inspection templates, integrates coordinate system switching,
//  displays photo attachments with sequence numbers, and provides auto-save functionality.
//  Follows the established patterns of TemplateLibraryView and TemplateDetailView.
//

import SwiftUI
import CoreData
import Combine
import UIKit

struct WriteupFormView: View {
    @ObservedObject var template: InspectionTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    // Manager integrations
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var templateManager = TemplateManager.shared
    @StateObject private var coordinateSystemManager = CoordinateSystemManager.shared

    // Form state management
    @State private var writeup: PUWriteup
    @State private var formData = WriteupFormData()
    @State private var selectedPhotos: Set<Photo> = []
    @State private var showingPhotoSelector = false
    @State private var validationErrors: [String: String] = [:]
    @State private var isSavingDraft = false
    @State private var showingCoordinateToggle = false
    @State private var isAutoSaving = false

    // Auto-save functionality with validation gates
    @State private var autoSaveTimer: Timer?
    @State private var hasUnsavedChanges = false
    @State private var consecutiveSaveFailures = 0
    @State private var autoSavePausedUntil: Date?
    @State private var lastSaveTimestamp: Date?

    // Draft cache to prevent constant DB queries
    @State private var cachedDraftId: UUID?

    // Navigation state
    @State private var selectedTab: Int? = nil // For callback navigation

    // Load/create writeup on appear
    init(template: InspectionTemplate, selectedTab: Binding<Int?>? = nil) {
        self.template = template
        self._selectedTab = State(initialValue: selectedTab?.wrappedValue)

        // Check cache first for faster lookup
        if let cachedDraft = Self.getCachedDraftFor(template: template) {
            self._writeup = State(initialValue: cachedDraft)
            print("⚡ Using cached draft: \(cachedDraft.id?.uuidString ?? "unknown")")
        } else {
            // Check database for existing draft
            let context = PersistenceController.shared.container.viewContext
            let existingDraft = Self.findExistingDraft(template: template, context: context)

            if let draft = existingDraft {
                // Cache the draft for future lookups
                Self.cacheDraft(draft, forTemplate: template)
                // Use existing draft
                self._writeup = State(initialValue: draft)
                print("📝 Using existing draft from database")
            } else {
                // Create new draft only if none exists
                let newWriteup = PUWriteup(context: context)
                newWriteup.id = UUID()
                // CRITICAL: Set required itemId to fix validation failures - Swift 6 pattern
                newWriteup.itemId = Int64(Date().timeIntervalSince1970) // Use timestamp as unique ID
                newWriteup.template = template
                newWriteup.status = "draft"
                newWriteup.createdDate = Date()
                // Use shared singletons directly in init to avoid @StateObject access before initialization
                newWriteup.coordinateSystem = CoordinateSystemManager.shared.isVelocitySystem ? "Velocity" : "CMES"
                newWriteup.session = SessionManager.shared.activeSession

                // Cache the new draft
                Self.cacheDraft(newWriteup, forTemplate: template)
                self._writeup = State(initialValue: newWriteup)
                print("🆕 Created and cached new draft")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                formHeaderSection
                coordinateSystemSection
                photoAttachmentSection
                dynamicFieldsSection
                validationSection
            }
            .navigationTitle("Write-up Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveAndClose) {
                        Text(isSavingDraft ? "Saving..." : "Save Draft")
                            .foregroundColor(.green)
                    }
                }
            }
            .sheet(isPresented: $showingPhotoSelector) {
                PhotoSelectorSheet(selectedPhotos: $selectedPhotos, writeup: writeup)
            }
            .task {
                setupAutoSave()
                // loadExistingDraft() is not async
                loadExistingDraft()
                initializeFormData()
                // prepareSessionInfo() is async
                await prepareSessionInfo()
            }
            .onDisappear {
                cleanupAutoSave()
                Task { await saveDraftSilently() }
            }
        }
    }

    // MARK: - Form Sections

    private var formHeaderSection: some View {
        Section(header: Text("Session Context")) {
            if let session = sessionManager.activeSession {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name ?? "Unnamed Session")
                            .font(.headline)

                        if let tailNumber = session.aircraftTailNumber {
                            Text("Aircraft: \(tailNumber)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if sessionManager.isZoneBasedSession {
                            Text("Zone-based inspection")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Activity-based inspection")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        if session.totalPhotos > 0 {
                            Text("\(session.totalPhotos) photos available")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No active session")
                    .foregroundColor(.red)
                    .italic()
            }
        }
    }

    private var coordinateSystemSection: some View {
        Section(header: Text("Coordinate System")) {
            HStack {
                Text("Current System:")
                    .font(.subheadline)
                Spacer()

                Button(action: {
                    withAnimation {
                        showingCoordinateToggle.toggle()
                    }
                }) {
                    HStack {
                        Text(coordinateSystemManager.isVelocitySystem ? "Velocity (X/Y/Z)" : "CMES (STA/WL/BL)")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showingCoordinateToggle ? 180 : 0))
                    }
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                }
            }

            if showingCoordinateToggle {
                HStack(spacing: 20) {
                    Button(action: toggleToVelocity) {
                        VStack {
                            Text("Velocity")
                            Text("X / Y / Z")
                                .font(.caption)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(coordinateSystemManager.isVelocitySystem ? Color.green.opacity(0.2) : Color.clear)
                                .stroke(coordinateSystemManager.isVelocitySystem ? Color.green : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(coordinateSystemManager.currentSystem.systemName == "Velocity" ? .green : .primary)
                    }

                    Button(action: toggleToCMES) {
                        VStack {
                            Text("CMES")
                            Text("STA / WL / BL")
                                .font(.caption)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(coordinateSystemManager.isCMESSystem ? Color.blue.opacity(0.2) : Color.clear)
                                .stroke(coordinateSystemManager.isCMESSystem ? Color.blue : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(coordinateSystemManager.currentSystem.systemName == "CMES" ? .blue : .primary)
                    }
                }
                .transition(.slide)
            }
        }
    }

    private var photoAttachmentSection: some View {
        Section(header: HStack {
            Text("Photo Attachments")
            Spacer()
            Text("\(selectedPhotos.count) selected")
                .foregroundColor(.secondary)
                .font(.caption)
        }) {
            if selectedPhotos.isEmpty {
                Button(action: { showingPhotoSelector = true }) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Attach Photos")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(.accentColor)
                }
            } else {
                // Display selected photos in horizontal scroll
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedPhotos).sorted(by: { $0.sequenceNumber < $1.sequenceNumber }), id: \.id) { photo in
                            PhotoAttachmentView(photo: photo)
                        }

                        // Add more photos button
                        Button(action: { showingPhotoSelector = true }) {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                Text("Add More")
                                    .font(.caption)
                            }
                            .foregroundColor(.accentColor)
                            .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var dynamicFieldsSection: some View {
        let fieldConfigs = template.decodedFieldConfigurations.filter { $0.visibility != .hidden }
        return ForEach(fieldConfigs, id: \.fieldName) { config in
            Section {
                DynamicFieldView(
                    config: config,
                    coordinateSystem: coordinateSystemManager.currentSystem,
                    validationError: validationErrors[config.fieldName],
                    formData: $formData
                )
            } header: {
                Text(formFieldLabel(for: config.fieldName))
            }
        }
    }

    private var validationSection: some View {
        Group {
            if !validationErrors.isEmpty {
                Section(header: Text("Validation Issues")) {
                    ForEach(validationErrors.sorted(by: { $0.key < $1.key }), id: \.key) { fieldName, error in
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text(formFieldLabel(for: fieldName))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: validateAndSaveFinal) {
                    Text("Mark as Complete & Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveFinal)
                .tint(canSaveFinal ? .green : .gray)
            }
        }
    }

    // MARK: - Actions

    private func toggleToVelocity() {
        coordinateSystemManager.switchToVelocity()
        writeup.coordinateSystem = "Velocity"
        hasUnsavedChanges = true
        showingCoordinateToggle = false
    }

    private func toggleToCMES() {
        coordinateSystemManager.switchToCMES()
        writeup.coordinateSystem = "CMES"
        hasUnsavedChanges = true
        showingCoordinateToggle = false
    }

    private func saveAndClose() {
        Task {
            await saveDraft()
            dismiss()
        }
    }

    private func validateAndSaveFinal() {
        // Full validation before final save
        validationErrors = ValidationEngine().validate(formData, template: template)
        if validationErrors.isEmpty {
            writeup.status = "pending"
            Task {
                await saveFinal()
                dismiss()
            }
        }
    }

    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Swift 6: Prevent infinite loop - only auto-save if valid and not paused
            if hasUnsavedChanges && canAutoSaveDraft() && !isAutoSavePaused() {
                Task { @MainActor in
                    await saveDraftSilently()
                }
            }
        }
    }

    private func cleanupAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    private func loadExistingDraft() {
        // TODO: Load existing writeup draft if it exists
    }

    private func prepareSessionInfo() async {
        // Refresh session information for accurate display
        let currentSessionInfo = await sessionManager.getCurrentSessionInfo()
        print("📝 Session info prepared: \(currentSessionInfo)")
    }

    private func initializeFormData() {
        // Map PUWriteup to form data for editing
        formData.itemDescription = writeup.itemDescription ?? ""
        formData.irm = writeup.irm ?? ""
        formData.partNumber = writeup.partNumber ?? ""
        formData.location = writeup.location ?? ""
        formData.xCoordinate = writeup.xCoordinate ?? ""
        formData.yCoordinate = writeup.yCoordinate ?? ""
        formData.zCoordinate = writeup.zCoordinate ?? ""
        formData.issue = writeup.issue ?? ""
        formData.shouldBe = writeup.shouldBe ?? ""

        // Load existing photo attachments from writeup
        loadExistingPhotoAttachments()
    }

    private func loadExistingPhotoAttachments() {
        guard let photoIdsString = writeup.photoIds, !photoIdsString.isEmpty else { return }

        let photoIds = photoIdsString.components(separatedBy: ",").filter { !$0.isEmpty }

        // Fetch photos by IDs on background thread and update selectedPhotos on main thread
        Task {
            do {
                let context = PersistenceController.shared.container.viewContext
                let photos = try await context.perform {
                    let fetchRequest = Photo.fetchRequest()
                    // SWIFT 6 FIX: Use string comparison for UUID field instead of UUID object conversion
                    fetchRequest.predicate = NSPredicate(format: "id in %@", photoIds)
                    return try context.fetch(fetchRequest)
                }

                await MainActor.run {
                    selectedPhotos.formUnion(Set(photos))
                    print("✅ Loaded \(photos.count) existing photos for draft")
                }
            } catch {
                print("❌ Error loading existing photos: \(error)")
            }
        }
    }

    private func saveDraftSilently() async {
        await MainActor.run {
            isAutoSaving = true
        }
        defer {
            isAutoSaving = false
            hasUnsavedChanges = false
        }

        // Update writeup on main thread
        await MainActor.run {
            updateWriteupFromForm()
            writeup.status = "draft"
            // Core Data @FetchRequest will handle UI updates automatically
        }

        do {
            // Use direct save on main thread context instead of context.perform for immediate UI updates
            try context.save()
            // Swift 6: Reset failure counter on successful save
            consecutiveSaveFailures = 0
            autoSavePausedUntil = nil
            print("✅ Auto-saved writeup draft (immediatelive UI updates enabled)")

            // SWIF των6 FIX: Proper notification posting with explicit type handling
            NotificationCenter.default.post(
                name: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
                object: context,
                userInfo: [
                    NSUpdatedObjectsKey: [writeup as Any]
                ] as [AnyHashable: Any]
            )
        } catch {
            // Swift 6: Track consecutive failures to prevent infinite loop
            consecutiveSaveFailures += 1
            print("❌ Failed to auto-save draft (\(consecutiveSaveFailures) failures): \(error)")

            // Pause auto-save for 5 minutes after 3 consecutive failures
            if consecutiveSaveFailures >= 3 {
                autoSavePausedUntil = Date().addingTimeInterval(300) // 5 minutes
                print("⏸️ Auto-save paused for 5 minutes due to repeated validation failures")
            }
        }
    }

    private func saveDraft() async {
        await MainActor.run {
            isSavingDraft = true
        }
        defer {
            isSavingDraft = false
        }

        await saveDraftSilently()
    }

    private func saveFinal() async {
        updateWriteupFromForm()
        writeup.status = "pending" // or "completed" based on workflow
        // Removed lastModified (not present in model)

        do {
            try context.save()
            print("✅ Saved writeup as final")

            // Switch to gallery tab to show write-ups
            if let tab = selectedTab {
                // TODO: Implement tab switching callback
                _ = tab
            }
        } catch {
            print("❌ Failed to save final writeup: \(error)")
        }
    }

    private func updateWriteupFromForm() {
        writeup.itemDescription = formData.itemDescription.isEmpty ? nil : formData.itemDescription
        writeup.irm = formData.irm.isEmpty ? nil : formData.irm
        writeup.partNumber = formData.partNumber.isEmpty ? nil : formData.partNumber
        writeup.location = formData.location.isEmpty ? nil : formData.location
        writeup.xCoordinate = formData.xCoordinate.isEmpty ? nil : formData.xCoordinate
        writeup.yCoordinate = formData.yCoordinate.isEmpty ? nil : formData.yCoordinate
        writeup.zCoordinate = formData.zCoordinate.isEmpty ? nil : formData.zCoordinate
        writeup.issue = formData.issue.isEmpty ? nil : formData.issue
        writeup.shouldBe = formData.shouldBe.isEmpty ? nil : formData.shouldBe

        // Update photo IDs
        let photoIds = selectedPhotos.map { $0.id?.uuidString ?? "" }.joined(separator: ",")
        writeup.photoIds = photoIds.isEmpty ? nil : photoIds
    }

    private func formFieldLabel(for fieldName: String) -> String {
        switch fieldName {
        case "itemDescription": return "Item Description"
        case "irm": return "IRM"
        case "partNumber": return "Part Number"
        case "shouldBe": return "Should Be"
        case "xCoordinate": return coordinateSystemManager.isVelocitySystem ? "X Coordinate" : "STA"
        case "yCoordinate": return coordinateSystemManager.isVelocitySystem ? "Y Coordinate" : "WL"
        case "zCoordinate": return coordinateSystemManager.isVelocitySystem ? "Z Coordinate" : "BL"
        default: return fieldName.capitalized
        }
    }

    private var canSaveFinal: Bool {
        !formData.issue.isEmpty && !formData.location.isEmpty && validationErrors.isEmpty
    }

    // MARK: - Auto-save Validation Gates

    /// Swift 6: Prevent infinite loop by checking if draft can be safely auto-saved
    private func canAutoSaveDraft() -> Bool {
        // Don't auto-save if core required fields are still empty (causing validation failures)
        let hasIssue = !formData.issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasLocation = !formData.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasIssue && hasLocation
    }

    /// Check if auto-save is temporarily paused due to consecutive failures
    private func isAutoSavePaused() -> Bool {
        guard let pauseUntil = autoSavePausedUntil else { return false }
        return Date() < pauseUntil
    }

    /// Manual trigger for retrying after pause period
    private func resetAutoSaveIfNeeded() {
        if !isAutoSavePaused() && consecutiveSaveFailures >= 3 {
            consecutiveSaveFailures = 0
            autoSavePausedUntil = nil
            print("🔄 Auto-save retry mechanism reset")
        }
    }

    // MARK: - Draft Management

    /// Static cache for draft objects to prevent repeated database queries
    static private var draftCache = [String: PUWriteup]()

    /// Get cached draft for template
    static private func getCachedDraftFor(template: InspectionTemplate) -> PUWriteup? {
        let cacheKey = Self.makeCacheKey(template: template)
        return draftCache[cacheKey]
    }

    /// Cache draft for template
    static private func cacheDraft(_ draft: PUWriteup, forTemplate template: InspectionTemplate) {
        let cacheKey = Self.makeCacheKey(template: template)
        draftCache[cacheKey] = draft
        print("💾 Cached draft \(draft.id?.uuidString ?? "unknown") for cache key: \(cacheKey)")
    }

    /// Clear all cached drafts (call when session changes)
    static func clearDraftCache() {
        draftCache.removeAll()
        print("🧹 Cleared draft cache")
    }

    /// Make cache key from template and session
    private static func makeCacheKey(template: InspectionTemplate) -> String {
        let templateId = template.id?.uuidString ?? "unknown-template"
        let sessionId = SessionManager.shared.activeSession?.id?.uuidString ?? "unknown-session"
        return "\(templateId)-\(sessionId)"
    }

    /// Find existing draft for the same template and session combination with detailed debugging
    private static func findExistingDraft(template: InspectionTemplate, context: NSManagedObjectContext) -> PUWriteup? {
        let templateId = template.id?.uuidString ?? ""
        let sessionId = SessionManager.shared.activeSession?.id?.uuidString ?? ""

        print("🔍 Searching for draft with:")
        print("    TemplateID: \(templateId.isEmpty ? "EMPTY" : templateId)")
        print("    SessionID: \(sessionId.isEmpty ? "EMPTY" : sessionId)")
        print("    Status: draft")

        // Check if IDs are valid
        guard !templateId.isEmpty && !sessionId.isEmpty else {
            print("❌ Cannot search - missing template or session ID")
            return nil
        }

        let fetchRequest = PUWriteup.fetchRequest()

        // SWIFT 6 FIX: Use string comparisons instead of UUID objects for CVarArg compatibility
        let predicates = [
            NSPredicate(format: "template.id == %@", templateId),
            NSPredicate(format: "session.id == %@", sessionId),
            NSPredicate(format: "status == %@", "draft")
        ]

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.fetchLimit = 5 // Get up to 5 to debug duplicates

        do {
            let results = try context.fetch(fetchRequest)
            print("🔍 Found \(results.count) matching drafts in database")

            for (index, draft) in results.enumerated() {
                print("    [\(index)] Draft ID: \(draft.id?.uuidString ?? "no-id") - Template: \(draft.template?.id?.uuidString ?? "no-template") - Session: \(draft.session?.id?.uuidString ?? "no-session")")
            }

            if let existingDraft = results.first {
                print("✅ Using first draft: \(existingDraft.id?.uuidString ?? "unknown")")

                // Clean up extra duplicates if they exist
                if results.count > 1 {
                    print("⚠️  Found \(results.count) duplicate drafts - should consolidate")
                }

                return existingDraft
            }
        } catch {
            print("❌ Error finding existing draft: \(error)")
            print("    Error details: \(error.localizedDescription)")
        }

        print("📝 No existing draft found in database")
        return nil
    }
}

// MARK: - Supporting Views

struct PhotoAttachmentView: View {
    let photo: Photo

    var body: some View {
        VStack {
            // Thumbnail image
            if let thumbnail = photo.thumbnailUIImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        // Sequence number badge
                        SequenceBadge(number: photo.sequenceNumber)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            Text("#\(photo.sequenceNumber)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct SequenceBadge: View {
    let number: Int64

    var body: some View {
        Circle()
            .fill(Color.black.opacity(0.8))
            .frame(width: 20, height: 20)
            .overlay(
                Text("\(number)")
                    .font(.caption2)
                    .foregroundColor(.white)
            )
            .offset(x: -20, y: -20)
    }
}

struct PhotoSelectorSheet: View {
    @Binding var selectedPhotos: Set<Photo>
    let writeup: PUWriteup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PhotoSelectorGrid(selectedPhotos: $selectedPhotos, writeup: writeup)
                .navigationTitle("Select Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Form Data Structures

struct WriteupFormData {
    var itemDescription = ""
    var irm = ""
    var partNumber = ""
    var location = ""
    var xCoordinate = ""
    var yCoordinate = ""
    var zCoordinate = ""
    var issue = ""
    var shouldBe = ""
}

// MARK: - Supporting Structures

struct PhotoSelectorGrid: View {
    @Binding var selectedPhotos: Set<Photo>
    let writeup: PUWriteup
    @StateObject private var photoManager = PhotoManager()

    @State private var sessionPhotos: [Photo] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading photos...")
            } else if sessionPhotos.isEmpty {
                VStack {
                    Image(systemName: "photo.stack")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No photos available")
                        .foregroundColor(.secondary)
                        .padding()
                    Text("Take photos first to attach them to write-ups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
                        ForEach(sessionPhotos.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })) { photo in
                            PhotoGridItem(
                                photo: photo,
                                isBulkSelectionMode: true,
                                isSelected: selectedPhotos.contains(photo),
                                onSelectionToggle: { toggleSelection(for: photo) },
                                onDeleteSingle: {},
                                onAnnotationRequested: {}
                            )
                            .onTapGesture {
                                toggleSelection(for: photo)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            loadSessionPhotos()
        }
    }

    private func loadSessionPhotos() {
        Task {
            await MainActor.run {
                isLoading = true
            }

            do {
                if let sessionId = writeup.session?.id?.uuidString {
                    sessionPhotos = try photoManager.fetchPhotos(forSession: sessionId)
                }
            } catch {
                print("Failed to load session photos: \(error)")
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func toggleSelection(for photo: Photo) {
        if selectedPhotos.contains(photo) {
            selectedPhotos.remove(photo)
        } else {
            selectedPhotos.insert(photo)
        }
    }
}



// MARK: - Validation Engine

@MainActor
class ValidationEngine {
    func validate(_ formData: WriteupFormData, template: InspectionTemplate) -> [String: String] {
        var errors: [String: String] = [:]

        // Get field configurations first (main actor isolated access)
        let fieldConfigs = template.decodedFieldConfigurations

        // Check required fields based on template
        for config in fieldConfigs {
            if config.visibility == .required {
                let fieldValue: String
                switch config.fieldName {
                case "itemDescription": fieldValue = formData.itemDescription
                case "irm": fieldValue = formData.irm
                case "partNumber": fieldValue = formData.partNumber
                case "location": fieldValue = formData.location
                case "xCoordinate": fieldValue = formData.xCoordinate
                case "yCoordinate": fieldValue = formData.yCoordinate
                case "zCoordinate": fieldValue = formData.zCoordinate
                case "issue": fieldValue = formData.issue
                case "shouldBe": fieldValue = formData.shouldBe
                default: fieldValue = ""
                }

                if fieldValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors[config.fieldName] = "\(config.fieldName.displayName) is required"
                }
            }
        }


        // Pattern validation
        for config in fieldConfigs {
            if let pattern = config.validation {
                let fieldValue: String
                switch config.fieldName {
                case "irm": fieldValue = formData.irm
                case "partNumber": fieldValue = formData.partNumber
                default: continue
                }

                if !fieldValue.isEmpty && !NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: fieldValue) {
                    errors[config.fieldName] = "Format does not match expected pattern"
                }
            }
        }

        return errors
    }
}

struct DynamicFieldView: View {
    let config: TemplateFieldConfiguration
    let coordinateSystem: any CoordinateSystem
    let validationError: String?
    @Binding var formData: WriteupFormData

    var body: some View {
        VStack(alignment: .leading) {
            // Field input
            fieldInputView

            // Validation error
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 2)
            }

            // Helper text for empty fields
            if shouldShowHelperText && fieldValue.isEmpty {
                Text(helperText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var fieldInputView: some View {
        if config.visibility == .hidden {
            return AnyView(EmptyView())
        } else {
            return AnyView(
                TextField(fieldPlaceholder, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(config.fieldName == "irm" || config.fieldName == "partNumber")
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .border(validationError != nil ? Color.red : Color.clear, width: validationError != nil ? 1 : 0)
            )
        }
    }

    private var binding: Binding<String> {
        switch config.fieldName {
        case "itemDescription": return $formData.itemDescription
        case "irm": return $formData.irm
        case "partNumber": return $formData.partNumber
        case "location": return $formData.location
        case "xCoordinate": return $formData.xCoordinate
        case "yCoordinate": return $formData.yCoordinate
        case "zCoordinate": return $formData.zCoordinate
        case "issue": return $formData.issue
        case "shouldBe": return $formData.shouldBe
        default: return .constant("")
        }
    }

    private var fieldValue: String {
        switch config.fieldName {
        case "itemDescription": return formData.itemDescription
        case "irm": return formData.irm
        case "partNumber": return formData.partNumber
        case "location": return formData.location
        case "xCoordinate": return formData.xCoordinate
        case "yCoordinate": return formData.yCoordinate
        case "zCoordinate": return formData.zCoordinate
        case "issue": return formData.issue
        case "shouldBe": return formData.shouldBe
        default: return ""
        }
    }

    private var fieldPlaceholder: String {
        switch config.fieldName {
        case "itemDescription": return "Enter item description"
        case "irm": return "Enter IRM number"
        case "partNumber": return "Enter part number"
        case "location": return "Enter location"
        case "xCoordinate": return coordinateSystem.xLabel + " coordinate"
        case "yCoordinate": return coordinateSystem.yLabel + " coordinate"
        case "zCoordinate": return coordinateSystem.zLabel + " coordinate"
        case "issue": return "Describe the issue found"
        case "shouldBe": return "What should be present?"
        default: return "Enter " + config.fieldName.displayName.lowercased()
        }
    }

    private var keyboardType: UIKeyboardType {
        if config.fieldName.contains("Coordinate") || config.fieldName.contains("partNumber") {
            return .numbersAndPunctuation
        }
        return .default
    }

    private var autocapitalization: TextInputAutocapitalization {
        if config.fieldName == "irm" || config.fieldName == "partNumber" {
            return .characters
        }
        return .words
    }

    private var shouldShowHelperText: Bool {
        !config.fieldName.contains("Coordinate") && config.fieldName != "irm" && config.fieldName != "partNumber"
    }

    private var helperText: String {
        if config.fieldName.contains("Coordinate") {
            return "Format: \(coordinateSystem.xLabel)/\(coordinateSystem.yLabel)/\(coordinateSystem.zLabel) - updates when coordinate system changes"
        }
        return ""
    }
}

// MARK: - Extensions

extension Photo {
    var thumbnailUIImage: UIImage? {
        return PhotoManager().loadThumbnail(for: self)
    }
}

extension String {
    var displayName: String {
        switch self {
        case "itemDescription": return "Item Description"
        case "irm": return "IRM"
        case "partNumber": return "Part Number"
        case "shouldBe": return "Should Be"
        case "xCoordinate": return "X Coordinate"
        case "yCoordinate": return "Y Coordinate"
        case "zCoordinate": return "Z Coordinate"
        default: return self.capitalized
        }
    }
}

#Preview {
    let template = InspectionTemplate()
    template.name = "Preview Template"
    template.templateType = "PU"
    return WriteupFormView(template: template)
}

// MARK: - TODOs for Next Implementation
// 1. Implement form data persistence and recovery
// 2. Add zone-aware location prefixing
// 3. Implement form validation with custom patterns
// 4. Add support for calculated formula fields
// 5. Create bulk photo attachment workflow
// 6. Add form export functionality
// 7. Implement write-up status change notifications
