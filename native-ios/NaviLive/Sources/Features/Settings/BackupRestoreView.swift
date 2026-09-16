import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
  @ObservedObject var model: AppModel

  @State private var isExporting = false
  @State private var isImporting = false
  @State private var exportDocument: NaviLiveBackupDocument?

  var body: some View {
    Form {
      Section {
        Text(L10n.text("settings.backup.local.description", table: .settings))

        Text(
          L10n.text(
            model.hasLocalRestorePoint
              ? "settings.backup.local.available"
              : "settings.backup.local.empty",
            table: .settings
          )
        )
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.updatesFrequently)

        Button {
          model.saveLocalRestorePoint()
        } label: {
          Label(
            L10n.text("settings.backup.local.save", table: .settings),
            systemImage: "checkmark.circle"
          )
        }

        Button {
          model.restoreLocalRestorePoint()
        } label: {
          Label(
            L10n.text("settings.backup.local.restore", table: .settings),
            systemImage: "arrow.counterclockwise"
          )
        }
        .disabled(!model.hasLocalRestorePoint)
      } header: {
        Text(L10n.text("settings.backup.local.title", table: .settings))
      }

      Section {
        Text(L10n.text("settings.backup.file.description", table: .settings))

        Button {
          prepareExport()
        } label: {
          Label(
            L10n.text("settings.backup.export", table: .settings),
            systemImage: "square.and.arrow.up"
          )
        }

        Button {
          isImporting = true
        } label: {
          Label(
            L10n.text("settings.backup.import", table: .settings),
            systemImage: "square.and.arrow.down"
          )
        }
      } header: {
        Text(L10n.text("settings.backup.file.title", table: .settings))
      }

      if !model.backupStatusMessage.isEmpty {
        Section {
          Text(model.backupStatusMessage)
            .accessibilityElement(children: .combine)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(L10n.text("settings.section.backup", table: .settings))
    .navigationBarTitleDisplayMode(.inline)
    .fileExporter(
      isPresented: $isExporting,
      document: exportDocument,
      contentType: .json,
      defaultFilename: model.suggestedBackupFileName()
    ) { result in
      exportDocument = nil
      model.onBackupExportFinished(result)
    }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: NaviLiveBackupDocument.readableContentTypes
    ) { result in
      switch result {
      case .success(let url):
        do {
          model.importBackupData(try NaviLiveBackupDocument.readData(from: url))
        } catch {
          model.reportBackupError(error)
        }
      case .failure(let error):
        model.reportBackupError(error)
      }
    }
  }

  private func prepareExport() {
    do {
      exportDocument = NaviLiveBackupDocument(data: try model.exportedBackupData())
      isExporting = true
    } catch {
      model.onBackupExportPreparationFailed()
    }
  }
}

#Preview {
  NavigationStack {
    BackupRestoreView(model: AppModel())
  }
}
